import Foundation
import StoreKit

enum StoreOperation: String, Codable, Equatable, Sendable {
    case loadProducts
    case purchase
    case restore
    case transactionUpdate
}

enum StorePurchaseState: Equatable, Sendable {
    case idle
    case loadingProducts
    case ready
    case purchasing(StoreProductID)
    case pendingApproval(StoreProductID)
    case cancelled
    case restoring
    case restored
    case offlineRetry(StoreOperation)
    case verificationFailed
    case failed(String)
}

@MainActor
final class StoreKitPurchaseController {
    typealias UpdateHandler = @MainActor (StorePurchaseState, EntitlementSnapshot) -> Void

    private let catalog: IAPCatalog
    private let ledger: PurchaseLedgerStore
    private let grantProcessor: PurchaseGrantProcessor
    private var updatesTask: Task<Void, Never>?
    private var retryOperation: StoreOperation?

    private(set) var products: [StoreProductID: Product] = [:]
    private(set) var state: StorePurchaseState = .idle
    private(set) var entitlements: EntitlementSnapshot
    var onUpdate: UpdateHandler?

    init(catalog: IAPCatalog, ledger: PurchaseLedgerStore) {
        self.catalog = catalog
        self.ledger = ledger
        grantProcessor = PurchaseGrantProcessor(ledger: ledger)
        entitlements = ledger.loadOrEmpty().entitlementSnapshot()
    }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                _ = await self.receive(result, source: .transactionUpdate)
            }
        }
        Task { [weak self] in
            await self?.loadProductsAndEntitlements()
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    func loadProductsAndEntitlements() async {
        setState(.loadingProducts)
        do {
            let loaded = try await Product.products(for: catalog.products.map { $0.id.rawValue })
            products = Dictionary(uniqueKeysWithValues: loaded.compactMap { product in
                StoreProductID(rawValue: product.id).map { ($0, product) }
            })
            guard products.count == catalog.products.count else {
                retryOperation = .loadProducts
                setState(.offlineRetry(.loadProducts))
                return
            }
            guard await refreshCurrentEntitlements() else { return }
            retryOperation = nil
            setState(.ready)
        } catch {
            retryOperation = .loadProducts
            setState(.offlineRetry(.loadProducts))
        }
    }

    func purchase(_ id: StoreProductID) async {
        guard let product = products[id] else {
            retryOperation = .loadProducts
            setState(.offlineRetry(.loadProducts))
            return
        }
        setState(.purchasing(id))
        do {
            switch try await product.purchase() {
            case .success(let verification):
                _ = await receive(verification, source: .purchase)
            case .pending:
                retryOperation = nil
                setState(.pendingApproval(id))
            case .userCancelled:
                retryOperation = nil
                setState(.cancelled)
            @unknown default:
                setState(.failed("알 수 없는 App Store 구매 결과입니다."))
            }
        } catch {
            retryOperation = .purchase
            setState(.offlineRetry(.purchase))
        }
    }

    func restorePurchases() async {
        setState(.restoring)
        do {
            try await AppStore.sync()
            guard await refreshCurrentEntitlements() else { return }
            retryOperation = nil
            setState(.restored)
        } catch {
            retryOperation = .restore
            setState(.offlineRetry(.restore))
        }
    }

    func retryLastOperation() async {
        switch retryOperation {
        case .loadProducts: await loadProductsAndEntitlements()
        case .restore: await restorePurchases()
        case .purchase, .transactionUpdate, .none:
            await refreshEntitlements()
        }
    }

    func refreshEntitlements() async {
        guard await refreshCurrentEntitlements() else { return }
        retryOperation = nil
        setState(.ready)
    }

    func isUnlocked(_ entitlement: PremiumEntitlement) -> Bool {
        entitlements.contains(entitlement)
    }

    private func refreshCurrentEntitlements() async -> Bool {
        var allVerifiedAndPersisted = true
        // History carries signed revocation and expiration data for purchases that are no
        // longer emitted by currentEntitlements. Persist it before deriving active access.
        for await verification in Transaction.all {
            if !(await receive(verification, source: .restore, publishReadyState: false)) {
                allVerifiedAndPersisted = false
            }
        }
        for await verification in Transaction.currentEntitlements {
            if !(await receive(verification, source: .restore, publishReadyState: false)) {
                allVerifiedAndPersisted = false
            }
        }
        publishEntitlements()
        return allVerifiedAndPersisted
    }

    @discardableResult
    private func receive(
        _ verification: VerificationResult<Transaction>,
        source: StoreOperation,
        publishReadyState: Bool = true
    ) async -> Bool {
        switch verification {
        case .unverified:
            retryOperation = nil
            setState(.verificationFailed)
            return false
        case .verified(let transaction):
            guard let productID = StoreProductID(rawValue: transaction.productID) else {
                setState(.failed("카탈로그에 없는 상품 거래를 거부했습니다."))
                return false
            }
            let record = VerifiedPurchaseRecord(
                transactionID: transaction.id,
                originalTransactionID: transaction.originalID,
                productID: productID,
                purchaseDate: transaction.purchaseDate,
                expirationDate: transaction.expirationDate,
                revocationDate: transaction.revocationDate
            )
            do {
                try await grantProcessor.persistThenFinish(record) {
                    await transaction.finish()
                }
                entitlements = ledger.loadOrEmpty().entitlementSnapshot()
                retryOperation = nil
                if publishReadyState { setState(.ready) }
                else { publishEntitlements() }
                return true
            } catch {
                retryOperation = source
                setState(.offlineRetry(source))
                return false
            }
        }
    }

    private func setState(_ state: StorePurchaseState) {
        self.state = state
        onUpdate?(state, entitlements)
    }

    private func publishEntitlements() {
        entitlements = ledger.loadOrEmpty().entitlementSnapshot()
        onUpdate?(state, entitlements)
    }

    deinit {
        updatesTask?.cancel()
    }
}

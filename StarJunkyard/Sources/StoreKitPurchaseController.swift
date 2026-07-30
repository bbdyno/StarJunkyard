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

    var allowsPurchase: Bool {
        switch self {
        case .ready, .restored, .cancelled: true
        default: false
        }
    }

    var needsRetry: Bool {
        switch self {
        case .offlineRetry, .verificationFailed, .failed: true
        default: false
        }
    }

    var allowsRestore: Bool {
        switch self {
        case .loadingProducts, .purchasing, .pendingApproval, .restoring: false
        default: true
        }
    }

    var statusKo: String {
        switch self {
        case .idle: "App Store 상품 정보를 준비하고 있습니다"
        case .loadingProducts: "상품과 현지 가격을 불러오는 중입니다"
        case .ready: "상품을 선택하면 App Store 구매 확인창이 열립니다"
        case .purchasing: "App Store에서 구매를 확인하는 중입니다"
        case .pendingApproval: "보호자 승인 대기 중 • 승인 후 자동 지급됩니다"
        case .cancelled: "구매를 취소했습니다 • 결제된 항목은 없습니다"
        case .restoring: "이 Apple ID의 구매 내역을 복원하는 중입니다"
        case .restored: "구매 복원과 권한 확인을 완료했습니다"
        case .offlineRetry: "App Store 연결 실패 • 네트워크 확인 후 다시 시도하세요"
        case .verificationFailed: "거래 검증 실패 • 지급하지 않았습니다"
        case .failed(let message): message
        }
    }
}

struct StoreProductDisplay: Equatable, Sendable {
    let id: StoreProductID
    let displayName: String
    let displayPrice: String
}

struct StorefrontSnapshot: Equatable, Sendable {
    let state: StorePurchaseState
    let entitlements: EntitlementSnapshot
    let products: [StoreProductDisplay]

    static func unavailable(entitlements: EntitlementSnapshot) -> StorefrontSnapshot {
        StorefrontSnapshot(state: .idle, entitlements: entitlements, products: [])
    }
}

@MainActor
final class StoreKitPurchaseController {
    typealias UpdateHandler = @MainActor (StorefrontSnapshot) -> Void

    private let catalog: IAPCatalog
    private let ledger: PurchaseLedgerStore
    private let grantProcessor: PurchaseGrantProcessor
    private var updatesTask: Task<Void, Never>?
    private var retryOperation: StoreOperation?

    private(set) var products: [StoreProductID: Product] = [:]
    private(set) var productDisplays: [StoreProductDisplay] = []
    private(set) var state: StorePurchaseState = .idle
    private(set) var entitlements: EntitlementSnapshot
    var onUpdate: UpdateHandler?

    var snapshot: StorefrontSnapshot {
        StorefrontSnapshot(state: state, entitlements: entitlements, products: productDisplays)
    }

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
        products = [:]
        productDisplays = []
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
            productDisplays = catalog.products.compactMap { definition in
                products[definition.id].map {
                    StoreProductDisplay(id: definition.id, displayName: $0.displayName, displayPrice: $0.displayPrice)
                }
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
        onUpdate?(snapshot)
    }

    private func publishEntitlements() {
        entitlements = ledger.loadOrEmpty().entitlementSnapshot()
        onUpdate?(snapshot)
    }

    deinit {
        updatesTask?.cancel()
    }
}

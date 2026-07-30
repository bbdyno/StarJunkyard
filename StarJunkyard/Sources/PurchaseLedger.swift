import Foundation

struct VerifiedPurchaseRecord: Codable, Equatable, Sendable {
    let transactionID: UInt64
    let originalTransactionID: UInt64
    let productID: StoreProductID
    let purchaseDate: Date
    var expirationDate: Date?
    var revocationDate: Date?

    var isRevoked: Bool { revocationDate != nil }

    func isActive(at date: Date) -> Bool {
        guard revocationDate == nil else { return false }
        return expirationDate.map { $0 > date } ?? true
    }
}

struct PurchaseLedgerSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let empty = PurchaseLedgerSnapshot(
        schemaVersion: currentSchemaVersion,
        revision: 0,
        updatedAt: .distantPast,
        records: []
    )

    var schemaVersion: Int
    var revision: Int
    var updatedAt: Date
    var records: [VerifiedPurchaseRecord]

    func entitlementSnapshot(at date: Date = Date()) -> EntitlementSnapshot {
        let active = records
            .filter { $0.isActive(at: date) }
            .reduce(into: Set<PremiumEntitlement>()) { result, record in
                result.formUnion(record.productID.expectedGrants)
            }
        return EntitlementSnapshot(active: active)
    }
}

enum PurchaseLedgerMutation: Equatable, Sendable {
    case inserted
    case updated
    case unchanged
}

enum PurchaseLedgerError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case invalidProduct(String)
}

final class PurchaseLedgerStore: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = base.appendingPathComponent("StarJunkyard", isDirectory: true)
        }
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    var ledgerURL: URL { directory.appendingPathComponent("purchase-ledger.json") }
    var backupURL: URL { directory.appendingPathComponent("purchase-ledger-backup.json") }

    func load() throws -> PurchaseLedgerSnapshot {
        try lock.withLock { try loadUnlocked() }
    }

    func loadOrEmpty() -> PurchaseLedgerSnapshot {
        (try? load()) ?? .empty
    }

    @discardableResult
    func record(_ incoming: VerifiedPurchaseRecord, now: Date = Date()) throws -> PurchaseLedgerMutation {
        try lock.withLock {
            var snapshot = try loadUnlocked()
            let mutation: PurchaseLedgerMutation
            if let index = snapshot.records.firstIndex(where: { $0.transactionID == incoming.transactionID }) {
                let merged = Self.merge(snapshot.records[index], incoming)
                guard merged != snapshot.records[index] else { return .unchanged }
                snapshot.records[index] = merged
                mutation = .updated
            } else {
                snapshot.records.append(incoming)
                mutation = .inserted
            }
            snapshot.records.sort { $0.transactionID < $1.transactionID }
            snapshot.revision += 1
            snapshot.updatedAt = now
            try saveUnlocked(snapshot)
            return mutation
        }
    }

    func exportCloudData() throws -> Data {
        try lock.withLock { try encoder.encode(loadUnlocked()) }
    }

    @discardableResult
    func mergeCloudData(_ data: Data, now: Date = Date()) throws -> PurchaseLedgerSnapshot {
        let cloud = try decoder.decode(PurchaseLedgerSnapshot.self, from: data)
        guard cloud.schemaVersion == PurchaseLedgerSnapshot.currentSchemaVersion else {
            throw PurchaseLedgerError.unsupportedSchema(cloud.schemaVersion)
        }
        return try lock.withLock {
            var local = try loadUnlocked()
            var records = Dictionary(uniqueKeysWithValues: local.records.map { ($0.transactionID, $0) })
            for incoming in cloud.records {
                if let existing = records[incoming.transactionID] {
                    records[incoming.transactionID] = Self.merge(existing, incoming)
                } else {
                    records[incoming.transactionID] = incoming
                }
            }
            local.records = records.values.sorted { $0.transactionID < $1.transactionID }
            local.revision = max(local.revision, cloud.revision) + 1
            local.updatedAt = now
            try saveUnlocked(local)
            return local
        }
    }

    private func loadUnlocked() throws -> PurchaseLedgerSnapshot {
        guard fileManager.fileExists(atPath: ledgerURL.path) else { return .empty }
        do {
            return try decode(Data(contentsOf: ledgerURL))
        } catch {
            guard fileManager.fileExists(atPath: backupURL.path) else { throw error }
            return try decode(Data(contentsOf: backupURL))
        }
    }

    private func decode(_ data: Data) throws -> PurchaseLedgerSnapshot {
        let snapshot = try decoder.decode(PurchaseLedgerSnapshot.self, from: data)
        guard snapshot.schemaVersion == PurchaseLedgerSnapshot.currentSchemaVersion else {
            throw PurchaseLedgerError.unsupportedSchema(snapshot.schemaVersion)
        }
        return snapshot
    }

    private func saveUnlocked(_ snapshot: PurchaseLedgerSnapshot) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: ledgerURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: ledgerURL, to: backupURL)
        }
        try encoder.encode(snapshot).write(
            to: ledgerURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private static func merge(_ lhs: VerifiedPurchaseRecord, _ rhs: VerifiedPurchaseRecord) -> VerifiedPurchaseRecord {
        VerifiedPurchaseRecord(
            transactionID: lhs.transactionID,
            originalTransactionID: lhs.originalTransactionID,
            productID: lhs.productID,
            purchaseDate: min(lhs.purchaseDate, rhs.purchaseDate),
            expirationDate: [lhs.expirationDate, rhs.expirationDate].compactMap { $0 }.max(),
            revocationDate: [lhs.revocationDate, rhs.revocationDate].compactMap { $0 }.max()
        )
    }
}

@MainActor
struct PurchaseGrantProcessor {
    let ledger: PurchaseLedgerStore

    @discardableResult
    func persistThenFinish(
        _ record: VerifiedPurchaseRecord,
        finish: @MainActor () async -> Void
    ) async throws -> PurchaseLedgerMutation {
        let mutation = try ledger.record(record)
        await finish()
        return mutation
    }
}

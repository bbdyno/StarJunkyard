import Foundation

enum StoreProductID: String, CaseIterable, Codable, Sendable {
    case starterCrewKit = "com.bbdyno.starjunkyard.starter.crewkit"
    case workbenchSlot3 = "com.bbdyno.starjunkyard.workbench.slot3"
    case offline16Hours = "com.bbdyno.starjunkyard.offline.16h"
    case boraRustCosmetic = "com.bbdyno.starjunkyard.cosmetic.bora.rust"
    case maintenanceMonthly = "com.bbdyno.starjunkyard.maintenance.monthly"
    case scrapFrontierSeason2026 = "com.bbdyno.starjunkyard.season.2026.scrapfrontier"

    var expectedType: StoreProductType {
        self == .maintenanceMonthly ? .autoRenewableSubscription : .nonConsumable
    }

    var expectedGrants: Set<PremiumEntitlement> {
        switch self {
        case .starterCrewKit:
            [.boraFounderUniform, .boraFounderAttackFX, .founderProfileBadge]
        case .workbenchSlot3:
            [.workbenchSlot3]
        case .offline16Hours:
            [.offlineCap16Hours]
        case .boraRustCosmetic:
            [.boraRustUniform, .boraRustAttackFX]
        case .maintenanceMonthly:
            [.craftSpeed110, .dailyTimeTicketPlus1, .monthlyCrewCosmetic]
        case .scrapFrontierSeason2026:
            [.season2026ScrapFrontierPremium]
        }
    }

    var benefitKo: String {
        switch self {
        case .starterCrewKit: "창업 정비복 · 공격 효과 · 배지"
        case .workbenchSlot3: "세 번째 작업대 영구 해금"
        case .offline16Hours: "오프라인 적립 8시간 → 16시간"
        case .boraRustCosmetic: "녹슨 정비복 · 전용 공격 효과"
        case .maintenanceMonthly: "제작 +10% · 매일 즉시완료권 1장"
        case .scrapFrontierSeason2026: "고철전선 시즌 유료 보상 트랙"
        }
    }

    var fallbackNameKo: String {
        switch self {
        case .starterCrewKit: "보라 창업 정비 키트"
        case .workbenchSlot3: "작업대 3번 슬롯"
        case .offline16Hours: "오프라인 적립 16시간"
        case .boraRustCosmetic: "보라 녹슨 정비복"
        case .maintenanceMonthly: "월간 정비 멤버십"
        case .scrapFrontierSeason2026: "고철전선 2026 시즌 패스"
        }
    }
}

enum StoreProductType: String, Codable, Sendable {
    case nonConsumable = "non_consumable"
    case autoRenewableSubscription = "auto_renewable_subscription"
}

enum PremiumEntitlement: String, CaseIterable, Codable, Sendable {
    case boraFounderUniform = "bora_founder_uniform"
    case boraFounderAttackFX = "bora_founder_attack_fx"
    case founderProfileBadge = "founder_profile_badge"
    case workbenchSlot3 = "workbench_slot_3"
    case offlineCap16Hours = "offline_cap_16h"
    case boraRustUniform = "bora_rust_uniform"
    case boraRustAttackFX = "bora_rust_attack_fx"
    case craftSpeed110 = "craft_speed_1_10"
    case dailyTimeTicketPlus1 = "daily_time_ticket_plus_1"
    case monthlyCrewCosmetic = "monthly_crew_cosmetic"
    case season2026ScrapFrontierPremium = "season_2026_scrapfrontier_premium"
}

struct EntitlementSnapshot: Codable, Equatable, Sendable {
    static let none = EntitlementSnapshot(active: [])

    var active: Set<PremiumEntitlement>

    func contains(_ entitlement: PremiumEntitlement) -> Bool {
        active.contains(entitlement)
    }

    var offlineCapHours: Int {
        contains(.offlineCap16Hours) ? 16 : 8
    }

    var workbenchSlots: Int {
        contains(.workbenchSlot3) ? 3 : 2
    }

    var craftSpeedMultiplier: Double {
        contains(.craftSpeed110) ? 1.10 : 1
    }
}

enum BoraUniform: String, Codable, CaseIterable, Sendable {
    case base
    case founder
    case rust

    var nameKo: String {
        switch self {
        case .base: "기본 작업복"
        case .founder: "창업 정비복"
        case .rust: "녹슨 정비복"
        }
    }

    func isUnlocked(by entitlements: EntitlementSnapshot) -> Bool {
        switch self {
        case .base: true
        case .founder: entitlements.contains(.boraFounderUniform)
        case .rust: entitlements.contains(.boraRustUniform)
        }
    }
}

struct IAPCatalog: Codable, Equatable, Sendable {
    struct ProductDefinition: Codable, Equatable, Sendable {
        let id: StoreProductID
        let type: StoreProductType
        let referencePriceUSD: Decimal
        let group: String?
        let grants: [PremiumEntitlement]
    }

    let schemaVersion: Int
    let platform: String
    let speedMultiplierTarget: Decimal
    let speedMultiplierHardCap: Decimal
    let products: [ProductDefinition]

    func validated() throws -> IAPCatalog {
        guard schemaVersion == 1 else { throw IAPCatalogError.unsupportedSchema(schemaVersion) }
        guard platform == "ios" else { throw IAPCatalogError.invalidPlatform(platform) }
        guard speedMultiplierTarget <= speedMultiplierHardCap, speedMultiplierHardCap <= Decimal(string: "1.8")! else {
            throw IAPCatalogError.invalidSpeedCap
        }
        let ids = products.map(\.id)
        guard Set(ids).count == ids.count else { throw IAPCatalogError.duplicateProduct }
        guard Set(ids) == Set(StoreProductID.allCases) else { throw IAPCatalogError.incompleteProductSet }
        for product in products {
            guard product.type == product.id.expectedType else {
                throw IAPCatalogError.typeMismatch(product.id)
            }
            guard Set(product.grants) == product.id.expectedGrants else {
                throw IAPCatalogError.grantMismatch(product.id)
            }
            if product.id == .maintenanceMonthly {
                guard product.group == "maintenance_membership" else {
                    throw IAPCatalogError.subscriptionGroupMismatch
                }
            } else if product.group != nil {
                throw IAPCatalogError.subscriptionGroupMismatch
            }
        }
        return self
    }

    func product(_ id: StoreProductID) -> ProductDefinition {
        products.first(where: { $0.id == id })!
    }

    static func load(bundle: Bundle = .main) throws -> IAPCatalog {
        let url = bundle.url(forResource: "ios-iap-catalog", withExtension: "json", subdirectory: "content")
            ?? bundle.url(forResource: "ios-iap-catalog", withExtension: "json")
        guard let url else { throw IAPCatalogError.missingResource }
        return try JSONDecoder().decode(IAPCatalog.self, from: Data(contentsOf: url)).validated()
    }
}

enum IAPCatalogError: Error, Equatable, Sendable {
    case missingResource
    case unsupportedSchema(Int)
    case invalidPlatform(String)
    case invalidSpeedCap
    case duplicateProduct
    case incompleteProductSet
    case typeMismatch(StoreProductID)
    case grantMismatch(StoreProductID)
    case subscriptionGroupMismatch
}

import Foundation

enum YardFacility: String, CaseIterable, Sendable {
    case press
    case sorter
    case warehouse

    var nameKo: String {
        switch self {
        case .press: "유압 압착기"
        case .sorter: "자동 선별기"
        case .warehouse: "궤도 창고"
        }
    }

    var outputPerLevel: Int {
        switch self {
        case .press: 2
        case .sorter: 5
        case .warehouse: 12
        }
    }

    var baseCost: Int {
        switch self {
        case .press: 30
        case .sorter: 90
        case .warehouse: 240
        }
    }
}

struct YardEconomy: Sendable {
    static let defaultOfflineCap: TimeInterval = 8 * 60 * 60

    static func offlineCap(entitlements: EntitlementSnapshot = .none) -> TimeInterval {
        entitlements.contains(.offlineCap16Hours) ? defaultOfflineCap * 2 : defaultOfflineCap
    }

    static func manualDamage(cutterLevel: Int) -> Int {
        6 + max(1, cutterLevel) * 4
    }

    static func manualReward(cutterLevel: Int) -> Int {
        max(1, max(1, cutterLevel) / 2)
    }

    static func facilityOutput(_ facility: YardFacility, level: Int) -> Int {
        max(0, level) * facility.outputPerLevel
    }

    static func passiveIncome(
        pressLevel: Int,
        sorterLevel: Int,
        warehouseLevel: Int,
        crewLevel: Int
    ) -> Int {
        facilityOutput(.press, level: pressLevel)
            + facilityOutput(.sorter, level: sorterLevel)
            + facilityOutput(.warehouse, level: warehouseLevel)
            + max(0, crewLevel - 1)
    }

    static func upgradeCost(_ facility: YardFacility, currentLevel: Int) -> Int {
        facility.baseCost * max(1, currentLevel + 1)
    }

    static func offlineIncome(
        rate: Int,
        elapsed: TimeInterval,
        entitlements: EntitlementSnapshot = .none
    ) -> (seconds: Int, amount: Int) {
        let seconds = Int(min(max(0, elapsed), offlineCap(entitlements: entitlements)).rounded(.down))
        return (seconds, max(0, rate) * seconds)
    }
}

import Foundation

enum DamageAffinity: String, Codable, CaseIterable, Sendable {
    case cut
    case impact
    case magnetic

    var nameKo: String {
        switch self {
        case .cut: "절단"
        case .impact: "충격"
        case .magnetic: "자력"
        }
    }

    func matches(enemyWeakness: String) -> Bool {
        switch self {
        case .cut: enemyWeakness == "cut"
        case .impact: enemyWeakness == "impact"
        case .magnetic: enemyWeakness == "electric" || enemyWeakness == "magnetic"
        }
    }
}

enum CrewRole: String, Codable, CaseIterable, Sendable {
    case breaker
    case cutter
    case collector

    var nameKo: String {
        switch self {
        case .breaker: "파쇄 담당"
        case .cutter: "절단 지원"
        case .collector: "자력 회수"
        }
    }

    var affinity: DamageAffinity {
        switch self {
        case .breaker: .impact
        case .cutter: .cut
        case .collector: .magnetic
        }
    }

    var damageMultiplierPPM: Int {
        switch self {
        case .breaker: 1_200_000
        case .cutter: 1_100_000
        case .collector: 1_000_000
        }
    }
}

struct FormationProgression: Sendable {
    static let weaknessBonusPPM = 1_500_000

    struct ModuleSpec: Equatable, Sendable {
        let id: String
        let nameKo: String
        let affinity: DamageAffinity
        let unlockStage: Int
        let requiresBossClear: Bool
        let powerPPM: Int
    }

    struct ReconcileResult: Equatable, Sendable {
        let unlockedDroneIDs: [String]
        let equippedDroneIDs: [String]
        let unlockedModuleIDs: [String]
        let equippedModuleIDs: [String]
        let newlyUnlockedDroneIDs: [String]
        let newlyUnlockedModuleIDs: [String]
    }

    struct DamageResolution: Equatable, Sendable {
        let damage: Int
        let affinity: DamageAffinity
        let weaknessApplied: Bool
        let multiplierPPM: Int
    }

    static let moduleCatalog: [ModuleSpec] = [
        ModuleSpec(
            id: "module_impact_hammer",
            nameKo: "충격 해머 모듈",
            affinity: .impact,
            unlockStage: 5,
            requiresBossClear: false,
            powerPPM: 1_050_000
        ),
        ModuleSpec(
            id: "module_cutting_coil",
            nameKo: "절단 코일 모듈",
            affinity: .cut,
            unlockStage: 10,
            requiresBossClear: true,
            powerPPM: 1_100_000
        ),
        ModuleSpec(
            id: "module_magnetic_net",
            nameKo: "자력 포획 모듈",
            affinity: .magnetic,
            unlockStage: 15,
            requiresBossClear: false,
            powerPPM: 1_080_000
        )
    ]

    static func droneSlotCount(highestStage: Int) -> Int {
        if highestStage >= 30 { return 2 }
        return 1
    }

    static func reconcile(
        highestStage: Int,
        defeatedBossStages: Set<Int>,
        drones: [VerticalSliceContent.Drone],
        unlockedDroneIDs previousDroneIDs: [String],
        equippedDroneIDs previousFormation: [String],
        unlockedModuleIDs previousModuleIDs: [String],
        equippedModuleIDs previousModules: [String]
    ) -> ReconcileResult {
        let eligibleDroneIDs = drones
            .filter { highestStage >= $0.unlockStage }
            .map(\.id)
        let previousDrones = canonicalIDs(previousDroneIDs)
        let previousDroneSet = Set(previousDrones)
        let unlockedDrones = canonicalIDs(previousDrones + eligibleDroneIDs)
        let unlockedDroneSet = Set(unlockedDrones)
        let newlyUnlockedDrones = eligibleDroneIDs.filter { !previousDroneSet.contains($0) }

        let eligibleModuleIDs = moduleCatalog.filter { module in
            highestStage >= module.unlockStage
                && (!module.requiresBossClear || defeatedBossStages.contains(module.unlockStage))
        }.map(\.id)
        let previousUnlockedModules = canonicalIDs(previousModuleIDs)
        let previousModuleSet = Set(previousUnlockedModules)
        let unlockedModules = canonicalIDs(previousUnlockedModules + eligibleModuleIDs)
        let unlockedModuleSet = Set(unlockedModules)
        let newlyUnlockedModules = eligibleModuleIDs.filter { !previousModuleSet.contains($0) }

        let slotCount = droneSlotCount(highestStage: highestStage)
        var formation = canonicalIDs(previousFormation).filter { unlockedDroneSet.contains($0) }
        formation = Array(formation.prefix(slotCount))
        for droneID in eligibleDroneIDs where formation.count < slotCount && !formation.contains(droneID) {
            formation.append(droneID)
        }

        var modules = canonicalIDs(previousModules).filter { unlockedModuleSet.contains($0) }
        modules = Array(modules.prefix(1))
        if modules.isEmpty, let firstEligible = eligibleModuleIDs.first {
            modules = [firstEligible]
        }

        return ReconcileResult(
            unlockedDroneIDs: unlockedDrones,
            equippedDroneIDs: formation,
            unlockedModuleIDs: unlockedModules,
            equippedModuleIDs: modules,
            newlyUnlockedDroneIDs: newlyUnlockedDrones,
            newlyUnlockedModuleIDs: newlyUnlockedModules
        )
    }

    static func selectingDrone(
        _ droneID: String,
        formation: [String],
        unlockedDroneIDs: Set<String>,
        slotCount: Int
    ) -> [String] {
        guard slotCount > 0, unlockedDroneIDs.contains(droneID) else { return formation }
        var selected = canonicalIDs(formation).filter { unlockedDroneIDs.contains($0) && $0 != droneID }
        if selected.count >= slotCount {
            selected.removeLast()
        }
        selected.append(droneID)
        return Array(selected.prefix(slotCount))
    }

    static func cyclingModule(equippedModuleIDs: [String], unlockedModuleIDs: Set<String>) -> [String] {
        let available = moduleCatalog.map(\.id).filter { unlockedModuleIDs.contains($0) }
        guard !available.isEmpty else { return [] }
        guard let current = equippedModuleIDs.first,
              let index = available.firstIndex(of: current)
        else { return [available[0]] }
        return [available[(index + 1) % available.count]]
    }

    static func nextRole(after role: CrewRole) -> CrewRole {
        let roles = CrewRole.allCases
        let index = roles.firstIndex(of: role) ?? 0
        return roles[(index + 1) % roles.count]
    }

    static func crewDamage(masteryLevel: Int, role: CrewRole) -> Int {
        let base = 5 + max(0, masteryLevel - 1) * 5
        return base * role.damageMultiplierPPM / 1_000_000
    }

    static func affinity(forDroneRole role: String) -> DamageAffinity {
        switch role {
        case "chain_electric": .magnetic
        case "salvage": .impact
        default: .cut
        }
    }

    static func module(id: String?) -> ModuleSpec? {
        moduleCatalog.first { $0.id == id }
    }

    static func resolveDamage(
        base: Int,
        affinity: DamageAffinity,
        enemyWeakness: String,
        powerPPM: Int = 1_000_000
    ) -> DamageResolution {
        let weaknessApplied = affinity.matches(enemyWeakness: enemyWeakness)
        let weaknessPPM = weaknessApplied ? weaknessBonusPPM : 1_000_000
        let multiplier = powerPPM * weaknessPPM / 1_000_000
        return DamageResolution(
            damage: max(0, base) * multiplier / 1_000_000,
            affinity: affinity,
            weaknessApplied: weaknessApplied,
            multiplierPPM: multiplier
        )
    }

    static func nextUnlockDescription(
        highestStage: Int,
        defeatedBossStages: Set<Int>,
        drones: [VerticalSliceContent.Drone]
    ) -> String {
        var candidates: [(Int, String)] = drones
            .filter { highestStage < $0.unlockStage }
            .map { ($0.unlockStage, "S\($0.unlockStage) \($0.nameKo) 무료 해금") }
        if highestStage < 30 {
            candidates.append((30, "S30 두 번째 드론 슬롯 무료 개방"))
        }
        for module in moduleCatalog {
            let unlocked = highestStage >= module.unlockStage
                && (!module.requiresBossClear || defeatedBossStages.contains(module.unlockStage))
            if !unlocked {
                let condition = module.requiresBossClear ? " 보스 해체" : " 도달"
                candidates.append((module.unlockStage, "S\(module.unlockStage)\(condition) • \(module.nameKo) 무료"))
            }
        }
        return candidates.sorted { left, right in
            left.0 == right.0 ? left.1 < right.1 : left.0 < right.0
        }.first?.1 ?? "R1 무료 편성 해금 완료"
    }

    static func canonicalIDs(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

import Foundation

struct BossEncounterRules: Sendable {
    enum Phase: Int, Equatable, Sendable {
        case armored
        case clawBroken
        case coreExposed
        case dismantle
    }

    struct FirstClearReward: Equatable, Sendable {
        let blueprintID: String
        let moduleID: String
        let storyLogID: String
    }

    static let simulationTickMilliseconds = 50

    static func timeLimitTicks(milliseconds: Int?) -> Int {
        max(1, (milliseconds ?? 45_000) / simulationTickMilliseconds)
    }

    static func remainingSeconds(deadlineTick: Int, currentTick: Int) -> Int {
        max(0, Int(ceil(Double(max(0, deadlineTick - currentTick)) / 20.0)))
    }

    static func phase(hp: Int, maxHP: Int) -> Phase {
        guard hp > 0 else { return .dismantle }
        let ratioPPM = hp * 1_000_000 / max(1, maxHP)
        if ratioPPM <= 300_000 { return .coreExposed }
        if ratioPPM <= 700_000 { return .clawBroken }
        return .armored
    }

    static func activeCutIndex(stageNumber: Int) -> Int {
        max(0, stageNumber / 10) % 2
    }

    static func firstClearReward(stageNumber: Int) -> FirstClearReward {
        switch stageNumber {
        case 10:
            FirstClearReward(
                blueprintID: "blueprint_cutting_coil",
                moduleID: "module_cutting_coil",
                storyLogID: "chapter_01_first_claw"
            )
        default:
            FirstClearReward(
                blueprintID: "blueprint_boss_" + String(stageNumber),
                moduleID: "module_boss_" + String(stageNumber),
                storyLogID: "boss_log_" + String(stageNumber)
            )
        }
    }

    static func bonusParts(baseParts: Int, cutSucceeded: Bool) -> Int {
        guard cutSucceeded else { return 0 }
        return max(1, Int(ceil(Double(max(0, baseParts)) * 0.15)))
    }
}

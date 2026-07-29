import Foundation

struct GameSave: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let cloudSlotName = "sj_main_v1"

    var schemaVersion: Int = currentSchemaVersion
    var revision: Int
    var updatedAt: Date
    var stageIndex: Int
    var waveIndex: Int
    var enemyHP: Int?
    var credits: Int
    var parts: Int
    var cutterLevel: Int
    var droneLevel: Int
    var magnetLevel: Int
    var tutorialStep: Int
    var combatTick: Int
    var highestStage: Int
    var cloudBackupEnabled: Bool

    static func newGame(now: Date = Date()) -> GameSave {
        GameSave(
            revision: 1,
            updatedAt: now,
            stageIndex: 0,
            waveIndex: 0,
            enemyHP: nil,
            credits: 0,
            parts: 0,
            cutterLevel: 1,
            droneLevel: 1,
            magnetLevel: 1,
            tutorialStep: 0,
            combatTick: 0,
            highestStage: 1,
            cloudBackupEnabled: false
        )
    }

    var summary: String {
        "S\(highestStage)  •  고철 \(credits)  •  절단날 LV.\(cutterLevel)"
    }
}

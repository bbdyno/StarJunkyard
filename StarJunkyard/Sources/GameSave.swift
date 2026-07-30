import Foundation

struct GameSave: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2
    static let cloudSlotName = "sj_main_v1"

    var schemaVersion: Int = currentSchemaVersion
    var revision: Int
    var updatedAt: Date
    var stageIndex: Int
    var waveIndex: Int
    var enemyHP: Int?
    var enemyHPs: [Int]?
    var credits: Int
    var parts: Int
    var cutterLevel: Int
    var droneLevel: Int
    var magnetLevel: Int
    var crewLevel: Int
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
            enemyHPs: nil,
            credits: 0,
            parts: 0,
            cutterLevel: 1,
            droneLevel: 1,
            magnetLevel: 1,
            crewLevel: 1,
            tutorialStep: 0,
            combatTick: 0,
            highestStage: 1,
            cloudBackupEnabled: false
        )
    }

    var summary: String {
        "S\(highestStage)  •  고철 \(credits)  •  보라 LV.\(crewLevel)"
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, updatedAt, stageIndex, waveIndex, enemyHP, enemyHPs
        case credits, parts, cutterLevel, droneLevel, magnetLevel, crewLevel
        case tutorialStep, combatTick, highestStage, cloudBackupEnabled
    }

    init(
        schemaVersion: Int = currentSchemaVersion,
        revision: Int,
        updatedAt: Date,
        stageIndex: Int,
        waveIndex: Int,
        enemyHP: Int?,
        enemyHPs: [Int]?,
        credits: Int,
        parts: Int,
        cutterLevel: Int,
        droneLevel: Int,
        magnetLevel: Int,
        crewLevel: Int,
        tutorialStep: Int,
        combatTick: Int,
        highestStage: Int,
        cloudBackupEnabled: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.updatedAt = updatedAt
        self.stageIndex = stageIndex
        self.waveIndex = waveIndex
        self.enemyHP = enemyHP
        self.enemyHPs = enemyHPs
        self.credits = credits
        self.parts = parts
        self.cutterLevel = cutterLevel
        self.droneLevel = droneLevel
        self.magnetLevel = magnetLevel
        self.crewLevel = crewLevel
        self.tutorialStep = tutorialStep
        self.combatTick = combatTick
        self.highestStage = highestStage
        self.cloudBackupEnabled = cloudBackupEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        revision = try values.decode(Int.self, forKey: .revision)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        stageIndex = try values.decode(Int.self, forKey: .stageIndex)
        waveIndex = try values.decode(Int.self, forKey: .waveIndex)
        enemyHP = try values.decodeIfPresent(Int.self, forKey: .enemyHP)
        enemyHPs = try values.decodeIfPresent([Int].self, forKey: .enemyHPs)
        credits = try values.decode(Int.self, forKey: .credits)
        parts = try values.decode(Int.self, forKey: .parts)
        cutterLevel = try values.decode(Int.self, forKey: .cutterLevel)
        droneLevel = try values.decode(Int.self, forKey: .droneLevel)
        magnetLevel = try values.decode(Int.self, forKey: .magnetLevel)
        crewLevel = try values.decodeIfPresent(Int.self, forKey: .crewLevel) ?? 1
        tutorialStep = try values.decode(Int.self, forKey: .tutorialStep)
        combatTick = try values.decode(Int.self, forKey: .combatTick)
        highestStage = try values.decode(Int.self, forKey: .highestStage)
        cloudBackupEnabled = try values.decode(Bool.self, forKey: .cloudBackupEnabled)
    }
}

import Foundation

struct GameSave: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 6
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
    var pressLevel: Int
    var sorterLevel: Int
    var warehouseLevel: Int
    var yardIncomeBank: Int
    var manualTapCount: Int
    var discoveredEnemyIDs: [String]
    var storyChapter: Int
    var shelterRepairParts: Int
    var prologueSeen: Bool
    var defeatedBossStages: [Int]
    var unlockedBlueprintIDs: [String]
    var unlockedModuleIDs: [String]
    var storyLogIDs: [String]
    var bossFailureCounts: [String: Int]
    var pendingBossDismantleStage: Int?
    var pendingBossBaseParts: Int
    var idleOperations: IdleOperationsState
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
            pressLevel: 1,
            sorterLevel: 0,
            warehouseLevel: 0,
            yardIncomeBank: 0,
            manualTapCount: 0,
            discoveredEnemyIDs: [],
            storyChapter: 0,
            shelterRepairParts: 0,
            prologueSeen: false,
            defeatedBossStages: [],
            unlockedBlueprintIDs: [],
            unlockedModuleIDs: [],
            storyLogIDs: [],
            bossFailureCounts: [:],
            pendingBossDismantleStage: nil,
            pendingBossBaseParts: 0,
            idleOperations: .newGame(now: now),
            tutorialStep: 0,
            combatTick: 0,
            highestStage: 1,
            cloudBackupEnabled: false
        )
    }

    var summary: String {
        let goal = ShelterRecovery.goal(deliveredParts: shelterRepairParts, highestStage: highestStage)
        return "S\(highestStage)  •  \(goal.title) \(goal.current)/\(goal.required)  •  고철 \(credits)"
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, updatedAt, stageIndex, waveIndex, enemyHP, enemyHPs
        case credits, parts, cutterLevel, droneLevel, magnetLevel, crewLevel
        case pressLevel, sorterLevel, warehouseLevel, yardIncomeBank, manualTapCount, discoveredEnemyIDs
        case storyChapter, shelterRepairParts, prologueSeen
        case defeatedBossStages, unlockedBlueprintIDs, unlockedModuleIDs, storyLogIDs, bossFailureCounts
        case pendingBossDismantleStage, pendingBossBaseParts
        case idleOperations
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
        pressLevel: Int,
        sorterLevel: Int,
        warehouseLevel: Int,
        yardIncomeBank: Int,
        manualTapCount: Int,
        discoveredEnemyIDs: [String],
        storyChapter: Int,
        shelterRepairParts: Int,
        prologueSeen: Bool,
        defeatedBossStages: [Int],
        unlockedBlueprintIDs: [String],
        unlockedModuleIDs: [String],
        storyLogIDs: [String],
        bossFailureCounts: [String: Int],
        pendingBossDismantleStage: Int?,
        pendingBossBaseParts: Int,
        idleOperations: IdleOperationsState,
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
        self.pressLevel = pressLevel
        self.sorterLevel = sorterLevel
        self.warehouseLevel = warehouseLevel
        self.yardIncomeBank = yardIncomeBank
        self.manualTapCount = manualTapCount
        self.discoveredEnemyIDs = discoveredEnemyIDs
        self.storyChapter = storyChapter
        self.shelterRepairParts = shelterRepairParts
        self.prologueSeen = prologueSeen
        self.defeatedBossStages = defeatedBossStages
        self.unlockedBlueprintIDs = unlockedBlueprintIDs
        self.unlockedModuleIDs = unlockedModuleIDs
        self.storyLogIDs = storyLogIDs
        self.bossFailureCounts = bossFailureCounts
        self.pendingBossDismantleStage = pendingBossDismantleStage
        self.pendingBossBaseParts = pendingBossBaseParts
        self.idleOperations = idleOperations
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
        pressLevel = try values.decodeIfPresent(Int.self, forKey: .pressLevel) ?? 1
        sorterLevel = try values.decodeIfPresent(Int.self, forKey: .sorterLevel) ?? 0
        warehouseLevel = try values.decodeIfPresent(Int.self, forKey: .warehouseLevel) ?? 0
        yardIncomeBank = try values.decodeIfPresent(Int.self, forKey: .yardIncomeBank) ?? 0
        manualTapCount = try values.decodeIfPresent(Int.self, forKey: .manualTapCount) ?? 0
        discoveredEnemyIDs = try values.decodeIfPresent([String].self, forKey: .discoveredEnemyIDs) ?? []
        storyChapter = try values.decodeIfPresent(Int.self, forKey: .storyChapter) ?? 0
        shelterRepairParts = try values.decodeIfPresent(Int.self, forKey: .shelterRepairParts) ?? 0
        prologueSeen = try values.decodeIfPresent(Bool.self, forKey: .prologueSeen) ?? false
        defeatedBossStages = try values.decodeIfPresent([Int].self, forKey: .defeatedBossStages) ?? []
        unlockedBlueprintIDs = try values.decodeIfPresent([String].self, forKey: .unlockedBlueprintIDs) ?? []
        unlockedModuleIDs = try values.decodeIfPresent([String].self, forKey: .unlockedModuleIDs) ?? []
        storyLogIDs = try values.decodeIfPresent([String].self, forKey: .storyLogIDs) ?? []
        bossFailureCounts = try values.decodeIfPresent([String: Int].self, forKey: .bossFailureCounts) ?? [:]
        pendingBossDismantleStage = try values.decodeIfPresent(Int.self, forKey: .pendingBossDismantleStage)
        pendingBossBaseParts = try values.decodeIfPresent(Int.self, forKey: .pendingBossBaseParts) ?? 0
        idleOperations = try values.decodeIfPresent(IdleOperationsState.self, forKey: .idleOperations) ?? .newGame(now: updatedAt)
        tutorialStep = try values.decode(Int.self, forKey: .tutorialStep)
        combatTick = try values.decode(Int.self, forKey: .combatTick)
        highestStage = try values.decode(Int.self, forKey: .highestStage)
        cloudBackupEnabled = try values.decode(Bool.self, forKey: .cloudBackupEnabled)
    }
}

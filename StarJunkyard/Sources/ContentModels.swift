import Foundation

struct VerticalSliceContent: Decodable, Sendable {
    let contentVersion: String
    let slice: Slice
    let player: Player
    let drones: [Drone]
    let regions: [Region]?
    let enemies: [Enemy]
    let stages: [Stage]
    let economy: Economy?

    struct Slice: Decodable, Sendable {
        let id: String
        let regionId: String
        let stageStart: Int
        let stageEnd: Int
        let productionStageEnd: Int?
    }

    struct Region: Decodable, Sendable {
        let id: String
        let number: Int
        let nameKo: String
        let stageStart: Int
        let stageEnd: Int
        let themeKo: String
        let musicKo: String
        let palette: [String]
        let backgroundSpriteId: String?
        let primaryDropId: String
        let baseFormKo: String
        let arrivalStoryKo: String
        let completionStoryKo: String
        let nextRegionId: String?
        let enemyIds: [String]
        let eliteIds: [String]
        let midBossId: String
        let regionBossId: String
    }

    struct Player: Decodable, Sendable {
        let id: String
        let baseDamage: Int
        let attackIntervalMs: Int
        let criticalChancePpm: Int
        let criticalDamagePpm: Int
        let spriteId: String
    }

    struct Drone: Decodable, Sendable {
        let id: String
        let nameKo: String
        let role: String
        let baseDamage: Int
        let attackIntervalMs: Int
        let unlockStage: Int
        let spriteId: String
    }

    struct Enemy: Decodable, Sendable {
        let id: String
        let nameKo: String
        let enemyClass: String
        let hpMultiplierPpm: Int
        let weakness: String
        let spriteId: String
        let regionId: String?
        let secondaryWeaknesses: [String]
        let behaviorId: String?
        let behaviorKo: String?
        let breakSequenceKo: String?
        let assetStatus: String?
        let bossRole: String?
        let timeLimitMs: Int?

        enum CodingKeys: String, CodingKey {
            case id, nameKo, hpMultiplierPpm, weakness, spriteId, regionId, secondaryWeaknesses
            case behaviorId, behaviorKo, breakSequenceKo, assetStatus, bossRole, timeLimitMs
            case enemyClass = "class"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            nameKo = try values.decode(String.self, forKey: .nameKo)
            enemyClass = try values.decode(String.self, forKey: .enemyClass)
            hpMultiplierPpm = try values.decode(Int.self, forKey: .hpMultiplierPpm)
            weakness = try values.decode(String.self, forKey: .weakness)
            spriteId = try values.decodeIfPresent(String.self, forKey: .spriteId) ?? ""
            regionId = try values.decodeIfPresent(String.self, forKey: .regionId)
            secondaryWeaknesses = try values.decodeIfPresent([String].self, forKey: .secondaryWeaknesses) ?? []
            behaviorId = try values.decodeIfPresent(String.self, forKey: .behaviorId)
            behaviorKo = try values.decodeIfPresent(String.self, forKey: .behaviorKo)
            breakSequenceKo = try values.decodeIfPresent(String.self, forKey: .breakSequenceKo)
            assetStatus = try values.decodeIfPresent(String.self, forKey: .assetStatus)
            bossRole = try values.decodeIfPresent(String.self, forKey: .bossRole)
            timeLimitMs = try values.decodeIfPresent(Int.self, forKey: .timeLimitMs)
        }
    }

    struct Stage: Decodable, Sendable {
        let number: Int
        let regionId: String?
        let localStage: Int?
        let landmarkId: String?
        let storyBeatId: String?
        let baseHp: Int
        let baseReward: Int
        let wave: [String]
        let bossTier: Int?
        let timeLimitMs: Int?
        let rewardMultiplierPpm: Int
        let encounterClass: R1EncounterRule?
        let expectedClearSeconds: Int?
        let firstClearReward: Economy.Wallet?
    }

    struct Economy: Decodable, Sendable {
        let currencies: [Currency]
        let enemyPartRewards: EnemyPartRewards
        let offline: Offline
        let launch: Launch
        let upgradeSinks: [UpgradeSink]

        struct Currency: Decodable, Sendable {
            let id: String
            let nameKo: String
            let primarySource: String
            let primarySink: String
        }

        struct EnemyPartRewards: Decodable, Sendable {
            let normal: Int
            let elite: Int
            let boss: Int
        }

        struct Offline: Decodable, Sendable {
            let efficiencyPpm: Int
            let cycleSeconds: Int
            let freeCapSeconds: Int
        }

        struct Launch: Decodable, Sendable {
            let requiredStage: Int
            let cost: Wallet
        }

        struct UpgradeSink: Decodable, Sendable {
            let id: String
            let nameKo: String
            let cost: Wallet
        }

        struct Wallet: Codable, Equatable, Sendable {
            let credits: Int
            let parts: Int
            let circuits: Int
            let alloy: Int
            let starCores: Int

            var economyWallet: EconomyWallet {
                EconomyWallet(
                    credits: credits,
                    parts: parts,
                    circuits: circuits,
                    alloy: alloy,
                    starCores: starCores
                )
            }
        }
    }
}

enum ContentLoader {
    static func loadVerticalSlice(bundle: Bundle = .main) -> VerticalSliceContent {
        guard let url = bundle.url(forResource: "world_r1_r6", withExtension: "json") else {
            preconditionFailure("world_r1_r6.json is missing from the app bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            let world = try JSONDecoder().decode(VerticalSliceContent.self, from: data)
            let productionEnd = world.slice.productionStageEnd ?? world.slice.stageEnd
            let stages = world.stages.filter { $0.number <= productionEnd }
            let usedEnemyIDs = Set(stages.flatMap(\.wave))
            let enemies = world.enemies.filter { usedEnemyIDs.contains($0.id) && !$0.spriteId.isEmpty }
            precondition(Set(stages.flatMap(\.wave)).isSubset(of: Set(enemies.map(\.id))), "production stages reference unfinished sprites")
            return VerticalSliceContent(
                contentVersion: world.contentVersion,
                slice: world.slice,
                player: world.player,
                drones: world.drones,
                regions: world.regions,
                enemies: enemies,
                stages: stages,
                economy: world.economy
            )
        } catch {
            preconditionFailure("Cannot decode world content: \(error)")
        }
    }
}

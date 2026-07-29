import Foundation

struct VerticalSliceContent: Decodable, Sendable {
    let contentVersion: String
    let slice: Slice
    let player: Player
    let drones: [Drone]
    let enemies: [Enemy]
    let stages: [Stage]

    struct Slice: Decodable, Sendable {
        let id: String
        let regionId: String
        let stageStart: Int
        let stageEnd: Int
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

        enum CodingKeys: String, CodingKey {
            case id, nameKo, hpMultiplierPpm, weakness, spriteId
            case enemyClass = "class"
        }
    }

    struct Stage: Decodable, Sendable {
        let number: Int
        let baseHp: Int
        let baseReward: Int
        let wave: [String]
        let bossTier: Int?
        let timeLimitMs: Int?
        let rewardMultiplierPpm: Int
    }
}

enum ContentLoader {
    static func loadVerticalSlice(bundle: Bundle = .main) -> VerticalSliceContent {
        guard let url = bundle.url(forResource: "r1_vertical_slice", withExtension: "json") else {
            preconditionFailure("r1_vertical_slice.json is missing from the app bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(VerticalSliceContent.self, from: data)
        } catch {
            preconditionFailure("Cannot decode vertical slice content: \(error)")
        }
    }
}

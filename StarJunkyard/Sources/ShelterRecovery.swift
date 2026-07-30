import Foundation

struct ShelterRecovery: Sendable {
    struct Goal: Equatable, Sendable {
        let title: String
        let detail: String
        let current: Int
        let required: Int
    }

    static let reactorRequirement = 12

    static func deliveredComponents(enemyClass: String) -> Int {
        switch enemyClass {
        case "boss": 6
        case "elite": 3
        default: 1
        }
    }

    static func milestone(for deliveredParts: Int) -> Int {
        switch max(0, deliveredParts) {
        case 0..<3: 0
        case 3..<7: 1
        case 7..<reactorRequirement: 2
        default: 3
        }
    }

    static func chapter(for deliveredParts: Int) -> Int {
        deliveredParts >= reactorRequirement ? 1 : 0
    }

    static func goal(deliveredParts: Int, highestStage: Int) -> Goal {
        let delivered = max(0, deliveredParts)
        switch milestone(for: delivered) {
        case 0:
            return Goal(
                title: "비상 조명 복구",
                detail: "괴수 부품을 피난처 반응로로 보내세요",
                current: min(delivered, 3),
                required: 3
            )
        case 1:
            return Goal(
                title: "보라 작업대 재가동",
                detail: "작업반 전력을 되찾기 위한 다음 복구",
                current: min(delivered, 7),
                required: 7
            )
        case 2:
            return Goal(
                title: "피난처 반응로 재점화",
                detail: "출항 준비를 위해 마지막 회로를 연결하세요",
                current: min(delivered, reactorRequirement),
                required: reactorRequirement
            )
        default:
            if highestStage > 10 {
                return Goal(
                    title: "출항 선체 조립",
                    detail: "R1 끝골목을 정리해 피난처를 출항시키세요",
                    current: min(max(10, highestStage), 20),
                    required: 20
                )
            }
            return Goal(
                title: "S10 압착왕 코어 회수",
                detail: "추진기를 고쳐 피난처 7호를 출항시키세요",
                current: min(max(1, highestStage), 10),
                required: 10
            )
        }
    }

    static func milestoneTitle(_ milestone: Int) -> String {
        switch milestone {
        case 1: "비상 조명 점등"
        case 2: "보라 작업대 재가동"
        case 3: "피난처 반응로 재점화"
        default: "폐기 판정"
        }
    }
}

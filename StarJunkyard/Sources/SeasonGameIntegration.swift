import Foundation

struct SeasonGameplayCoordinator: Sendable {
    private let engine: SeasonEngine
    private(set) var progress: SeasonProgress
    private(set) var eventSequence: Int
    private(set) var premiumUnlocked: Bool

    init(
        save: GameSave,
        catalog: SeasonCatalog,
        date: Date,
        clockSuspect: Bool,
        premiumUnlocked: Bool = false
    ) {
        engine = SeasonEngine(catalog: catalog)
        progress = engine.synchronize(save.seasonProgress, at: date, clockSuspect: clockSuspect)
        eventSequence = max(0, save.seasonEventSequence)
        self.premiumUnlocked = premiumUnlocked
        progress.premiumUnlocked = premiumUnlocked
    }

    mutating func updatePremiumUnlocked(_ unlocked: Bool) {
        premiumUnlocked = unlocked
        progress.premiumUnlocked = unlocked
    }

    mutating func synchronize(at date: Date, clockSuspect: Bool) {
        progress = engine.synchronize(progress, at: date, clockSuspect: clockSuspect)
        progress.premiumUnlocked = premiumUnlocked
    }

    func snapshot(at date: Date, clockSuspect: Bool) throws -> SeasonSnapshot {
        try engine.snapshot(progress: progress, at: date, clockSuspect: clockSuspect).snapshot
    }

    @discardableResult
    mutating func record(
        metric: SeasonMetric,
        amount: Int = 1,
        playXP: Int = 0,
        eventID suppliedEventID: String? = nil,
        at date: Date,
        clockSuspect: Bool
    ) -> SeasonEventResult? {
        guard amount > 0, playXP >= 0 else { return nil }
        guard shouldRecord(metric: metric, playXP: playXP, at: date, clockSuspect: clockSuspect) else {
            return nil
        }

        let eventID: String
        if let suppliedEventID {
            eventID = suppliedEventID
        } else {
            eventSequence += 1
            eventID = "game:\(progress.activeSeasonID):\(eventSequence):\(metric.rawValue)"
        }
        guard let applied = try? engine.apply(
            SeasonGameplayEvent(id: eventID, metric: metric, amount: amount, playXP: playXP),
            to: progress,
            at: date,
            clockSuspect: clockSuspect
        ) else { return nil }
        progress = applied.progress
        progress.premiumUnlocked = premiumUnlocked
        return applied.result
    }

    func write(to save: inout GameSave) {
        save.seasonProgress = progress
        save.seasonEventSequence = eventSequence
    }

    private func shouldRecord(
        metric: SeasonMetric,
        playXP: Int,
        at date: Date,
        clockSuspect: Bool
    ) -> Bool {
        guard let resolved = try? engine.snapshot(progress: progress, at: date, clockSuspect: clockSuspect) else {
            return false
        }
        let missionCanProgress = (resolved.snapshot.dailyMissions + resolved.snapshot.weeklyMissions).contains { mission in
            mission.definition.metric == metric &&
                resolved.progress.missionProgress[mission.instanceID, default: 0] < mission.definition.target
        }
        let playXPCanProgress = playXP > 0 && resolved.snapshot.weeklyXP < resolved.snapshot.definition.weeklyXPCap
        return missionCanProgress || playXPCanProgress
    }
}

enum SeasonRewardApplicationError: Error, Equatable {
    case unsupportedReward(String)
}

enum SeasonSaveRewardService {
    @discardableResult
    static func claim(
        level: Int,
        track: SeasonRewardTrack,
        catalog: SeasonCatalog,
        premiumUnlocked: Bool,
        save: inout GameSave
    ) throws -> SeasonDefinition.Reward {
        let engine = SeasonEngine(catalog: catalog)
        guard var progress = save.seasonProgress else { throw SeasonEngineError.unknownSeason }
        progress.premiumUnlocked = premiumUnlocked
        let claimed = try engine.claimReward(level: level, track: track, progress: progress)

        var candidate = save
        try apply(claimed.reward, to: &candidate)
        candidate.seasonProgress = claimed.progress
        candidate.schemaVersion = GameSave.currentSchemaVersion
        candidate.revision += 1
        candidate.updatedAt = Date()
        save = candidate
        return claimed.reward
    }

    static func description(for reward: SeasonDefinition.Reward) -> String {
        switch reward.kind {
        case .currency:
            return reward.itemID == "credits" ? "고철 +\(reward.amount)" : "재화 \(reward.itemID) +\(reward.amount)"
        case .material:
            let name: String
            switch reward.itemID {
            case "parts": name = "부품"
            case "circuit": name = "회로"
            case "alloy": name = "합금"
            case "stellar_core": name = "별 코어"
            default: name = reward.itemID
            }
            return "\(name) +\(reward.amount)"
        case .story: return "기록 해금 • \(reward.itemID)"
        case .cosmetic: return "외형 해금 • \(reward.itemID)"
        case .convenience: return "편의 슬롯 해금 • \(reward.itemID)"
        }
    }

    private static func apply(_ reward: SeasonDefinition.Reward, to save: inout GameSave) throws {
        switch reward.kind {
        case .currency where reward.itemID == "credits":
            save.credits += reward.amount
        case .material where reward.itemID == "parts":
            save.parts += reward.amount
        case .material where reward.itemID == "circuit":
            save.idleOperations.circuits += reward.amount
        case .material where reward.itemID == "alloy":
            save.idleOperations.alloy += reward.amount
        case .material where reward.itemID == "stellar_core":
            save.starCores += reward.amount
        case .story:
            insert(reward.itemID, into: &save.storyLogIDs)
        case .cosmetic:
            insert(reward.itemID, into: &save.claimedSeasonCosmeticIDs)
        case .convenience:
            insert(reward.itemID, into: &save.claimedSeasonConvenienceIDs)
        default:
            throw SeasonRewardApplicationError.unsupportedReward(reward.itemID)
        }
    }

    private static func insert(_ id: String, into values: inout [String]) {
        guard !values.contains(id) else { return }
        values.append(id)
        values.sort()
    }
}

import Foundation

enum SeasonMetric: String, Codable, CaseIterable, Sendable {
    case dismantleEnemy = "dismantle_enemy"
    case salvagePart = "salvage_part"
    case manualSalvage = "manual_salvage"
    case crewAttack = "crew_attack"
    case clearStage = "clear_stage"
    case facilityJob = "facility_job"
    case defeatBoss = "defeat_boss"
    case expeditionComplete = "expedition_complete"
}

struct SeasonDefinition: Codable, Equatable, Sendable {
    struct Mission: Codable, Equatable, Sendable {
        enum Cadence: String, Codable, Sendable {
            case daily
            case weekly
        }

        let id: String
        let titleKo: String
        let cadence: Cadence
        let metric: SeasonMetric
        let target: Int
        let xp: Int
    }

    struct Reward: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case currency
            case material
            case story
            case cosmetic
            case convenience
        }

        let kind: Kind
        let itemID: String
        let amount: Int
    }

    struct RewardTier: Codable, Equatable, Sendable {
        let level: Int
        let xpRequired: Int
        let free: Reward
        let premium: Reward
    }

    let schemaVersion: Int
    let contentVersion: String
    let seasonID: String
    let titleKo: String
    let startsAt: Date
    let endsAt: Date
    let selectionSeed: UInt64
    let weeklyXPCap: Int
    let codexEntryID: String
    let dailyMissionPool: [Mission]
    let weeklyMissions: [Mission]
    let rewardTiers: [RewardTier]

    var duration: TimeInterval { endsAt.timeIntervalSince(startsAt) }

    func contains(_ date: Date) -> Bool {
        startsAt <= date && date < endsAt
    }

    func dayIndex(at date: Date) -> Int {
        boundedIndex(at: date, interval: 24 * 60 * 60, maximum: 55)
    }

    func weekIndex(at date: Date) -> Int {
        boundedIndex(at: date, interval: 7 * 24 * 60 * 60, maximum: 7)
    }

    private func boundedIndex(at date: Date, interval: TimeInterval, maximum: Int) -> Int {
        let elapsed = max(0, date.timeIntervalSince(startsAt))
        return min(maximum, Int(elapsed / interval))
    }
}

struct SeasonCatalog: Equatable, Sendable {
    let current: SeasonDefinition
    let next: SeasonDefinition

    var definitions: [SeasonDefinition] { [current, next] }

    func definition(id: String) -> SeasonDefinition? {
        definitions.first { $0.seasonID == id }
    }

    func definition(at date: Date) -> SeasonDefinition? {
        definitions.first { $0.contains(date) }
    }
}

struct SeasonCodexRecord: Codable, Equatable, Sendable {
    let seasonID: String
    let titleKo: String
    let codexEntryID: String
    let earnedXP: Int
    let highestTier: Int
    let archivedAt: Date
}

struct SeasonProgress: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var schemaVersion: Int
    var activeSeasonID: String
    var totalXP: Int
    var premiumUnlocked: Bool
    var lastTrustedDayIndex: Int
    var lastTrustedWeekIndex: Int
    var missionProgress: [String: Int]
    var completedMissionIDs: [String]
    var processedEventIDs: [String]
    var weeklyAwardedXP: [String: Int]
    var claimedRewardKeys: [String]
    var codexRecords: [SeasonCodexRecord]

    static func start(season: SeasonDefinition, at date: Date) -> SeasonProgress {
        SeasonProgress(
            schemaVersion: schemaVersion,
            activeSeasonID: season.seasonID,
            totalXP: 0,
            premiumUnlocked: false,
            lastTrustedDayIndex: season.dayIndex(at: date),
            lastTrustedWeekIndex: season.weekIndex(at: date),
            missionProgress: [:],
            completedMissionIDs: [],
            processedEventIDs: [],
            weeklyAwardedXP: [:],
            claimedRewardKeys: [],
            codexRecords: []
        )
    }
}

struct SeasonMissionInstance: Equatable, Sendable {
    let instanceID: String
    let definition: SeasonDefinition.Mission
    let periodIndex: Int
}

struct SeasonGameplayEvent: Equatable, Sendable {
    let id: String
    let metric: SeasonMetric
    let amount: Int
    let playXP: Int
}

struct SeasonEventResult: Equatable, Sendable {
    let awardedXP: Int
    let progressedMissionIDs: [String]
    let completedMissionIDs: [String]
    let weeklyCapReached: Bool
    let ignoredDuplicate: Bool
}

struct SeasonSnapshot: Equatable, Sendable {
    enum Phase: String, Sendable {
        case upcoming
        case active
        case ended
        case transitionHeld
    }

    let definition: SeasonDefinition
    let phase: Phase
    let dailyMissions: [SeasonMissionInstance]
    let weeklyMissions: [SeasonMissionInstance]
    let unlockedTier: Int
    let weeklyXP: Int
}

enum SeasonRewardTrack: String, Sendable {
    case free
    case premium
}

enum SeasonEngineError: Error, Equatable {
    case unknownSeason
    case inactiveSeason
    case invalidEvent
    case unknownTier
    case tierLocked
    case premiumRequired
    case alreadyClaimed
}

struct SeasonEngine: Sendable {
    static let expectedDuration: TimeInterval = 8 * 7 * 24 * 60 * 60
    static let expectedTierCount = 40
    static let expectedWeeklyXPCap = 2_500

    let catalog: SeasonCatalog

    func synchronize(
        _ existing: SeasonProgress?,
        at date: Date,
        clockSuspect: Bool
    ) -> SeasonProgress {
        guard var progress = existing else {
            let definition = catalog.definition(at: date) ?? catalog.current
            return .start(season: definition, at: date)
        }
        guard !clockSuspect else { return progress }

        let active = catalog.definition(id: progress.activeSeasonID)
        if let target = catalog.definition(at: date), target.seasonID != progress.activeSeasonID {
            if let active {
                archive(active, progress: &progress, at: date)
            }
            return freshProgress(for: target, at: date, preserving: progress.codexRecords)
        }

        if let active {
            progress.lastTrustedDayIndex = active.dayIndex(at: date)
            progress.lastTrustedWeekIndex = active.weekIndex(at: date)
            if date >= active.endsAt {
                archive(active, progress: &progress, at: date)
            }
        }
        return progress
    }

    func snapshot(
        progress existing: SeasonProgress?,
        at date: Date,
        clockSuspect: Bool
    ) throws -> (progress: SeasonProgress, snapshot: SeasonSnapshot) {
        let progress = synchronize(existing, at: date, clockSuspect: clockSuspect)
        guard let definition = catalog.definition(id: progress.activeSeasonID) else {
            throw SeasonEngineError.unknownSeason
        }
        let phase: SeasonSnapshot.Phase
        if clockSuspect && !definition.contains(date) {
            phase = .transitionHeld
        } else if date < definition.startsAt {
            phase = .upcoming
        } else if date >= definition.endsAt {
            phase = .ended
        } else {
            phase = .active
        }
        let day = clockSuspect ? progress.lastTrustedDayIndex : definition.dayIndex(at: date)
        let week = clockSuspect ? progress.lastTrustedWeekIndex : definition.weekIndex(at: date)
        let weeklyKey = weekKey(seasonID: definition.seasonID, weekIndex: week)
        let snapshot = SeasonSnapshot(
            definition: definition,
            phase: phase,
            dailyMissions: dailyMissions(for: definition, dayIndex: day),
            weeklyMissions: weeklyMissions(for: definition, throughWeek: week),
            unlockedTier: unlockedTier(definition: definition, xp: progress.totalXP),
            weeklyXP: progress.weeklyAwardedXP[weeklyKey, default: 0]
        )
        return (progress, snapshot)
    }

    func dailyMissions(
        for definition: SeasonDefinition,
        dayIndex: Int
    ) -> [SeasonMissionInstance] {
        var candidates = definition.dailyMissionPool
        var generator = PCG32(
            seed: definition.selectionSeed ^ stableSeed("\(definition.seasonID):\(dayIndex)"),
            stream: 0x5345_4153_4F4E
        )
        if candidates.count > 1 {
            for index in stride(from: candidates.count - 1, through: 1, by: -1) {
                let other = Int(generator.bounded(UInt32(index + 1)))
                candidates.swapAt(index, other)
            }
        }
        return candidates.prefix(3).map {
            SeasonMissionInstance(
                instanceID: "\(definition.seasonID):d\(dayIndex):\($0.id)",
                definition: $0,
                periodIndex: dayIndex
            )
        }
    }

    func weeklyMissions(
        for definition: SeasonDefinition,
        throughWeek weekIndex: Int
    ) -> [SeasonMissionInstance] {
        (0...max(0, min(7, weekIndex))).flatMap { week in
            definition.weeklyMissions.map {
                SeasonMissionInstance(
                    instanceID: "\(definition.seasonID):w\(week):\($0.id)",
                    definition: $0,
                    periodIndex: week
                )
            }
        }
    }

    func apply(
        _ event: SeasonGameplayEvent,
        to existing: SeasonProgress?,
        at date: Date,
        clockSuspect: Bool
    ) throws -> (progress: SeasonProgress, result: SeasonEventResult) {
        guard !event.id.isEmpty, event.amount > 0, event.playXP >= 0 else {
            throw SeasonEngineError.invalidEvent
        }
        let resolved = try snapshot(progress: existing, at: date, clockSuspect: clockSuspect)
        var progress = resolved.progress
        guard resolved.snapshot.phase == .active || resolved.snapshot.phase == .transitionHeld else {
            throw SeasonEngineError.inactiveSeason
        }
        if progress.processedEventIDs.contains(event.id) {
            return (progress, SeasonEventResult(
                awardedXP: 0,
                progressedMissionIDs: [],
                completedMissionIDs: [],
                weeklyCapReached: resolved.snapshot.weeklyXP >= resolved.snapshot.definition.weeklyXPCap,
                ignoredDuplicate: true
            ))
        }

        let openMissions = resolved.snapshot.dailyMissions + resolved.snapshot.weeklyMissions
        var progressed: [String] = []
        var completed: [String] = []
        var missionXP = 0
        for mission in openMissions where mission.definition.metric == event.metric {
            let oldValue = progress.missionProgress[mission.instanceID, default: 0]
            let newValue = min(mission.definition.target, oldValue + event.amount)
            guard newValue != oldValue else { continue }
            progress.missionProgress[mission.instanceID] = newValue
            progressed.append(mission.instanceID)
            if oldValue < mission.definition.target, newValue >= mission.definition.target {
                completed.append(mission.instanceID)
                if !progress.completedMissionIDs.contains(mission.instanceID) {
                    progress.completedMissionIDs.append(mission.instanceID)
                    missionXP += mission.definition.xp
                }
            }
        }

        let requestedXP = event.playXP + missionXP
        let definition = resolved.snapshot.definition
        let week = clockSuspect ? progress.lastTrustedWeekIndex : definition.weekIndex(at: date)
        let key = weekKey(seasonID: definition.seasonID, weekIndex: week)
        let alreadyAwarded = progress.weeklyAwardedXP[key, default: 0]
        let awarded = min(requestedXP, max(0, definition.weeklyXPCap - alreadyAwarded))
        progress.totalXP += awarded
        progress.weeklyAwardedXP[key] = alreadyAwarded + awarded
        progress.processedEventIDs.append(event.id)
        return (progress, SeasonEventResult(
            awardedXP: awarded,
            progressedMissionIDs: progressed.sorted(),
            completedMissionIDs: completed.sorted(),
            weeklyCapReached: awarded < requestedXP || alreadyAwarded + awarded >= definition.weeklyXPCap,
            ignoredDuplicate: false
        ))
    }

    func claimReward(
        level: Int,
        track: SeasonRewardTrack,
        progress existing: SeasonProgress
    ) throws -> (progress: SeasonProgress, reward: SeasonDefinition.Reward) {
        guard let definition = catalog.definition(id: existing.activeSeasonID) else {
            throw SeasonEngineError.unknownSeason
        }
        guard let tier = definition.rewardTiers.first(where: { $0.level == level }) else {
            throw SeasonEngineError.unknownTier
        }
        guard existing.totalXP >= tier.xpRequired else { throw SeasonEngineError.tierLocked }
        if track == .premium, !existing.premiumUnlocked {
            throw SeasonEngineError.premiumRequired
        }
        let key = "\(definition.seasonID):\(track.rawValue):\(level)"
        guard !existing.claimedRewardKeys.contains(key) else {
            throw SeasonEngineError.alreadyClaimed
        }
        var progress = existing
        progress.claimedRewardKeys.append(key)
        return (progress, track == .free ? tier.free : tier.premium)
    }

    private func archive(
        _ definition: SeasonDefinition,
        progress: inout SeasonProgress,
        at date: Date
    ) {
        guard !progress.codexRecords.contains(where: { $0.seasonID == definition.seasonID }) else {
            return
        }
        progress.codexRecords.append(SeasonCodexRecord(
            seasonID: definition.seasonID,
            titleKo: definition.titleKo,
            codexEntryID: definition.codexEntryID,
            earnedXP: progress.totalXP,
            highestTier: unlockedTier(definition: definition, xp: progress.totalXP),
            archivedAt: date
        ))
    }

    private func freshProgress(
        for definition: SeasonDefinition,
        at date: Date,
        preserving records: [SeasonCodexRecord]
    ) -> SeasonProgress {
        var progress = SeasonProgress.start(season: definition, at: date)
        progress.codexRecords = records
        return progress
    }

    private func unlockedTier(definition: SeasonDefinition, xp: Int) -> Int {
        definition.rewardTiers.last(where: { xp >= $0.xpRequired })?.level ?? 0
    }

    private func weekKey(seasonID: String, weekIndex: Int) -> String {
        "\(seasonID):w\(weekIndex)"
    }

    private func stableSeed(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

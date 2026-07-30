import Foundation

enum EconomyMath {
    static let ppm = 1_000_000

    static func applyingPPM(_ multiplier: Int, to value: Int) -> Int {
        precondition(value >= 0 && multiplier >= 0)
        let (whole, wholeOverflow) = (value / ppm).multipliedReportingOverflow(by: multiplier)
        let (fractionProduct, fractionOverflow) = (value % ppm).multipliedReportingOverflow(by: multiplier)
        guard !wholeOverflow, !fractionOverflow else { return Int.max }
        let fractional = fractionProduct / ppm
        let (result, overflow) = whole.addingReportingOverflow(fractional)
        return overflow ? Int.max : result
    }
}

struct EconomyWallet: Codable, Equatable, Sendable {
    var credits: Int
    var parts: Int
    var circuits: Int
    var alloy: Int
    var starCores: Int

    static let zero = EconomyWallet(credits: 0, parts: 0, circuits: 0, alloy: 0, starCores: 0)

    static func + (left: EconomyWallet, right: EconomyWallet) -> EconomyWallet {
        EconomyWallet(
            credits: left.credits + right.credits,
            parts: left.parts + right.parts,
            circuits: left.circuits + right.circuits,
            alloy: left.alloy + right.alloy,
            starCores: left.starCores + right.starCores
        )
    }

    static func * (wallet: EconomyWallet, multiplier: Int) -> EconomyWallet {
        EconomyWallet(
            credits: wallet.credits * multiplier,
            parts: wallet.parts * multiplier,
            circuits: wallet.circuits * multiplier,
            alloy: wallet.alloy * multiplier,
            starCores: wallet.starCores * multiplier
        )
    }

    func scaled(byPPM multiplier: Int) -> EconomyWallet {
        EconomyWallet(
            credits: credits * multiplier / R1Economy.ppm,
            parts: parts * multiplier / R1Economy.ppm,
            circuits: circuits * multiplier / R1Economy.ppm,
            alloy: alloy * multiplier / R1Economy.ppm,
            starCores: starCores * multiplier / R1Economy.ppm
        )
    }

    func covers(_ cost: EconomyWallet) -> Bool {
        credits >= cost.credits
            && parts >= cost.parts
            && circuits >= cost.circuits
            && alloy >= cost.alloy
            && starCores >= cost.starCores
    }

    func subtracting(_ cost: EconomyWallet) -> EconomyWallet? {
        guard covers(cost) else { return nil }
        return EconomyWallet(
            credits: credits - cost.credits,
            parts: parts - cost.parts,
            circuits: circuits - cost.circuits,
            alloy: alloy - cost.alloy,
            starCores: starCores - cost.starCores
        )
    }
}

enum R1EncounterRule: String, Codable, Sendable {
    case normal
    case elite
    case boss
    case regionBoss

    static func expected(for stage: Int, regionEnd: Int = 60) -> R1EncounterRule {
        precondition(stage >= 1 && stage <= regionEnd)
        if stage == regionEnd { return .regionBoss }
        if stage.isMultiple(of: 10) { return .boss }
        if stage.isMultiple(of: 5) { return .elite }
        return .normal
    }
}

struct R1Economy: Sendable {
    static let ppm = 1_000_000

    struct OfflineHarvest: Equatable, Sendable {
        let stage: Int
        let elapsedSeconds: Int
        let cycles: Int
        let reward: EconomyWallet
    }

    struct LaunchStatus: Equatable, Sendable {
        let requiredStage: Int
        let stageReady: Bool
        let walletReady: Bool
        let eligible: Bool
        let missing: EconomyWallet
    }

    static func battleReward(
        for stage: VerticalSliceContent.Stage,
        enemies: [VerticalSliceContent.Enemy],
        partRewards: VerticalSliceContent.Economy.EnemyPartRewards
    ) -> EconomyWallet {
        let enemyByID = Dictionary(uniqueKeysWithValues: enemies.map { ($0.id, $0) })
        let creditsPerEnemy = EconomyMath.applyingPPM(stage.rewardMultiplierPpm, to: stage.baseReward)
        var reward = EconomyWallet.zero
        for enemyID in stage.wave {
            guard let enemy = enemyByID[enemyID] else { continue }
            reward.credits += creditsPerEnemy
            switch enemy.enemyClass {
            case "elite": reward.parts += partRewards.elite
            case "boss": reward.parts += partRewards.boss
            default: reward.parts += partRewards.normal
            }
        }
        return reward
    }

    static func firstClearReward(for stage: VerticalSliceContent.Stage) -> EconomyWallet {
        stage.firstClearReward?.economyWallet ?? .zero
    }

    static func offlineHarvest(
        lastClearedStage: Int,
        elapsed: TimeInterval,
        content: VerticalSliceContent
    ) -> OfflineHarvest? {
        guard
            let economy = content.economy,
            let stage = content.stages.first(where: { $0.number == lastClearedStage })
        else { return nil }

        let elapsedSeconds = Int(min(max(0, elapsed), TimeInterval(economy.offline.freeCapSeconds)).rounded(.down))
        let cycles = elapsedSeconds / economy.offline.cycleSeconds
        let fullCycle = battleReward(for: stage, enemies: content.enemies, partRewards: economy.enemyPartRewards)
        let reward = (fullCycle * cycles).scaled(byPPM: economy.offline.efficiencyPpm)
        return OfflineHarvest(stage: stage.number, elapsedSeconds: elapsedSeconds, cycles: cycles, reward: reward)
    }

    static func launchStatus(
        highestClearedStage: Int,
        wallet: EconomyWallet,
        launch: VerticalSliceContent.Economy.Launch
    ) -> LaunchStatus {
        let cost = launch.cost.economyWallet
        let missing = EconomyWallet(
            credits: max(0, cost.credits - wallet.credits),
            parts: max(0, cost.parts - wallet.parts),
            circuits: max(0, cost.circuits - wallet.circuits),
            alloy: max(0, cost.alloy - wallet.alloy),
            starCores: max(0, cost.starCores - wallet.starCores)
        )
        let stageReady = highestClearedStage >= launch.requiredStage
        let walletReady = wallet.covers(cost)
        return LaunchStatus(
            requiredStage: launch.requiredStage,
            stageReady: stageReady,
            walletReady: walletReady,
            eligible: stageReady && walletReady,
            missing: missing
        )
    }
}

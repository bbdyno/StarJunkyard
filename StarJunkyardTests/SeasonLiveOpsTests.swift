import Foundation
import XCTest
@testable import StarJunkyard

final class SeasonLiveOpsTests: XCTestCase {
    func testBundledCatalogHasContiguousEightWeekUTCSeasonsAndSeparatedTracks() {
        let catalog = SeasonContentLoader.loadCatalog(bundle: Bundle(for: Self.self))

        XCTAssertEqual(catalog.current.duration, SeasonEngine.expectedDuration)
        XCTAssertEqual(catalog.next.duration, SeasonEngine.expectedDuration)
        XCTAssertEqual(catalog.current.endsAt, catalog.next.startsAt)
        for season in catalog.definitions {
            XCTAssertEqual(season.contentVersion, "1.0.0")
            XCTAssertEqual(season.dailyMissionPool.count, 6)
            XCTAssertEqual(season.weeklyMissions.count, 4)
            XCTAssertEqual(season.weeklyXPCap, 2_500)
            XCTAssertEqual(season.rewardTiers.map(\.level), Array(1...40))
            XCTAssertTrue(season.rewardTiers.allSatisfy {
                $0.premium.kind == .cosmetic || $0.premium.kind == .convenience
            })
            XCTAssertFalse(season.codexEntryID.isEmpty)
        }
    }

    func testDailySelectionIsDeterministicThreeOfSix() {
        let catalog = SeasonContentLoader.loadCatalog(bundle: Bundle(for: Self.self))
        let engine = SeasonEngine(catalog: catalog)
        let firstDay = catalog.current.startsAt.addingTimeInterval(3 * day)

        let first = engine.dailyMissions(for: catalog.current, dayIndex: catalog.current.dayIndex(at: firstDay))
        let repeated = engine.dailyMissions(for: catalog.current, dayIndex: catalog.current.dayIndex(at: firstDay))
        let next = engine.dailyMissions(for: catalog.current, dayIndex: catalog.current.dayIndex(at: firstDay) + 1)

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(Set(first.map(\.instanceID)).count, 3)
        XCTAssertNotEqual(first.map(\.instanceID), next.map(\.instanceID))
        XCTAssertTrue(first.allSatisfy { catalog.current.dailyMissionPool.contains($0.definition) })
    }

    func testFourWeekliesPerWeekRemainOpenUntilSeasonEnd() throws {
        let catalog = SeasonContentLoader.loadCatalog(bundle: Bundle(for: Self.self))
        let engine = SeasonEngine(catalog: catalog)
        let weekFour = catalog.current.startsAt.addingTimeInterval(22 * day)
        let resolved = try engine.snapshot(progress: nil, at: weekFour, clockSuspect: false)

        XCTAssertEqual(resolved.snapshot.weeklyMissions.count, 16)
        XCTAssertEqual(
            resolved.snapshot.weeklyMissions.filter { $0.periodIndex == 0 }.count,
            4
        )

        let event = SeasonGameplayEvent(id: "clear-40", metric: .clearStage, amount: 40, playXP: 0)
        let applied = try engine.apply(event, to: resolved.progress, at: weekFour, clockSuspect: false)
        let completedWeeklies = applied.result.completedMissionIDs.filter { $0.contains(":w") }
        XCTAssertEqual(completedWeeklies.count, 4)
        XCTAssertTrue(completedWeeklies.contains { $0.contains(":w0:") })
    }

    func testPlayXPIsIdempotentAndStopsAtWeeklyCap() throws {
        let catalog = SeasonContentLoader.loadCatalog(bundle: Bundle(for: Self.self))
        let engine = SeasonEngine(catalog: catalog)
        let date = catalog.current.startsAt.addingTimeInterval(day)
        var progress: SeasonProgress?
        var lastResult: SeasonEventResult?

        for index in 1...3 {
            let event = SeasonGameplayEvent(
                id: "xp-\(index)",
                metric: .expeditionComplete,
                amount: 1,
                playXP: 1_000
            )
            let applied = try engine.apply(event, to: progress, at: date, clockSuspect: false)
            progress = applied.progress
            lastResult = applied.result
        }

        XCTAssertEqual(progress?.totalXP, 2_500)
        XCTAssertTrue(lastResult?.weeklyCapReached == true)
        let duplicate = try engine.apply(
            SeasonGameplayEvent(id: "xp-3", metric: .expeditionComplete, amount: 1, playXP: 1_000),
            to: progress,
            at: date,
            clockSuspect: false
        )
        XCTAssertTrue(duplicate.result.ignoredDuplicate)
        XCTAssertEqual(duplicate.result.awardedXP, 0)
        XCTAssertEqual(duplicate.progress.totalXP, 2_500)
    }

    func testClockSuspectPreservesXPAndHoldsOnlySeasonTransition() throws {
        let catalog = SeasonContentLoader.loadCatalog(bundle: Bundle(for: Self.self))
        let engine = SeasonEngine(catalog: catalog)
        let trustedDate = catalog.current.startsAt.addingTimeInterval(day)
        var progress = SeasonProgress.start(season: catalog.current, at: trustedDate)
        progress.totalXP = 500
        progress.weeklyAwardedXP["\(catalog.current.seasonID):w0"] = 500
        let afterBoundary = catalog.next.startsAt.addingTimeInterval(day)

        let held = try engine.snapshot(progress: progress, at: afterBoundary, clockSuspect: true)
        XCTAssertEqual(held.progress.activeSeasonID, catalog.current.seasonID)
        XCTAssertEqual(held.snapshot.phase, .transitionHeld)
        XCTAssertTrue(held.snapshot.dailyMissions.allSatisfy { $0.periodIndex == 1 })

        let applied = try engine.apply(
            SeasonGameplayEvent(id: "suspect-play", metric: .expeditionComplete, amount: 1, playXP: 300),
            to: held.progress,
            at: afterBoundary,
            clockSuspect: true
        )
        XCTAssertEqual(applied.progress.totalXP, 800)
        XCTAssertEqual(applied.progress.activeSeasonID, catalog.current.seasonID)

        let trusted = engine.synchronize(applied.progress, at: afterBoundary, clockSuspect: false)
        XCTAssertEqual(trusted.activeSeasonID, catalog.next.seasonID)
        XCTAssertEqual(trusted.totalXP, 0)
        XCTAssertEqual(trusted.codexRecords.count, 1)
        XCTAssertEqual(trusted.codexRecords[0].earnedXP, 800)
        XCTAssertEqual(trusted.codexRecords[0].codexEntryID, catalog.current.codexEntryID)

        let data = try JSONEncoder().encode(trusted)
        XCTAssertEqual(try JSONDecoder().decode(SeasonProgress.self, from: data), trusted)
    }

    func testFreeRewardDoesNotRequirePurchaseAndPremiumDoes() throws {
        let catalog = SeasonContentLoader.loadCatalog(bundle: Bundle(for: Self.self))
        let engine = SeasonEngine(catalog: catalog)
        var progress = SeasonProgress.start(season: catalog.current, at: catalog.current.startsAt)
        progress.totalXP = 500

        let free = try engine.claimReward(level: 1, track: .free, progress: progress)
        XCTAssertEqual(free.reward.kind, .currency)
        XCTAssertThrowsError(try engine.claimReward(level: 1, track: .premium, progress: progress)) {
            XCTAssertEqual($0 as? SeasonEngineError, .premiumRequired)
        }

        progress.premiumUnlocked = true
        let premium = try engine.claimReward(level: 1, track: .premium, progress: progress)
        XCTAssertEqual(premium.reward.kind, .cosmetic)
    }

    private let day: TimeInterval = 24 * 60 * 60
}

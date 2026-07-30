import SpriteKit
import XCTest
@testable import StarJunkyard

@MainActor
final class SeasonGameIntegrationTests: XCTestCase {
    func testSchemaSixCloudPayloadMigratesSeasonDefaultsAndRoundTripsSeasonOwnership() throws {
        let store = temporarySaveStore()
        var oldSave = GameSave.newGame(now: Date(timeIntervalSince1970: 1_000))
        oldSave.schemaVersion = 6
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: store.exportCloudData(oldSave)) as? [String: Any]
        )
        [
            "starCores",
            "seasonProgress",
            "seasonEventSequence",
            "claimedSeasonCosmeticIDs",
            "claimedSeasonConvenienceIDs"
        ].forEach { object.removeValue(forKey: $0) }
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        var migrated = try store.decodeCloudData(legacyData)
        XCTAssertEqual(migrated.schemaVersion, GameSave.currentSchemaVersion)
        XCTAssertNil(migrated.seasonProgress)
        XCTAssertEqual(migrated.seasonEventSequence, 0)
        XCTAssertEqual(migrated.starCores, 0)
        XCTAssertTrue(migrated.claimedSeasonCosmeticIDs.isEmpty)
        XCTAssertTrue(migrated.claimedSeasonConvenienceIDs.isEmpty)

        let catalog = testCatalog()
        var progress = SeasonProgress.start(season: catalog.current, at: activeDate(catalog))
        progress.totalXP = 777
        migrated.seasonProgress = progress
        migrated.seasonEventSequence = 42
        migrated.claimedSeasonCosmeticIDs = ["rust_signal_sticker_01"]
        migrated.claimedSeasonConvenienceIDs = ["loadout_preset_slot_rust_a"]
        migrated.starCores = 2

        let cloudRoundTrip = try store.decodeCloudData(store.exportCloudData(migrated))
        XCTAssertEqual(cloudRoundTrip.seasonProgress, progress)
        XCTAssertEqual(cloudRoundTrip.seasonEventSequence, 42)
        XCTAssertEqual(cloudRoundTrip.claimedSeasonCosmeticIDs, ["rust_signal_sticker_01"])
        XCTAssertEqual(cloudRoundTrip.claimedSeasonConvenienceIDs, ["loadout_preset_slot_rust_a"])
        XCTAssertEqual(cloudRoundTrip.starCores, 2)
    }

    func testGameplayCoordinatorUsesUniqueSequenceAndRejectsDuplicateOperationClaim() throws {
        let catalog = testCatalog()
        let date = activeDate(catalog)
        let save = GameSave.newGame(now: date)
        var coordinator = SeasonGameplayCoordinator(
            save: save,
            catalog: catalog,
            date: date,
            clockSuspect: false
        )

        let first = coordinator.record(
            metric: .expeditionComplete,
            playXP: 200,
            eventID: "operation:expedition-1:claim",
            at: date,
            clockSuspect: false
        )
        let duplicate = coordinator.record(
            metric: .expeditionComplete,
            playXP: 200,
            eventID: "operation:expedition-1:claim",
            at: date,
            clockSuspect: false
        )
        _ = coordinator.record(metric: .clearStage, playXP: 25, at: date, clockSuspect: false)
        _ = coordinator.record(metric: .defeatBoss, playXP: 100, at: date, clockSuspect: false)

        XCTAssertEqual(first?.awardedXP, 200)
        XCTAssertTrue(duplicate?.ignoredDuplicate == true)
        XCTAssertEqual(coordinator.eventSequence, 2)
        XCTAssertEqual(Set(coordinator.progress.processedEventIDs).count, 3)
        XCTAssertEqual(coordinator.progress.totalXP, 325)

        var saved = save
        coordinator.write(to: &saved)
        XCTAssertEqual(saved.seasonEventSequence, 2)
        XCTAssertEqual(saved.seasonProgress?.totalXP, 325)

        var cappedSave = save
        var cappedProgress = SeasonProgress.start(season: catalog.current, at: date)
        cappedProgress.totalXP = catalog.current.weeklyXPCap
        cappedProgress.weeklyAwardedXP["\(catalog.current.seasonID):w0"] = catalog.current.weeklyXPCap
        cappedSave.seasonProgress = cappedProgress
        var capped = SeasonGameplayCoordinator(
            save: cappedSave,
            catalog: catalog,
            date: date,
            clockSuspect: false
        )
        XCTAssertNil(capped.record(metric: .expeditionComplete, playXP: 50, at: date, clockSuspect: false))
        XCTAssertTrue(capped.progress.processedEventIDs.isEmpty)
    }

    func testFreeAndPremiumClaimsGrantRealWalletStoryAndOwnershipExactlyOnce() throws {
        let catalog = testCatalog()
        var save = GameSave.newGame(now: activeDate(catalog))
        var progress = SeasonProgress.start(season: catalog.current, at: activeDate(catalog))
        progress.totalXP = 20_000
        save.seasonProgress = progress

        _ = try SeasonSaveRewardService.claim(level: 1, track: .free, catalog: catalog, premiumUnlocked: false, save: &save)
        _ = try SeasonSaveRewardService.claim(level: 2, track: .free, catalog: catalog, premiumUnlocked: false, save: &save)
        _ = try SeasonSaveRewardService.claim(level: 4, track: .free, catalog: catalog, premiumUnlocked: false, save: &save)
        _ = try SeasonSaveRewardService.claim(level: 8, track: .free, catalog: catalog, premiumUnlocked: false, save: &save)
        _ = try SeasonSaveRewardService.claim(level: 10, track: .free, catalog: catalog, premiumUnlocked: false, save: &save)
        _ = try SeasonSaveRewardService.claim(level: 39, track: .free, catalog: catalog, premiumUnlocked: false, save: &save)

        XCTAssertEqual(save.credits, 100)
        XCTAssertEqual(save.parts, 20)
        XCTAssertEqual(save.idleOperations.circuits, 5)
        XCTAssertEqual(save.idleOperations.alloy, 3)
        XCTAssertEqual(save.starCores, 1)
        XCTAssertTrue(save.storyLogIDs.contains("rust_signal_record_01"))
        XCTAssertThrowsError(
            try SeasonSaveRewardService.claim(level: 1, track: .premium, catalog: catalog, premiumUnlocked: false, save: &save)
        ) { XCTAssertEqual($0 as? SeasonEngineError, .premiumRequired) }

        _ = try SeasonSaveRewardService.claim(level: 1, track: .premium, catalog: catalog, premiumUnlocked: true, save: &save)
        _ = try SeasonSaveRewardService.claim(level: 5, track: .premium, catalog: catalog, premiumUnlocked: true, save: &save)
        XCTAssertEqual(save.claimedSeasonCosmeticIDs, ["rust_signal_sticker_01"])
        XCTAssertEqual(save.claimedSeasonConvenienceIDs, ["loadout_preset_slot_rust_a"])
        XCTAssertThrowsError(
            try SeasonSaveRewardService.claim(level: 1, track: .free, catalog: catalog, premiumUnlocked: false, save: &save)
        ) { XCTAssertEqual($0 as? SeasonEngineError, .alreadyClaimed) }
        XCTAssertEqual(save.credits, 100)
    }

    func testPixelSeasonPanelShowsMissionsWeeklyCapFiveTierPagesAndFortyFourPointClaims() {
        let catalog = testCatalog()
        let date = activeDate(catalog)
        var save = GameSave.newGame(now: date)
        var progress = SeasonProgress.start(season: catalog.current, at: date)
        progress.totalXP = 2_600
        progress.weeklyAwardedXP["\(catalog.current.seasonID):w0"] = 900
        save.seasonProgress = progress
        let scene = PixelSeasonScene(save: save, catalog: catalog, nowProvider: { date })
        let view = SKView(frame: CGRect(origin: .zero, size: PixelSeasonScene.logicalSize))
        scene.didMove(to: view)

        XCTAssertEqual(label(named: "season_name", in: scene)?.text, catalog.current.titleKo)
        XCTAssertTrue(label(named: "season_xp", in: scene)?.text?.contains("900/2500") == true)
        XCTAssertTrue(label(named: "season_weekly_summary", in: scene)?.text?.contains("누적 주간") == true)
        XCTAssertEqual(nodes(withPrefix: "season_daily_", in: scene).compactMap { $0 as? SKLabelNode }.count, 3)
        XCTAssertEqual(label(named: "season_tier_page", in: scene)?.text, "보상 단계 1-5 / 40")
        XCTAssertEqual(label(named: "season_premium_state", in: scene)?.text, "프리미엄 미보유")
        for level in 1...5 {
            XCTAssertNotNil(rewardHitArea(named: "season_claim_free_\(level)", in: scene))
            XCTAssertNotNil(rewardHitArea(named: "season_claim_premium_\(level)", in: scene))
        }
        XCTAssertFalse(containsShapeNode(scene))

        scene.updatePremiumUnlocked(true)
        XCTAssertEqual(label(named: "season_premium_state", in: scene)?.text, "프리미엄 연결됨")

        scene.showRewardPage(containing: 40)
        XCTAssertNotNil(findNode(named: "season_tier_40", in: scene))
        XCTAssertEqual(label(named: "season_tier_page", in: scene)?.text, "보상 단계 36-40 / 40")

        let tabletViewport = PixelViewport(
            viewSize: CGSize(width: 1_032, height: 1_376),
            safeAreaInsets: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
            nativeScale: 2
        )
        scene.applyViewport(tabletViewport)
        XCTAssertNotNil(findNode(named: "season_mission_rail", in: scene))
        XCTAssertNotNil(findNode(named: "season_archive_rail", in: scene))
    }

    func testPanelClaimPersistsImmediatelyWithoutDoubleGrant() {
        let catalog = testCatalog()
        let date = activeDate(catalog)
        var save = GameSave.newGame(now: date)
        var progress = SeasonProgress.start(season: catalog.current, at: date)
        progress.totalXP = 500
        save.seasonProgress = progress
        let scene = PixelSeasonScene(save: save, catalog: catalog, nowProvider: { date })
        var persisted: GameSave?
        scene.onSave = { persisted = $0 }
        scene.didMove(to: SKView(frame: CGRect(origin: .zero, size: PixelSeasonScene.logicalSize)))

        XCTAssertTrue(scene.claimReward(level: 1, track: .free))
        XCTAssertEqual(persisted?.credits, 100)
        XCTAssertFalse(scene.claimReward(level: 1, track: .free))
        XCTAssertEqual(persisted?.credits, 100)
    }

    func testClockWarningAndEndedSeasonCodexAreVisible() throws {
        let catalog = testCatalog()
        let heldDate = catalog.next.startsAt.addingTimeInterval(24 * 60 * 60)
        var heldSave = GameSave.newGame(now: activeDate(catalog))
        heldSave.seasonProgress = SeasonProgress.start(season: catalog.current, at: activeDate(catalog))
        heldSave.idleOperations.lastObservedAt = heldDate.addingTimeInterval(10 * 60)
        heldSave.idleOperations.clockSuspect = true
        let held = PixelSeasonScene(save: heldSave, catalog: catalog, nowProvider: { heldDate })
        held.didMove(to: SKView(frame: CGRect(origin: .zero, size: PixelSeasonScene.logicalSize)))
        XCTAssertTrue(label(named: "season_clock_status", in: held)?.text?.contains("전환을 보류") == true)
        XCTAssertTrue(held.accessibilitySummary.contains("기기 시간 확인 필요"))

        var archivedSave = heldSave
        archivedSave.idleOperations.clockSuspect = false
        archivedSave.idleOperations.lastObservedAt = heldDate.addingTimeInterval(-60)
        let archived = PixelSeasonScene(save: archivedSave, catalog: catalog, nowProvider: { heldDate })
        archived.didMove(to: SKView(frame: CGRect(origin: .zero, size: PixelSeasonScene.logicalSize)))
        XCTAssertTrue(label(named: "season_archive", in: archived)?.text?.contains(catalog.current.titleKo) == true)
        XCTAssertTrue(label(named: "season_name", in: archived)?.text?.contains(catalog.next.titleKo) == true)
    }

    func testFacilitiesExposeReadableSeasonEntry() {
        let catalog = testCatalog()
        let date = activeDate(catalog)
        var save = GameSave.newGame(now: date)
        save.prologueSeen = true
        save.tutorialStep = 4
        let scene = CombatScene(
            content: ContentLoader.loadVerticalSlice(bundle: Bundle(for: Self.self)),
            save: save,
            showFacilityPanelOnLaunch: true,
            seasonCatalog: catalog,
            nowProvider: { date }
        )
        scene.didMove(to: SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize)))

        let entry = try? XCTUnwrap(findNode(named: "season_open", in: scene))
        XCTAssertNotNil(entry)
        XCTAssertTrue(allLabelTexts(in: scene).contains("시즌 확인 〉"))
    }

    func testCombatCooperativeAttackFeedsTheSelectedCrewMission() throws {
        let catalog = testCatalog()
        let engine = SeasonEngine(catalog: catalog)
        let crewDay = try XCTUnwrap((0...55).first { dayIndex in
            engine.dailyMissions(for: catalog.current, dayIndex: dayIndex)
                .contains { $0.definition.metric == .crewAttack }
        })
        let date = catalog.current.startsAt.addingTimeInterval(TimeInterval(crewDay) * 24 * 60 * 60 + 60)
        var save = GameSave.newGame(now: date)
        save.prologueSeen = true
        save.tutorialStep = 4
        let scene = CombatScene(
            content: ContentLoader.loadVerticalSlice(bundle: Bundle(for: Self.self)),
            save: save,
            seasonCatalog: catalog,
            nowProvider: { date }
        )
        var persisted: GameSave?
        scene.onSave = { persisted = $0 }
        scene.didMove(to: SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize)))
        scene.update(1)
        for step in 1...24 {
            scene.update(1 + Double(step) * 0.251)
        }
        scene.updateSeasonPremiumUnlocked(false)

        let crewMission = try XCTUnwrap(
            engine.dailyMissions(for: catalog.current, dayIndex: crewDay)
                .first { $0.definition.metric == .crewAttack }
        )
        XCTAssertEqual(persisted?.seasonProgress?.missionProgress[crewMission.instanceID], 1)
        XCTAssertTrue(persisted?.seasonProgress?.processedEventIDs.contains { $0.hasSuffix(":crew_attack") } == true)
    }

    private func testCatalog() -> SeasonCatalog {
        SeasonContentLoader.loadCatalog(bundle: Bundle(for: Self.self))
    }

    private func activeDate(_ catalog: SeasonCatalog) -> Date {
        catalog.current.startsAt.addingTimeInterval(24 * 60 * 60)
    }

    private func temporarySaveStore() -> GameSaveStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return GameSaveStore(directory: directory)
    }

    private func rewardHitArea(named name: String, in node: SKNode) -> SKSpriteNode? {
        nodes(named: name, in: node)
            .compactMap { $0 as? SKSpriteNode }
            .first { $0.size == PixelSeasonScene.rewardHitSize }
    }

    private func findNode(named name: String, in node: SKNode) -> SKNode? {
        if node.name == name { return node }
        return node.children.lazy.compactMap { self.findNode(named: name, in: $0) }.first
    }

    private func nodes(named name: String, in node: SKNode) -> [SKNode] {
        (node.name == name ? [node] : []) + node.children.flatMap { self.nodes(named: name, in: $0) }
    }

    private func nodes(withPrefix prefix: String, in node: SKNode) -> [SKNode] {
        ((node.name?.hasPrefix(prefix) == true) ? [node] : []) +
            node.children.flatMap { self.nodes(withPrefix: prefix, in: $0) }
    }

    private func label(named name: String, in node: SKNode) -> SKLabelNode? {
        nodes(named: name, in: node).compactMap { $0 as? SKLabelNode }.first
    }

    private func allLabelTexts(in node: SKNode) -> [String] {
        let own = (node as? SKLabelNode)?.text.map { [$0] } ?? []
        return own + node.children.flatMap(self.allLabelTexts)
    }

    private func containsShapeNode(_ node: SKNode) -> Bool {
        node is SKShapeNode || node.children.contains(where: self.containsShapeNode)
    }
}

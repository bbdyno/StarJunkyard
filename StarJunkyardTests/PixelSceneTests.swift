import SpriteKit
import XCTest
@testable import StarJunkyard

@MainActor
final class PixelSceneTests: XCTestCase {
    func testPCG32MatchesSharedReference() {
        var generator = PCG32(seed: 42, stream: 54)
        XCTAssertEqual(
            [generator.next(), generator.next(), generator.next(), generator.next(), generator.next()],
            [2_707_161_783, 2_068_313_097, 3_122_475_824, 2_211_639_955, 3_215_226_955]
        )
        XCTAssertEqual(generator.state, 9_440_484_487_994_590_321)
    }

    func testSharedVerticalSliceDecodes() {
        let bundle = Bundle(for: Self.self)
        let content = ContentLoader.loadVerticalSlice(bundle: bundle)
        XCTAssertEqual(content.contentVersion, "0.3.0")
        XCTAssertEqual(content.stages.map(\.number), Array(1...120))
        XCTAssertEqual(content.enemies.count, 16)
        XCTAssertEqual(content.enemies.last(where: { $0.id == "fridge_boar" })?.nameKo, "냉장고멧돼지")
        XCTAssertEqual(content.economy?.offline.efficiencyPpm, 700_000)
        XCTAssertEqual(content.stages[59].encounterClass, .regionBoss)
        XCTAssertEqual(content.stages[59].firstClearReward?.starCores, 1)
    }

    func testR1EncounterRulesCoverEliteBossAndRegionBoss() {
        XCTAssertEqual(R1EncounterRule.expected(for: 1), .normal)
        XCTAssertEqual(R1EncounterRule.expected(for: 5), .elite)
        XCTAssertEqual(R1EncounterRule.expected(for: 10), .boss)
        XCTAssertEqual(R1EncounterRule.expected(for: 55), .elite)
        XCTAssertEqual(R1EncounterRule.expected(for: 60), .regionBoss)
    }

    func testEconomyModelUsesBattleLootAndLastClearedStageForOffline() throws {
        let content = ContentLoader.loadVerticalSlice(bundle: Bundle(for: Self.self))
        let economy = try XCTUnwrap(content.economy)
        let stage1 = content.stages[0]
        XCTAssertEqual(
            R1Economy.battleReward(for: stage1, enemies: content.enemies, partRewards: economy.enemyPartRewards),
            EconomyWallet(credits: 80, parts: 24, circuits: 0, alloy: 0, starCores: 0)
        )

        let stage60 = content.stages[59]
        let fullCycle = R1Economy.battleReward(
            for: stage60,
            enemies: content.enemies,
            partRewards: economy.enemyPartRewards
        )
        let harvest = try XCTUnwrap(
            R1Economy.offlineHarvest(lastClearedStage: 60, elapsed: 75, content: content)
        )
        XCTAssertEqual(harvest.stage, 60)
        XCTAssertEqual(harvest.cycles, 1)
        XCTAssertEqual(harvest.reward.credits, fullCycle.credits * 700_000 / 1_000_000)
        XCTAssertEqual(harvest.reward.parts, 10)
        XCTAssertEqual(harvest.reward.circuits, 0)
        XCTAssertEqual(harvest.reward.starCores, 0)
    }

    func testR2LaunchRequiresStageAndAllFiveCurrencies() throws {
        let content = ContentLoader.loadVerticalSlice(bundle: Bundle(for: Self.self))
        let launch = try XCTUnwrap(content.economy?.launch)
        let exactCost = launch.cost.economyWallet

        let stageLocked = R1Economy.launchStatus(
            highestClearedStage: 59,
            wallet: exactCost,
            launch: launch
        )
        XCTAssertFalse(stageLocked.eligible)
        XCTAssertTrue(stageLocked.walletReady)

        let ready = R1Economy.launchStatus(
            highestClearedStage: 60,
            wallet: exactCost,
            launch: launch
        )
        XCTAssertTrue(ready.eligible)
        XCTAssertEqual(ready.missing, .zero)
        XCTAssertEqual(exactCost.subtracting(exactCost), .zero)
    }

    func testRootViewIsOneGameCanvasWithoutUIKitButtons() {
        let controller = GameViewController(content: sampleContent(), saveStore: temporarySaveStore())
        controller.loadViewIfNeeded()
        XCTAssertTrue(controller.view is SKView)
        XCTAssertTrue(controller.view.subviews.isEmpty)
        XCTAssertTrue(findButtons(in: controller.view).isEmpty)
        XCTAssertTrue((controller.view as? SKView)?.scene is SaveSelectionScene)
        XCTAssertNotNil(findNode(named: "continue_save", in: (controller.view as! SKView).scene!))
        XCTAssertNotNil(findNode(named: "cloud_load", in: (controller.view as! SKView).scene!))
    }

    func testSceneUsesPortraitLogicalCanvasAndPixelNodes() {
        let scene = CombatScene(content: sampleContent())
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        XCTAssertEqual(scene.size, CGSize(width: 360, height: 800))
        XCTAssertFalse(scene.children.isEmpty)
        XCTAssertFalse(containsShapeNode(scene), "Vector SKShapeNode is forbidden in the game canvas")
        XCTAssertNotNil(findNode(named: "actor_mo_base", in: scene))
        XCTAssertNotNil(findNode(named: "drone_riv0_base", in: scene))
        XCTAssertNotNil(findNode(named: "crew_bora_base", in: scene))
        XCTAssertNotNil(findNode(named: "enemy_can_bug", in: scene))
        XCTAssertNotNil(findNode(named: "shop_open", in: scene))
        XCTAssertNotNil(findNode(named: "crew_open", in: scene))
        XCTAssertNotNil(findNode(named: "facility_open", in: scene))
        XCTAssertNotNil(findNode(named: "records_open", in: scene))
        XCTAssertNotNil(findNode(named: "manual_salvage_1", in: scene))
        XCTAssertNotNil(findNode(named: "tutorial_panel", in: scene))
        XCTAssertNotNil(findNode(named: "story_goal", in: scene))
        XCTAssertNotNil(findNode(named: "story_panel", in: scene))
        XCTAssertNotNil(findNode(named: "story_continue", in: scene))
        XCTAssertNotNil(findNode(named: "shelter_reactor", in: scene))
        XCTAssertNotNil(findNode(named: "shelter_reactor_lamp_1", in: scene))
        XCTAssertNil(findNode(named: "mechanic_mo_debug", in: scene))
        assertIntegralPositions(scene)
    }

    func testNormalWaveSpawnsThreeIndividuallyTargetableEnemies() {
        let scene = CombatScene(content: multiEnemyContent())
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        XCTAssertNotNil(findNode(named: "enemy_slot_0", in: scene))
        XCTAssertNotNil(findNode(named: "enemy_slot_1", in: scene))
        XCTAssertNotNil(findNode(named: "enemy_slot_2", in: scene))
        XCTAssertNotNil(findNode(named: "enemy_fridge_boar", in: scene))
    }

    func testPhoneSafeAreaMovesHUDAndControlsInsideUsableFrame() {
        let scene = CombatScene(content: multiEnemyContent())
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        scene.didMove(to: view)
        let viewport = PixelViewport(
            viewSize: view.bounds.size,
            safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            nativeScale: 3
        )
        scene.applyViewport(viewport)

        let hud = findNode(named: "hud_panel", in: scene)!
        let hudOrigin = scene.convert(CGPoint.zero, from: hud)
        XCTAssertLessThanOrEqual(hudOrigin.y + 62, viewport.safeFrame.maxY + 0.001)
        let controls = findNode(named: "workshop_console", in: scene)!
        let controlsOrigin = scene.convert(CGPoint.zero, from: controls)
        XCTAssertGreaterThanOrEqual(controlsOrigin.y, viewport.safeFrame.minY)
        XCTAssertEqual(viewport.integerScale, 3)
    }

    func testIPadKeepsCentralCombatLaneAndAddsInformationRails() {
        let scene = CombatScene(content: multiEnemyContent())
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1032, height: 1376))
        scene.didMove(to: view)
        let viewport = PixelViewport(
            viewSize: view.bounds.size,
            safeAreaInsets: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
            nativeScale: 2
        )
        scene.applyViewport(viewport)

        XCTAssertEqual(viewport.laneFrame.size, CGSize(width: 360, height: 800))
        XCTAssertTrue(viewport.usesTabletRails)
        XCTAssertNotNil(findNode(named: "ipad_crew_rail", in: scene))
        XCTAssertNotNil(findNode(named: "ipad_wave_rail", in: scene))
    }

    func testLocalSaveRoundTripAndBackupRecovery() throws {
        let store = temporarySaveStore()
        var first = GameSave.newGame(now: Date(timeIntervalSince1970: 100))
        first.credits = 10
        first.cutterLevel = 2
        try store.save(first)

        var second = first
        second.revision = 2
        second.credits = 77
        try store.save(second)
        XCTAssertEqual(store.load(), second)

        try Data("broken".utf8).write(to: store.mainURL, options: .atomic)
        XCTAssertEqual(store.load(), first)
    }

    func testSchemaOneSaveMigratesSingleEnemyHPAndCrewLevel() throws {
        let data = Data(
            """
            {"schemaVersion":1,"revision":7,"updatedAt":100000,"stageIndex":2,"waveIndex":3,"enemyHP":41,"credits":12,"parts":4,"cutterLevel":2,"droneLevel":1,"magnetLevel":1,"tutorialStep":3,"combatTick":99,"highestStage":3,"cloudBackupEnabled":false}
            """.utf8
        )
        let migrated = try temporarySaveStore().decodeCloudData(data)
        XCTAssertEqual(migrated.schemaVersion, GameSave.currentSchemaVersion)
        XCTAssertEqual(migrated.enemyHPs, [41])
        XCTAssertEqual(migrated.crewLevel, 1)
        XCTAssertEqual(migrated.pressLevel, 1)
        XCTAssertEqual(migrated.sorterLevel, 0)
        XCTAssertEqual(migrated.yardIncomeBank, 0)
        XCTAssertTrue(migrated.discoveredEnemyIDs.isEmpty)
        XCTAssertEqual(migrated.storyChapter, 0)
        XCTAssertEqual(migrated.shelterRepairParts, 0)
        XCTAssertFalse(migrated.prologueSeen)
        XCTAssertTrue(migrated.defeatedBossStages.isEmpty)
        XCTAssertTrue(migrated.unlockedModuleIDs.isEmpty)
        XCTAssertEqual(migrated.idleOperations.workbenchSlots, 2)
        XCTAssertEqual(migrated.dailyInstantFinish, .empty)
        XCTAssertEqual(migrated.equippedBoraUniform, .base)
        XCTAssertNil(migrated.seasonProgress)
        XCTAssertTrue(migrated.claimedSeasonCosmeticIDs.isEmpty)
    }

    func testSchemaTwoSaveMigratesYardDefaults() throws {
        let data = Data(
            """
            {"schemaVersion":2,"revision":9,"updatedAt":100000,"stageIndex":0,"waveIndex":0,"enemyHPs":[25],"credits":44,"parts":6,"cutterLevel":2,"droneLevel":2,"magnetLevel":1,"crewLevel":3,"tutorialStep":4,"combatTick":120,"highestStage":4,"cloudBackupEnabled":true}
            """.utf8
        )
        let migrated = try temporarySaveStore().decodeCloudData(data)
        XCTAssertEqual(migrated.schemaVersion, GameSave.currentSchemaVersion)
        XCTAssertEqual(migrated.pressLevel, 1)
        XCTAssertEqual(migrated.warehouseLevel, 0)
        XCTAssertEqual(migrated.manualTapCount, 0)
    }

    func testShelterRecoveryDefinesReadableProgression() {
        XCTAssertEqual(ShelterRecovery.deliveredComponents(enemyClass: "normal"), 1)
        XCTAssertEqual(ShelterRecovery.deliveredComponents(enemyClass: "elite"), 3)
        XCTAssertEqual(ShelterRecovery.deliveredComponents(enemyClass: "boss"), 6)
        XCTAssertEqual(ShelterRecovery.milestone(for: 2), 0)
        XCTAssertEqual(ShelterRecovery.milestone(for: 3), 1)
        XCTAssertEqual(ShelterRecovery.milestone(for: 7), 2)
        XCTAssertEqual(ShelterRecovery.milestone(for: 12), 3)

        let firstGoal = ShelterRecovery.goal(deliveredParts: 1, highestStage: 1)
        XCTAssertEqual(firstGoal.title, "비상 조명 복구")
        XCTAssertEqual(firstGoal.current, 1)
        XCTAssertEqual(firstGoal.required, 3)
        let bossGoal = ShelterRecovery.goal(deliveredParts: 12, highestStage: 4)
        XCTAssertEqual(bossGoal.title, "S10 압착왕 코어 회수")
        XCTAssertEqual(bossGoal.current, 4)
        XCTAssertEqual(bossGoal.required, 10)
    }

    func testBossRulesDefineTimerPhasesAndGuaranteedReward() {
        XCTAssertEqual(BossEncounterRules.timeLimitTicks(milliseconds: 45_000), 900)
        XCTAssertEqual(BossEncounterRules.remainingSeconds(deadlineTick: 900, currentTick: 1), 45)
        XCTAssertEqual(BossEncounterRules.phase(hp: 71, maxHP: 100), .armored)
        XCTAssertEqual(BossEncounterRules.phase(hp: 70, maxHP: 100), .clawBroken)
        XCTAssertEqual(BossEncounterRules.phase(hp: 30, maxHP: 100), .coreExposed)
        XCTAssertEqual(BossEncounterRules.phase(hp: 0, maxHP: 100), .dismantle)
        XCTAssertEqual(BossEncounterRules.activeCutIndex(stageNumber: 10), 1)
        XCTAssertEqual(BossEncounterRules.bonusParts(baseParts: 15, cutSucceeded: true), 3)
        XCTAssertEqual(BossEncounterRules.bonusParts(baseParts: 15, cutSucceeded: false), 0)
        let reward = BossEncounterRules.firstClearReward(stageNumber: 10)
        XCTAssertEqual(reward.blueprintID, "blueprint_cutting_coil")
        XCTAssertEqual(reward.moduleID, "module_cutting_coil")
    }

    func testBossStageShowsTimerAndPendingDismantleRestores() {
        let content = ContentLoader.loadVerticalSlice(bundle: Bundle(for: Self.self))
        var activeSave = GameSave.newGame()
        activeSave.stageIndex = 9
        activeSave.prologueSeen = true
        activeSave.tutorialStep = 4
        let activeScene = CombatScene(content: content, save: activeSave)
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        activeScene.didMove(to: view)
        XCTAssertNotNil(findNode(named: "boss_timer_panel", in: activeScene))
        XCTAssertNotNil(findNode(named: "boss_timer", in: activeScene))

        var pendingSave = activeSave
        pendingSave.enemyHPs = [0]
        pendingSave.pendingBossDismantleStage = 10
        pendingSave.pendingBossBaseParts = 15
        let pendingScene = CombatScene(content: content, save: pendingSave)
        pendingScene.didMove(to: view)
        XCTAssertNotNil(findNode(named: "boss_dismantle_panel", in: pendingScene))
        XCTAssertNotNil(findNode(named: "boss_cut_0", in: pendingScene))
        XCTAssertNotNil(findNode(named: "boss_cut_1", in: pendingScene))
    }

    func testRecoveredShelterPersistsStoryStateAndSkipsPrologue() {
        var save = GameSave.newGame()
        save.shelterRepairParts = 7
        save.storyChapter = 0
        save.prologueSeen = true
        var persisted: GameSave?
        let scene = CombatScene(content: sampleContent(), save: save)
        scene.onSave = { persisted = $0 }
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        XCTAssertNil(findNode(named: "story_panel", in: scene))
        XCTAssertNotNil(findNode(named: "story_goal", in: scene))
        XCTAssertEqual(persisted?.shelterRepairParts, 7)
        XCTAssertTrue(persisted?.prologueSeen == true)
    }

    func testYardEconomyBalancesManualAutomationAndOfflineCap() {
        XCTAssertEqual(YardEconomy.manualDamage(cutterLevel: 1), 10)
        XCTAssertEqual(YardEconomy.manualReward(cutterLevel: 4), 2)
        XCTAssertEqual(
            YardEconomy.passiveIncome(pressLevel: 2, sorterLevel: 1, warehouseLevel: 1, crewLevel: 3),
            23
        )
        XCTAssertEqual(YardEconomy.upgradeCost(.sorter, currentLevel: 0), 90)
        let offline = YardEconomy.offlineIncome(rate: 7, elapsed: 12 * 60 * 60)
        XCTAssertEqual(offline.seconds, 8 * 60 * 60)
        XCTAssertEqual(offline.amount, 201_600)

        let paidOffline = YardEconomy.offlineIncome(
            rate: 7,
            elapsed: 20 * 60 * 60,
            entitlements: EntitlementSnapshot(active: [.offlineCap16Hours])
        )
        XCTAssertEqual(paidOffline.seconds, 16 * 60 * 60)
        XCTAssertEqual(paidOffline.amount, 403_200)
    }

    func testIAPCatalogMapsAllSixProductsAndGrants() throws {
        let catalog = try IAPCatalog.load(bundle: Bundle(for: Self.self))
        XCTAssertEqual(catalog.products.count, 6)
        XCTAssertEqual(Set(catalog.products.map(\.id)), Set(StoreProductID.allCases))
        XCTAssertEqual(catalog.product(.maintenanceMonthly).type, .autoRenewableSubscription)
        XCTAssertEqual(
            Set(catalog.product(.offline16Hours).grants),
            [.offlineCap16Hours]
        )
        XCTAssertEqual(catalog.speedMultiplierHardCap, Decimal(string: "1.8"))
        XCTAssertEqual(
            Set(catalog.product(.scrapFrontierSeason2026).grants),
            [.season2026ScrapFrontierPremium]
        )
    }

    func testPremiumStoreUsesLoadedLocalizedPriceAndActualPurchaseNodes() {
        var save = GameSave.newGame()
        save.prologueSeen = true
        let scene = CombatScene(content: sampleContent(), save: save, showPremiumStoreOnLaunch: true)
        scene.onStorePurchase = { _ in }
        scene.onStoreRestore = {}
        let products = StoreProductID.allCases.map {
            StoreProductDisplay(id: $0, displayName: "현지 상품 " + $0.rawValue, displayPrice: "₩12,000")
        }
        scene.updateStorefront(StorefrontSnapshot(state: .ready, entitlements: .none, products: products))
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        XCTAssertNotNil(findNode(named: "store_product_" + StoreProductID.scrapFrontierSeason2026.rawValue, in: scene))
        let purchaseName = "store_purchase_" + StoreProductID.scrapFrontierSeason2026.rawValue
        let price = findNodes(named: purchaseName, in: scene)
            .compactMap { $0 as? SKLabelNode }
            .first(where: { $0.text == "₩12,000" })
        XCTAssertNotNil(price)
        XCTAssertNotNil(findNode(named: "store_restore", in: scene))
    }

    func testPremiumStoreDoesNotCreateFakePurchaseButtonsWithoutStoreProducts() {
        var save = GameSave.newGame()
        save.prologueSeen = true
        let scene = CombatScene(content: sampleContent(), save: save, showPremiumStoreOnLaunch: true)
        scene.onStorePurchase = { _ in XCTFail("Unavailable products must not be purchasable") }
        scene.updateStorefront(.unavailable(entitlements: .none))
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        XCTAssertNil(findNode(named: "store_purchase_" + StoreProductID.offline16Hours.rawValue, in: scene))
        XCTAssertNotNil(findNode(named: "store_product_" + StoreProductID.offline16Hours.rawValue, in: scene))
    }

    func testStorefrontMessagesDistinguishPendingCancelAndFailure() {
        XCTAssertTrue(StorePurchaseState.pendingApproval(.starterCrewKit).statusKo.contains("승인 대기"))
        XCTAssertFalse(StorePurchaseState.pendingApproval(.starterCrewKit).allowsPurchase)
        XCTAssertTrue(StorePurchaseState.cancelled.statusKo.contains("취소"))
        XCTAssertTrue(StorePurchaseState.cancelled.allowsPurchase)
        XCTAssertTrue(StorePurchaseState.offlineRetry(.purchase).statusKo.contains("연결 실패"))
        XCTAssertTrue(StorePurchaseState.offlineRetry(.purchase).needsRetry)
        XCTAssertTrue(StorePurchaseState.verificationFailed.statusKo.contains("지급하지 않았습니다"))
    }

    func testOwnedRustUniformChangesProductionBoraSpriteAndPersistsSelection() {
        var save = GameSave.newGame()
        save.prologueSeen = true
        save.equippedBoraUniform = .rust
        var persisted: GameSave?
        let scene = CombatScene(
            content: sampleContent(),
            save: save,
            premiumEntitlements: EntitlementSnapshot(active: [.boraRustUniform, .boraRustAttackFX])
        )
        scene.onSave = { persisted = $0 }
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        let bora = findNode(named: "crew_bora_combat", in: scene) as? SKSpriteNode
        XCTAssertNotNil(bora?.texture, "Uniform variants must reuse the production Bora pixel texture")
        XCTAssertEqual(bora?.colorBlendFactor ?? 0, 0.52, accuracy: 0.001)
        XCTAssertEqual(persisted?.equippedBoraUniform, .rust)
    }

    func testMissingMonthlyCosmeticAssetStaysExplicitlyLocked() {
        var save = GameSave.newGame()
        save.prologueSeen = true
        let scene = CombatScene(
            content: sampleContent(),
            save: save,
            premiumEntitlements: EntitlementSnapshot(active: [.monthlyCrewCosmetic]),
            showCrewPanelOnLaunch: true
        )
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        let lock = findNode(named: "monthly_cosmetic_asset_locked", in: scene) as? SKLabelNode
        XCTAssertEqual(lock?.text, "월간 직원 외형 • 전용 픽셀 자산 준비 전 잠김")
        XCTAssertNil(findNode(named: "equip_bora_monthly", in: scene))
    }

    func testEntitlementExpiryKeepsRunningThirdWorkbenchOperationUnchanged() throws {
        let now = Date(timeIntervalSince1970: 50_000)
        var operations = IdleOperationsState.newGame(now: now)
        operations.workbenchSlots = 3
        _ = try IdleOperationsEngine.start(.research, now: now, identifier: "research", state: &operations)
        _ = try IdleOperationsEngine.start(.craft, now: now, identifier: "craft-1", state: &operations)
        _ = try IdleOperationsEngine.start(.craft, now: now, identifier: "craft-2", state: &operations)
        let completions = operations.active.map(\.completesAt)
        var save = GameSave.newGame(now: now)
        save.prologueSeen = true
        save.idleOperations = operations
        var persisted: GameSave?
        let scene = CombatScene(content: sampleContent(), save: save, premiumEntitlements: .none)
        scene.onSave = { persisted = $0 }
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        XCTAssertEqual(persisted?.idleOperations.workbenchSlots, 2)
        XCTAssertEqual(persisted?.idleOperations.active.count, 3)
        XCTAssertEqual(persisted?.idleOperations.active.map(\.completesAt), completions)
    }

    func testPurchaseLedgerIsIdempotentAndFinishesOnlyAfterPersistence() async throws {
        let store = temporaryPurchaseLedgerStore()
        let processor = PurchaseGrantProcessor(ledger: store)
        let record = purchaseRecord(id: 101, product: .offline16Hours)
        var finishCount = 0

        let first = try await processor.persistThenFinish(record) {
            XCTAssertEqual(try? store.load().records.map(\.transactionID), [101])
            finishCount += 1
        }
        let duplicate = try await processor.persistThenFinish(record) {
            XCTAssertEqual(try? store.load().records.count, 1)
            finishCount += 1
        }

        XCTAssertEqual(first, .inserted)
        XCTAssertEqual(duplicate, .unchanged)
        XCTAssertEqual(finishCount, 2)
        XCTAssertTrue(store.loadOrEmpty().entitlementSnapshot().contains(.offlineCap16Hours))
    }

    func testFailedLedgerWriteDoesNotFinishTransaction() async {
        let unwritable = PurchaseLedgerStore(
            directory: URL(fileURLWithPath: "/dev/null/purchase-ledger-test", isDirectory: true)
        )
        let processor = PurchaseGrantProcessor(ledger: unwritable)
        var didFinish = false

        do {
            try await processor.persistThenFinish(purchaseRecord(id: 102, product: .offline16Hours)) {
                didFinish = true
            }
            XCTFail("An unwritable ledger path must fail")
        } catch {
            XCTAssertFalse(didFinish)
        }
    }

    func testRefundRevokesNonConsumableWithoutDeletingAuditRecord() throws {
        let store = temporaryPurchaseLedgerStore()
        let purchase = purchaseRecord(id: 202, product: .workbenchSlot3)
        try store.record(purchase)
        var refund = purchase
        refund.revocationDate = Date(timeIntervalSince1970: 2_000)

        XCTAssertEqual(try store.record(refund), .updated)
        let snapshot = try store.load()
        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertTrue(snapshot.records[0].isRevoked)
        XCTAssertFalse(snapshot.entitlementSnapshot().contains(.workbenchSlot3))
    }

    func testSubscriptionCancellationKeepsAccessUntilExpiration() throws {
        let store = temporaryPurchaseLedgerStore()
        let now = Date(timeIntervalSince1970: 10_000)
        var subscription = purchaseRecord(id: 303, product: .maintenanceMonthly)
        subscription.expirationDate = now.addingTimeInterval(3_600)
        try store.record(subscription, now: now)

        let ledger = try store.load()
        XCTAssertTrue(ledger.entitlementSnapshot(at: now).contains(.craftSpeed110))
        XCTAssertFalse(ledger.entitlementSnapshot(at: now.addingTimeInterval(3_601)).contains(.craftSpeed110))
    }

    func testPurchaseLedgerCloudMergePreservesUniqueTransactionIDs() throws {
        let local = temporaryPurchaseLedgerStore()
        let cloud = temporaryPurchaseLedgerStore()
        try local.record(purchaseRecord(id: 401, product: .starterCrewKit))
        try cloud.record(purchaseRecord(id: 402, product: .boraRustCosmetic))

        let merged = try local.mergeCloudData(cloud.exportCloudData())
        XCTAssertEqual(merged.records.map(\.transactionID), [401, 402])
        XCTAssertTrue(merged.entitlementSnapshot().contains(.boraFounderUniform))
        XCTAssertTrue(merged.entitlementSnapshot().contains(.boraRustUniform))
    }

    func testFacilitiesShowLockedPremiumAccessWithoutPurchaseButtons() {
        var save = GameSave.newGame(now: Date())
        save.prologueSeen = true
        let scene = CombatScene(
            content: sampleContent(),
            save: save,
            premiumEntitlements: .none,
            showFacilityPanelOnLaunch: true
        )
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        let status = findNode(named: "premium_access_status", in: scene) as? SKLabelNode
        XCTAssertEqual(status?.text, "작업대3 잠김 • 16H 잠김 • 멤버십 잠김")
        XCTAssertNil(findNode(named: "buy_offline_16h", in: scene))
        XCTAssertNil(findNode(named: "buy_maintenance_monthly", in: scene))
    }

    func testFacilityPanelShowsOfflineReportAndActionableRows() {
        var save = GameSave.newGame(now: Date().addingTimeInterval(-9 * 60 * 60))
        save.pressLevel = 2
        save.sorterLevel = 1
        var persisted: GameSave?
        let scene = CombatScene(content: sampleContent(), save: save, showFacilityPanelOnLaunch: true)
        scene.onSave = { persisted = $0 }
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        XCTAssertNotNil(findNode(named: "shop_panel", in: scene))
        XCTAssertNotNil(findNode(named: "collect_yard_income", in: scene))
        XCTAssertNotNil(findNode(named: "buy_press", in: scene))
        XCTAssertNotNil(findNode(named: "buy_sorter", in: scene))
        XCTAssertNotNil(findNode(named: "buy_warehouse", in: scene))
        XCTAssertNotNil(findNode(named: "operations_open", in: scene))
        XCTAssertEqual(persisted?.yardIncomeBank, 9 * 8 * 60 * 60)
    }

    func testSaveSelectionExplainsGameBeforeCombat() {
        let scene = SaveSelectionScene(localSave: .newGame())
        let view = SKView(frame: CGRect(origin: .zero, size: SaveSelectionScene.logicalSize))
        scene.didMove(to: view)
        XCTAssertNotNil(findNode(named: "save_slot", in: scene))
        XCTAssertNotNil(findNode(named: "new_game", in: scene))
        XCTAssertNotNil(findNode(named: "cloud_backup", in: scene))
        XCTAssertNil(findNode(named: "enemy_can_bug", in: scene))
    }

    private func sampleContent() -> VerticalSliceContent {
        let data = Data(
            """
            {
              "contentVersion":"0.1.0",
              "slice":{"id":"test","regionId":"r01","stageStart":1,"stageEnd":1},
              "player":{"id":"mo","baseDamage":8,"attackIntervalMs":1200,"criticalChancePpm":50000,"criticalDamagePpm":1700000,"spriteId":"actor_mo_base"},
              "drones":[{"id":"riv0","nameKo":"리벳","role":"salvage","baseDamage":3,"attackIntervalMs":1000,"unlockStage":1,"spriteId":"drone_riv0_base"}],
              "enemies":[{"id":"can_bug","nameKo":"캔벌레","class":"normal","hpMultiplierPpm":1000000,"weakness":"impact","spriteId":"enemy_can_bug"}],
              "stages":[{"number":1,"baseHp":50,"baseReward":10,"wave":["can_bug"],"rewardMultiplierPpm":1000000}]
            }
            """.utf8
        )
        return try! JSONDecoder().decode(VerticalSliceContent.self, from: data)
    }

    private func multiEnemyContent() -> VerticalSliceContent {
        let data = Data(
            """
            {
              "contentVersion":"0.1.0",
              "slice":{"id":"test","regionId":"r01","stageStart":1,"stageEnd":1},
              "player":{"id":"mo","baseDamage":8,"attackIntervalMs":1200,"criticalChancePpm":50000,"criticalDamagePpm":1700000,"spriteId":"actor_mo_base"},
              "drones":[{"id":"riv0","nameKo":"리벳","role":"salvage","baseDamage":3,"attackIntervalMs":1000,"unlockStage":1,"spriteId":"drone_riv0_base"}],
              "enemies":[
                {"id":"can_bug","nameKo":"캔벌레","class":"normal","hpMultiplierPpm":1000000,"weakness":"impact","spriteId":"enemy_can_bug"},
                {"id":"umbrella_crab","nameKo":"우산게","class":"normal","hpMultiplierPpm":1150000,"weakness":"cut","spriteId":"enemy_umbrella_crab"},
                {"id":"fridge_boar","nameKo":"냉장고멧돼지","class":"normal","hpMultiplierPpm":1350000,"weakness":"electric","spriteId":"enemy_fridge_boar"}
              ],
              "stages":[{"number":1,"baseHp":50,"baseReward":10,"wave":["can_bug","umbrella_crab","fridge_boar"],"rewardMultiplierPpm":1000000}]
            }
            """.utf8
        )
        return try! JSONDecoder().decode(VerticalSliceContent.self, from: data)
    }

    private func temporarySaveStore() -> GameSaveStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return GameSaveStore(directory: directory)
    }

    private func temporaryPurchaseLedgerStore() -> PurchaseLedgerStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return PurchaseLedgerStore(directory: directory)
    }

    private func purchaseRecord(id: UInt64, product: StoreProductID) -> VerifiedPurchaseRecord {
        VerifiedPurchaseRecord(
            transactionID: id,
            originalTransactionID: id,
            productID: product,
            purchaseDate: Date(timeIntervalSince1970: 1_000),
            expirationDate: nil,
            revocationDate: nil
        )
    }

    private func findButtons(in view: UIView) -> [UIButton] {
        let own = view as? UIButton
        return (own.map { [$0] } ?? []) + view.subviews.flatMap(findButtons)
    }

    private func containsShapeNode(_ node: SKNode) -> Bool {
        node is SKShapeNode || node.children.contains(where: containsShapeNode)
    }

    private func findNode(named name: String, in node: SKNode) -> SKNode? {
        if node.name == name { return node }
        return node.children.lazy.compactMap { self.findNode(named: name, in: $0) }.first
    }

    private func findNodes(named name: String, in node: SKNode) -> [SKNode] {
        let own = node.name == name ? [node] : []
        return own + node.children.flatMap { findNodes(named: name, in: $0) }
    }

    private func assertIntegralPositions(_ node: SKNode, file: StaticString = #filePath, line: UInt = #line) {
        for child in node.children {
            XCTAssertEqual(child.position.x, child.position.x.rounded(), accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(child.position.y, child.position.y.rounded(), accuracy: 0.0001, file: file, line: line)
            assertIntegralPositions(child, file: file, line: line)
        }
    }
}

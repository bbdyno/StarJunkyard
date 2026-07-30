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
        XCTAssertEqual(content.contentVersion, "0.1.0")
        XCTAssertEqual(content.stages.map(\.number), Array(1...20))
        XCTAssertEqual(content.enemies.count, 6)
        XCTAssertEqual(content.enemies.last(where: { $0.id == "fridge_boar" })?.nameKo, "냉장고멧돼지")
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
        XCTAssertNotNil(findNode(named: "tutorial_panel", in: scene))
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
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.enemyHPs, [41])
        XCTAssertEqual(migrated.crewLevel, 1)
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

    private func assertIntegralPositions(_ node: SKNode, file: StaticString = #filePath, line: UInt = #line) {
        for child in node.children {
            XCTAssertEqual(child.position.x, child.position.x.rounded(), accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(child.position.y, child.position.y.rounded(), accuracy: 0.0001, file: file, line: line)
            assertIntegralPositions(child, file: file, line: line)
        }
    }
}

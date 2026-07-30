import SpriteKit
import XCTest
@testable import StarJunkyard

final class WorldContentTests: XCTestCase {
    func testWorldContractContainsSixRegionsAndRequiredEnemyCounts() throws {
        let world = try loadWorld()
        XCTAssertEqual(world.contentVersion, "0.3.0")
        XCTAssertEqual(world.regions?.count, 6)
        XCTAssertEqual(world.stages.map(\.number), Array(1...360))
        XCTAssertEqual(world.enemies.filter { $0.enemyClass == "normal" }.count, 24)
        XCTAssertEqual(world.enemies.filter { $0.enemyClass == "elite" }.count, 12)
        XCTAssertEqual(world.enemies.filter { $0.enemyClass == "boss" }.count, 12)

        for region in try XCTUnwrap(world.regions) {
            XCTAssertEqual(region.enemyIds.count, 4)
            XCTAssertEqual(region.eliteIds.count, 2)
            XCTAssertEqual(
                world.enemies.filter { $0.regionId == region.id }.count,
                8,
                "Each region owns four normal, two elite, and two boss entities"
            )
        }
    }

    func testOnlyCompletedRegionsExposeRuntimeSpriteIDs() throws {
        let world = try loadWorld()
        for enemy in world.enemies {
            if enemy.regionId == "r01" || enemy.regionId == "r02" {
                XCTAssertEqual(enemy.assetStatus, "production_ready")
                XCTAssertFalse(enemy.spriteId.isEmpty)
            } else {
                XCTAssertEqual(enemy.assetStatus, "contract_only")
                XCTAssertTrue(enemy.spriteId.isEmpty)
            }
        }
        let production = ContentLoader.loadVerticalSlice(bundle: Bundle(for: Self.self))
        XCTAssertEqual(production.stages.last?.number, 120)
        XCTAssertEqual(Set(production.enemies.compactMap(\.regionId)), ["r01", "r02"])
    }

    func testR1DepartureConnectsToR2ArrivalAndBaseStory() throws {
        let world = try loadWorld()
        let transition = try XCTUnwrap(
            RegionProgression.transition(from: 60, to: 61, regions: world.regions ?? [])
        )
        XCTAssertEqual(transition.fromRegionID, "r01")
        XCTAssertEqual(transition.toRegionID, "r02")
        XCTAssertEqual(transition.title, "R2 • 폐쇄된 메가몰")
        XCTAssertTrue(transition.departureStory.contains("출항로"))
        XCTAssertTrue(transition.arrivalStory.contains("메가몰"))
        XCTAssertTrue(transition.baseForm.contains("재활용 공장"))
    }

    @MainActor
    func testR2ProductionSceneUsesMallBackgroundAndRecognizableEnemySprite() throws {
        let content = ContentLoader.loadVerticalSlice(bundle: Bundle(for: Self.self))
        var save = GameSave.newGame()
        save.stageIndex = 60
        save.highestStage = 61
        save.prologueSeen = true
        save.tutorialStep = 4
        let scene = CombatScene(content: content, save: save)
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        let background = try XCTUnwrap(findNode(named: "region_background", in: scene) as? SKSpriteNode)
        XCTAssertEqual(background.userData?["spriteId"] as? String, "background_r02_closed_megamall")
        XCTAssertNotNil(findNode(named: "enemy_mannequin_octopus", in: scene))
        let baseTitle = try XCTUnwrap(findNode(named: "base_region_title", in: scene) as? SKLabelNode)
        XCTAssertTrue(baseTitle.text?.contains("재활용 공장") == true)
        XCTAssertNotNil(findNode(named: "facility_conveyor", in: scene))
        XCTAssertNotNil(findNode(named: "facility_compactor", in: scene))
        XCTAssertNotNil(findNode(named: "facility_furnace", in: scene))
        XCTAssertNotNil(findNode(named: "facility_beacon", in: scene))
        XCTAssertEqual(findNode(named: "shelter_reactor_core", in: scene)?.isHidden, true)
    }

    private func loadWorld() throws -> VerticalSliceContent {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "world_r1_r6", withExtension: "json"))
        return try JSONDecoder().decode(VerticalSliceContent.self, from: Data(contentsOf: url))
    }

    @MainActor
    private func findNode(named name: String, in node: SKNode) -> SKNode? {
        if node.name == name { return node }
        return node.children.lazy.compactMap { self.findNode(named: name, in: $0) }.first
    }
}

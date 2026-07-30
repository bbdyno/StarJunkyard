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

    func testAllRegionsExposeRuntimeSpriteIDs() throws {
        let world = try loadWorld()
        for enemy in world.enemies {
            XCTAssertEqual(enemy.assetStatus, "production_ready")
            XCTAssertFalse(enemy.spriteId.isEmpty)
        }
        let production = ContentLoader.loadVerticalSlice(bundle: Bundle(for: Self.self))
        XCTAssertEqual(production.stages.last?.number, 360)
        XCTAssertEqual(Set(production.enemies.compactMap(\.regionId)), Set(["r01", "r02", "r03", "r04", "r05", "r06"]))
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

    @MainActor
    func testR3ThroughR6ScenesUseUniqueBackgroundsAndThreeEnemySprites() throws {
        let content = ContentLoader.loadVerticalSlice(bundle: Bundle(for: Self.self))
        let entries: [(index: Int, background: String, facilities: [String])] = [
            (120, "background_r03_last_train_subway", ["facility_rail", "facility_train", "facility_signal", "facility_power"]),
            (180, "background_r04_sunken_ship_graveyard", ["facility_salvage", "facility_cutter", "facility_hull", "facility_lighthouse"]),
            (240, "background_r05_orbital_debris_belt", ["facility_docking", "facility_panel", "facility_oxygen", "facility_orbit"]),
            (300, "background_r06_lunar_whiteout_plant", ["facility_memory", "facility_time", "facility_star", "facility_protocol"]),
        ]
        for entry in entries {
            var save = GameSave.newGame()
            save.stageIndex = entry.index
            save.highestStage = entry.index + 1
            save.prologueSeen = true
            save.tutorialStep = 4
            let scene = CombatScene(content: content, save: save)
            let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
            scene.didMove(to: view)

            let background = try XCTUnwrap(findNode(named: "region_background", in: scene) as? SKSpriteNode)
            XCTAssertEqual(background.userData?["spriteId"] as? String, entry.background)
            let stage = content.stages[entry.index]
            let spriteIDs = stage.wave.prefix(3).compactMap { enemyID in
                content.enemies.first(where: { $0.id == enemyID })?.spriteId
            }
            XCTAssertEqual(Set(spriteIDs).count, 3)
            for spriteID in spriteIDs {
                XCTAssertNotNil(findNode(named: spriteID, in: scene), "\(spriteID) must render without fallback")
            }
            XCTAssertNotNil(findNode(named: "crew_bora_combat", in: scene))
            XCTAssertNotNil(findNode(named: "drone_riv0_base", in: scene))
            XCTAssertNotNil(findNode(named: "drone_spk2_base", in: scene))
            for facility in entry.facilities {
                XCTAssertNotNil(findNode(named: facility, in: scene), "\(facility) must render in its regional base")
            }
            XCTAssertEqual(findNode(named: "shelter_reactor_core", in: scene)?.isHidden, true)
        }
    }

    @MainActor
    func testRegionalFacilityCatalogUsesTwentyUniquePixelSilhouettes() {
        let regionIDs = ["r02", "r03", "r04", "r05", "r06"]
        let facilities = regionIDs.flatMap { regionID -> [RegionalFacilitySpec] in
            let regional = RegionalFacilityCatalog.facilities(for: regionID)
            XCTAssertEqual(regional.count, 4, "\(regionID) needs four recognizable facilities")
            return regional
        }
        XCTAssertEqual(Set(facilities.map(\.name)).count, 20)
        XCTAssertEqual(Set(facilities.map(\.blockSignature)).count, 20)
        for facility in facilities {
            XCTAssertFalse(facility.blocks.isEmpty)
            for block in facility.blocks {
                XCTAssertGreaterThanOrEqual(block.x, 0)
                XCTAssertGreaterThanOrEqual(block.y, 0)
                XCTAssertLessThanOrEqual(block.x + block.width, 20)
                XCTAssertLessThanOrEqual(block.y + block.height, 20)
            }
        }
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

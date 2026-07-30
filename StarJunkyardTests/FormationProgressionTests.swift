import SpriteKit
import XCTest
@testable import StarJunkyard

final class FormationProgressionTests: XCTestCase {
    private let drones = [
        VerticalSliceContent.Drone(
            id: "riv0",
            nameKo: "리벳",
            role: "salvage",
            baseDamage: 3,
            attackIntervalMs: 1_000,
            unlockStage: 3,
            spriteId: "drone_riv0_base"
        ),
        VerticalSliceContent.Drone(
            id: "spk2",
            nameKo: "스파크",
            role: "chain_electric",
            baseDamage: 5,
            attackIntervalMs: 800,
            unlockStage: 18,
            spriteId: "drone_spk2_base"
        )
    ]

    func testFreeUnlockLadderCreatesARealFormationWithoutDuplicates() {
        let stage3 = reconcile(stage: 3)
        XCTAssertEqual(stage3.unlockedDroneIDs, ["riv0"])
        XCTAssertEqual(stage3.equippedDroneIDs, ["riv0"])
        XCTAssertEqual(stage3.newlyUnlockedDroneIDs, ["riv0"])

        let stage5 = reconcile(
            stage: 5,
            drones: stage3.unlockedDroneIDs,
            formation: stage3.equippedDroneIDs
        )
        XCTAssertEqual(stage5.unlockedModuleIDs, ["module_impact_hammer"])
        XCTAssertEqual(stage5.equippedModuleIDs, ["module_impact_hammer"])

        let bossLocked = reconcile(
            stage: 10,
            drones: stage5.unlockedDroneIDs,
            formation: stage5.equippedDroneIDs,
            modules: stage5.unlockedModuleIDs,
            equippedModules: stage5.equippedModuleIDs
        )
        XCTAssertFalse(bossLocked.unlockedModuleIDs.contains("module_cutting_coil"))

        let bossCleared = reconcile(
            stage: 10,
            bosses: [10],
            drones: bossLocked.unlockedDroneIDs,
            formation: bossLocked.equippedDroneIDs,
            modules: bossLocked.unlockedModuleIDs,
            equippedModules: bossLocked.equippedModuleIDs
        )
        XCTAssertEqual(bossCleared.newlyUnlockedModuleIDs, ["module_cutting_coil"])

        let stage18 = reconcile(
            stage: 18,
            bosses: [10],
            drones: bossCleared.unlockedDroneIDs,
            formation: bossCleared.equippedDroneIDs,
            modules: bossCleared.unlockedModuleIDs,
            equippedModules: bossCleared.equippedModuleIDs
        )
        XCTAssertEqual(Set(stage18.unlockedDroneIDs), ["riv0", "spk2"])
        XCTAssertEqual(
            Set(stage18.unlockedModuleIDs),
            ["module_impact_hammer", "module_cutting_coil", "module_magnetic_net"]
        )
        XCTAssertEqual(stage18.equippedDroneIDs, ["riv0"], "S18 has one meaningful choice slot")

        let selectedSpark = FormationProgression.selectingDrone(
            "spk2",
            formation: stage18.equippedDroneIDs,
            unlockedDroneIDs: Set(stage18.unlockedDroneIDs),
            slotCount: 1
        )
        XCTAssertEqual(selectedSpark, ["spk2"])

        let stage30 = reconcile(
            stage: 30,
            bosses: [10],
            drones: stage18.unlockedDroneIDs,
            formation: selectedSpark,
            modules: stage18.unlockedModuleIDs,
            equippedModules: stage18.equippedModuleIDs
        )
        XCTAssertEqual(stage30.equippedDroneIDs, ["spk2", "riv0"])
        XCTAssertEqual(FormationProgression.canonicalIDs(stage30.unlockedDroneIDs + stage30.unlockedDroneIDs), stage30.unlockedDroneIDs)
    }

    func testReconcileAndBossRewardsAreIdempotent() {
        let first = reconcile(
            stage: 18,
            bosses: [10],
            drones: ["riv0", "riv0"],
            formation: ["riv0", "riv0"],
            modules: ["module_cutting_coil", "module_cutting_coil"],
            equippedModules: ["module_cutting_coil", "module_cutting_coil"]
        )
        let second = reconcile(
            stage: 18,
            bosses: [10],
            drones: first.unlockedDroneIDs,
            formation: first.equippedDroneIDs,
            modules: first.unlockedModuleIDs,
            equippedModules: first.equippedModuleIDs
        )
        XCTAssertTrue(second.newlyUnlockedDroneIDs.isEmpty)
        XCTAssertTrue(second.newlyUnlockedModuleIDs.isEmpty)
        XCTAssertEqual(second.unlockedDroneIDs.count, Set(second.unlockedDroneIDs).count)
        XCTAssertEqual(second.unlockedModuleIDs.count, Set(second.unlockedModuleIDs).count)
    }

    func testCutImpactAndMagneticAffinitiesApplyEnemyWeaknessBonus() {
        let impact = FormationProgression.resolveDamage(base: 100, affinity: .impact, enemyWeakness: "impact")
        XCTAssertEqual(impact.damage, 150)
        XCTAssertTrue(impact.weaknessApplied)

        let cut = FormationProgression.resolveDamage(base: 100, affinity: .cut, enemyWeakness: "cut", powerPPM: 1_100_000)
        XCTAssertEqual(cut.damage, 165)
        XCTAssertEqual(cut.multiplierPPM, 1_650_000)

        let magnetic = FormationProgression.resolveDamage(base: 100, affinity: .magnetic, enemyWeakness: "electric")
        XCTAssertEqual(magnetic.damage, 150)
        XCTAssertTrue(magnetic.weaknessApplied)

        let mismatch = FormationProgression.resolveDamage(base: 100, affinity: .cut, enemyWeakness: "impact")
        XCTAssertEqual(mismatch.damage, 100)
        XCTAssertFalse(mismatch.weaknessApplied)
    }

    func testCrewRoleAndMasteryChangeSavedCombatEffect() {
        XCTAssertEqual(FormationProgression.crewDamage(masteryLevel: 3, role: .breaker), 18)
        XCTAssertEqual(FormationProgression.crewDamage(masteryLevel: 3, role: .cutter), 16)
        XCTAssertEqual(FormationProgression.crewDamage(masteryLevel: 3, role: .collector), 15)
        XCTAssertEqual(FormationProgression.nextRole(after: .breaker), .cutter)
        XCTAssertEqual(FormationProgression.nextRole(after: .collector), .breaker)
    }

    func testSchemaFiveMigratesFormationAndCanonicalizesDuplicateRewards() throws {
        let payload = Data(
            """
            {"schemaVersion":5,"revision":9,"updatedAt":100000,"stageIndex":9,"waveIndex":0,"enemyHPs":[25],"credits":44,"parts":6,"cutterLevel":2,"droneLevel":2,"magnetLevel":1,"crewLevel":4,"pressLevel":1,"sorterLevel":0,"warehouseLevel":0,"yardIncomeBank":0,"manualTapCount":0,"discoveredEnemyIDs":[],"storyChapter":1,"shelterRepairParts":12,"prologueSeen":true,"defeatedBossStages":[10,10],"unlockedBlueprintIDs":[],"unlockedModuleIDs":["module_cutting_coil","module_cutting_coil"],"storyLogIDs":[],"bossFailureCounts":{},"pendingBossBaseParts":0,"tutorialStep":4,"combatTick":120,"highestStage":10,"cloudBackupEnabled":true}
            """.utf8
        )
        let store = temporarySaveStore()
        let migrated = try store.decodeCloudData(payload)
        XCTAssertEqual(migrated.schemaVersion, GameSave.currentSchemaVersion)
        XCTAssertEqual(migrated.defeatedBossStages, [10])
        XCTAssertEqual(migrated.unlockedModuleIDs, ["module_cutting_coil"])
        XCTAssertEqual(migrated.crewRoleAssignments["bora"], CrewRole.breaker.rawValue)
        XCTAssertEqual(migrated.crewMasteryLevels["bora"], 4)
        XCTAssertTrue(migrated.unlockedDroneIDs.isEmpty)
        XCTAssertTrue(migrated.equippedDroneIDs.isEmpty)
    }

    @MainActor
    func testFacilityUIExplainsNextFreeUnlockAndScenePersistsFormation() throws {
        let content = ContentLoader.loadVerticalSlice(bundle: Bundle(for: Self.self))
        var save = GameSave.newGame()
        save.highestStage = 18
        save.stageIndex = 17
        save.prologueSeen = true
        save.tutorialStep = 4
        var persisted: GameSave?
        let scene = CombatScene(content: content, save: save, showFacilityPanelOnLaunch: true)
        scene.onSave = { persisted = $0 }
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        XCTAssertNotNil(findNode(named: "formation_next_unlock", in: scene))
        XCTAssertEqual(Set(try XCTUnwrap(persisted).unlockedDroneIDs), ["riv0", "spk2"])
        XCTAssertEqual(persisted?.equippedDroneIDs, ["riv0"])
        XCTAssertEqual(Set(persisted?.unlockedModuleIDs ?? []), ["module_impact_hammer", "module_magnetic_net"])
        XCTAssertNotNil(findNode(named: "drone_riv0_base", in: scene))
        XCTAssertNil(findNode(named: "drone_spk2_base", in: scene))
    }

    private func reconcile(
        stage: Int,
        bosses: Set<Int> = [],
        drones unlockedDrones: [String] = [],
        formation: [String] = [],
        modules: [String] = [],
        equippedModules: [String] = []
    ) -> FormationProgression.ReconcileResult {
        FormationProgression.reconcile(
            highestStage: stage,
            defeatedBossStages: bosses,
            drones: drones,
            unlockedDroneIDs: unlockedDrones,
            equippedDroneIDs: formation,
            unlockedModuleIDs: modules,
            equippedModuleIDs: equippedModules
        )
    }

    private func temporarySaveStore() -> GameSaveStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return GameSaveStore(directory: directory)
    }

    @MainActor
    private func findNode(named name: String, in node: SKNode) -> SKNode? {
        if node.name == name { return node }
        return node.children.lazy.compactMap { self.findNode(named: name, in: $0) }.first
    }
}

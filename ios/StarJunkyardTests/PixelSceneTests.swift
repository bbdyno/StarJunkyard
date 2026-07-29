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
        XCTAssertEqual(content.enemies.count, 5)
    }

    func testRootViewIsOneGameCanvasWithoutUIKitButtons() {
        let controller = GameViewController(content: sampleContent())
        controller.loadViewIfNeeded()
        XCTAssertTrue(controller.view is SKView)
        XCTAssertTrue(controller.view.subviews.isEmpty)
        XCTAssertTrue(findButtons(in: controller.view).isEmpty)
    }

    func testSceneUsesPortraitLogicalCanvasAndPixelNodes() {
        let scene = CombatScene(content: sampleContent())
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        scene.didMove(to: view)

        XCTAssertEqual(scene.size, CGSize(width: 360, height: 800))
        XCTAssertFalse(scene.children.isEmpty)
        XCTAssertFalse(containsShapeNode(scene), "Vector SKShapeNode is forbidden in the game canvas")
        assertIntegralPositions(scene)
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

    private func findButtons(in view: UIView) -> [UIButton] {
        let own = view as? UIButton
        return (own.map { [$0] } ?? []) + view.subviews.flatMap(findButtons)
    }

    private func containsShapeNode(_ node: SKNode) -> Bool {
        node is SKShapeNode || node.children.contains(where: containsShapeNode)
    }

    private func assertIntegralPositions(_ node: SKNode, file: StaticString = #filePath, line: UInt = #line) {
        for child in node.children {
            XCTAssertEqual(child.position.x, child.position.x.rounded(), accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(child.position.y, child.position.y.rounded(), accuracy: 0.0001, file: file, line: line)
            assertIntegralPositions(child, file: file, line: line)
        }
    }
}

import SpriteKit
import XCTest
@testable import StarJunkyard

@MainActor
final class PixelSettingsAccessibilityTests: XCTestCase {
    func testKoreanPixelSettingsRowsAreReadableAndAtLeastFortyFourPoints() {
        let fixture = makeFixture(locale: Locale(identifier: "ko"))
        fixture.scene.didMove(to: fixture.view)

        XCTAssertEqual(label(named: "settings_title", in: fixture.scene)?.text, "설정")
        XCTAssertEqual(PixelSettingsToggle.allCases.count, 7)
        for toggle in PixelSettingsToggle.allCases {
            let name = "setting_toggle_" + toggle.rawValue
            let hitArea = nodes(named: name, in: fixture.scene)
                .compactMap { $0 as? SKSpriteNode }
                .first { $0.size == PixelSettingsScene.rowHitSize }
            XCTAssertNotNil(hitArea, "Missing hit target for \(toggle.rawValue)")
            XCTAssertGreaterThanOrEqual(hitArea?.size.width ?? 0, 44)
            XCTAssertGreaterThanOrEqual(hitArea?.size.height ?? 0, 44)
        }
        XCTAssertFalse(containsShapeNode(fixture.scene))
        XCTAssertTrue(fixture.scene.accessibilitySummary.contains("배경 음악 켬"))
        XCTAssertTrue(fixture.scene.accessibilitySummary.contains("플레이 데이터 공유 끔"))
    }

    func testEnglishSettingsAndVoiceOverSummaryUseEnglishCatalog() {
        let fixture = makeFixture(locale: Locale(identifier: "en"))
        fixture.scene.didMove(to: fixture.view)

        XCTAssertEqual(label(named: "settings_title", in: fixture.scene)?.text, "Settings")
        XCTAssertTrue(fixture.scene.accessibilitySummary.contains("Music On"))
        XCTAssertTrue(fixture.scene.accessibilitySummary.contains("Share Play Data Off"))
        XCTAssertTrue(allLabelTexts(in: fixture.scene).contains("Single-Tap Actions"))
    }

    func testEveryTogglePersistsAndConsentRecordsAfterOptIn() {
        let fixture = makeFixture(locale: Locale(identifier: "ko"))
        var changedSettings: [GameSettings] = []
        var analytics: [GameAnalyticsEvent] = []
        fixture.scene.onSettingsChanged = { changedSettings.append($0) }
        fixture.scene.onAnalyticsEvent = { analytics.append($0) }
        fixture.scene.didMove(to: fixture.view)

        for toggle in PixelSettingsToggle.allCases where toggle != .analyticsConsent {
            fixture.scene.toggleSetting(toggle)
        }
        fixture.scene.toggleSetting(.analyticsConsent)

        let stored = fixture.settingsStore.load()
        XCTAssertFalse(stored.musicEnabled)
        XCTAssertFalse(stored.soundEffectsEnabled)
        XCTAssertFalse(stored.hapticsEnabled)
        XCTAssertTrue(stored.reduceMotion)
        XCTAssertTrue(stored.reduceScreenShake)
        XCTAssertTrue(stored.singleTapActions)
        XCTAssertEqual(fixture.consentStore.load(), .granted)
        XCTAssertEqual(changedSettings.count, 6)
        XCTAssertEqual(analytics.count, 7)
        XCTAssertEqual(
            analytics.last,
            .settingChanged(identifier: PixelSettingsToggle.analyticsConsent.rawValue, enabled: true)
        )
    }

    func testLegacyPayloadMigratesIntoVisibleDefaultRows() {
        let fixture = makeFixture(locale: Locale(identifier: "ko"))
        fixture.defaults.set(
            Data(#"{"musicEnabled":false,"soundEffectsEnabled":false}"#.utf8),
            forKey: GameSettingsStore.storageKey
        )
        let migrated = PixelSettingsScene(
            settingsStore: fixture.settingsStore,
            consentStore: fixture.consentStore,
            locale: Locale(identifier: "ko"),
            bundle: Bundle(for: GameViewController.self)
        )
        migrated.didMove(to: fixture.view)

        XCTAssertEqual(migrated.isEnabled(.music), false)
        XCTAssertEqual(migrated.isEnabled(.soundEffects), false)
        XCTAssertEqual(migrated.isEnabled(.haptics), true)
        XCTAssertEqual(migrated.isEnabled(.singleTapActions), false)
        XCTAssertEqual(label(named: "setting_value_music", in: migrated)?.text, "○ 끔")
        XCTAssertEqual(label(named: "setting_value_haptics", in: migrated)?.text, "● 켬")
        XCTAssertEqual(fixture.settingsStore.load().schemaVersion, GameSettings.currentSchemaVersion)
    }

    func testIPadAddsReadableSideRailsWhileKeepingCentralSettingsLane() {
        let fixture = makeFixture(
            locale: Locale(identifier: "ko"),
            size: CGSize(width: 1_032, height: 1_376)
        )
        fixture.scene.didMove(to: fixture.view)
        let viewport = PixelViewport(
            viewSize: fixture.view.bounds.size,
            safeAreaInsets: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
            nativeScale: 2
        )
        fixture.scene.applyViewport(viewport)

        XCTAssertTrue(viewport.usesTabletRails)
        XCTAssertNotNil(findNode(named: "settings_audio_rail", in: fixture.scene))
        XCTAssertNotNil(findNode(named: "settings_access_rail", in: fixture.scene))
        XCTAssertEqual(viewport.laneFrame.size, PixelSettingsScene.logicalSize)
    }

    func testMotionAndFeedbackPoliciesRespectIndependentToggles() {
        var settings = GameSettings.default
        settings.reduceMotion = true
        settings.reduceScreenShake = true
        settings.soundEffectsEnabled = false
        settings.hapticsEnabled = true

        XCTAssertFalse(GameMotionPolicy.allowsDecorativeMotion(settings: settings))
        XCTAssertFalse(GameMotionPolicy.allowsScreenShake(settings: settings))
        XCTAssertEqual(GameMotionPolicy.transitionDuration(0.2, settings: settings), 0)
        for event in GameFeedbackEvent.allTestEvents {
            XCTAssertFalse(GameFeedbackPolicy.allowsSound(for: event, settings: settings))
            XCTAssertTrue(GameFeedbackPolicy.allowsHaptic(for: event, settings: settings))
        }
    }

    func testCombatExposesSettingsEntryAndVoiceOverPrimaryAction() {
        var save = GameSave.newGame()
        save.prologueSeen = true
        save.tutorialStep = 4
        var settings = GameSettings.default
        settings.singleTapActions = true
        let scene = CombatScene(content: sampleContent(), save: save, settings: settings)
        let view = SKView(frame: CGRect(origin: .zero, size: CombatScene.logicalSize))
        var feedback: [GameFeedbackEvent] = []
        scene.onFeedback = { feedback.append($0) }
        scene.didMove(to: view)

        XCTAssertNotNil(findNode(named: "settings_menu", in: scene))
        XCTAssertTrue(scene.performPrimaryAccessibilityAction())
        XCTAssertEqual(feedback.first, .manualSalvage)
    }

    private struct Fixture {
        let defaults: UserDefaults
        let suiteName: String
        let settingsStore: GameSettingsStore
        let consentStore: AnalyticsConsentStore
        let scene: PixelSettingsScene
        let view: SKView
    }

    private func makeFixture(locale: Locale, size: CGSize = PixelSettingsScene.logicalSize) -> Fixture {
        let suiteName = "PixelSettingsAccessibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = GameSettingsStore(defaults: defaults)
        let consentStore = AnalyticsConsentStore(defaults: defaults)
        let scene = PixelSettingsScene(
            settingsStore: settingsStore,
            consentStore: consentStore,
            locale: locale,
            bundle: Bundle(for: GameViewController.self)
        )
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        return Fixture(
            defaults: defaults,
            suiteName: suiteName,
            settingsStore: settingsStore,
            consentStore: consentStore,
            scene: scene,
            view: view
        )
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

    private func findNode(named name: String, in node: SKNode) -> SKNode? {
        if node.name == name { return node }
        return node.children.lazy.compactMap { self.findNode(named: name, in: $0) }.first
    }

    private func nodes(named name: String, in node: SKNode) -> [SKNode] {
        (node.name == name ? [node] : []) + node.children.flatMap { self.nodes(named: name, in: $0) }
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

private extension GameFeedbackEvent {
    static let allTestEvents: [GameFeedbackEvent] = [
        .settingChanged,
        .manualSalvage,
        .enemyDismantled,
        .recoveryMilestone,
        .bossPhaseBreak,
        .bossDismantled
    ]
}

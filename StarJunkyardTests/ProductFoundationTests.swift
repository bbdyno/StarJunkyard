import XCTest
@testable import StarJunkyard

final class ProductFoundationTests: XCTestCase {
    func testKoreanAndEnglishCatalogsContainEveryContractKey() {
        let bundle = Bundle(for: GameViewController.self)
        for key in GameTextKey.allCases {
            let korean = GameText.localized(key, locale: Locale(identifier: "ko"), bundle: bundle)
            let english = GameText.localized(key, locale: Locale(identifier: "en"), bundle: bundle)
            XCTAssertNotEqual(korean, key.rawValue, "Missing Korean key: \(key.rawValue)")
            XCTAssertNotEqual(english, key.rawValue, "Missing English key: \(key.rawValue)")
            XCTAssertFalse(korean.isEmpty)
            XCTAssertFalse(english.isEmpty)
        }
    }

    func testLocalizedNumberFormattingUsesStablePositionalArguments() {
        let bundle = Bundle(for: GameViewController.self)
        XCTAssertEqual(
            GameText.format(
                .formatStageProgress,
                locale: Locale(identifier: "ko"),
                bundle: bundle,
                Int64(7),
                Int64(20)
            ),
            "스테이지 7 / 20"
        )
        XCTAssertEqual(
            GameText.format(
                .formatCredits,
                locale: Locale(identifier: "en"),
                bundle: bundle,
                Int64(1_250)
            ),
            "1,250 Scrap"
        )
    }

    func testSettingsRoundTripAndOlderPayloadDefaults() throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = GameSettingsStore(defaults: defaults)

        var settings = GameSettings.default
        settings.musicEnabled = false
        settings.reduceMotion = true
        settings.reduceScreenShake = true
        settings.singleTapActions = true
        XCTAssertTrue(store.save(settings))
        XCTAssertEqual(store.load(), settings)

        defaults.set(
            Data(#"{"musicEnabled":false,"soundEffectsEnabled":false}"#.utf8),
            forKey: GameSettingsStore.storageKey
        )
        let migrated = store.load()
        XCTAssertEqual(migrated.schemaVersion, GameSettings.currentSchemaVersion)
        XCTAssertFalse(migrated.musicEnabled)
        XCTAssertFalse(migrated.soundEffectsEnabled)
        XCTAssertTrue(migrated.hapticsEnabled)
        XCTAssertFalse(migrated.reduceMotion)
        XCTAssertFalse(migrated.reduceScreenShake)
        XCTAssertFalse(migrated.singleTapActions)
    }

    func testAnalyticsConsentDefaultsToNoOpAndNeverBlocksGameFlow() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let consent = AnalyticsConsentStore(defaults: defaults)
        let recorder = LocalGameAnalyticsRecorder()
        let analytics = ConsentGatedGameAnalytics(consentStore: consent, destination: recorder)

        analytics.record(.appLaunched)
        XCTAssertTrue(recorder.snapshot().isEmpty)

        consent.save(.denied)
        analytics.record(.combatStarted(stage: 3))
        XCTAssertTrue(recorder.snapshot().isEmpty)

        consent.save(.granted)
        analytics.record(.combatStarted(stage: 3))
        XCTAssertEqual(recorder.snapshot(), [.combatStarted(stage: 3)])
    }

    func testLocalAnalyticsRecorderIsMemoryBounded() {
        let recorder = LocalGameAnalyticsRecorder(capacity: 2)
        recorder.record(.combatStarted(stage: 1))
        recorder.record(.combatStarted(stage: 2))
        recorder.record(.combatStarted(stage: 3))
        XCTAssertEqual(
            recorder.snapshot(),
            [.combatStarted(stage: 2), .combatStarted(stage: 3)]
        )
    }

    func testFeedbackPolicyRespectsIndependentSoundAndHapticSettings() {
        var settings = GameSettings.default
        settings.soundEffectsEnabled = false
        settings.hapticsEnabled = true
        XCTAssertFalse(GameFeedbackPolicy.allowsSound(for: .enemyDismantled, settings: settings))
        XCTAssertTrue(GameFeedbackPolicy.allowsHaptic(for: .enemyDismantled, settings: settings))

        settings.soundEffectsEnabled = true
        settings.hapticsEnabled = false
        XCTAssertTrue(GameFeedbackPolicy.allowsSound(for: .recoveryMilestone, settings: settings))
        XCTAssertFalse(GameFeedbackPolicy.allowsHaptic(for: .recoveryMilestone, settings: settings))
    }

    @MainActor
    func testControllerRecordsPrivacySafeLaunchEventWhenRecorderIsExplicitlyInjected() {
        let recorder = LocalGameAnalyticsRecorder()
        let controller = GameViewController(
            content: sampleContent(),
            saveStore: temporarySaveStore(),
            analytics: recorder
        )
        controller.loadViewIfNeeded()
        XCTAssertEqual(recorder.snapshot(), [.appLaunched])
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "ProductFoundationTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func temporarySaveStore() -> GameSaveStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return GameSaveStore(directory: directory)
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
}

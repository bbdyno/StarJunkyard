import Foundation

enum GameTextKey: String, CaseIterable, Sendable {
    case appTitle = "app.title"
    case accessibilitySaveSelection = "accessibility.save_selection"
    case accessibilityCombat = "accessibility.combat"
    case settingsTitle = "settings.title"
    case settingsMusic = "settings.music"
    case settingsSoundEffects = "settings.sound_effects"
    case settingsHaptics = "settings.haptics"
    case settingsReduceMotion = "settings.reduce_motion"
    case settingsReduceScreenShake = "settings.reduce_screen_shake"
    case settingsSingleTapActions = "settings.single_tap_actions"
    case settingsAnalyticsConsent = "settings.analytics_consent"
    case settingsAnalyticsConsentDetail = "settings.analytics_consent_detail"
    case commonOn = "common.on"
    case commonOff = "common.off"
    case commonClose = "common.close"
    case formatStage = "format.stage"
    case formatStageProgress = "format.stage_progress"
    case formatCredits = "format.credits"
    case formatOfflineMinutes = "format.offline_minutes"
}

enum GameText {
    static func localized(
        _ key: GameTextKey,
        locale: Locale = .current,
        bundle: Bundle = .main
    ) -> String {
        localizationBundle(for: locale, in: bundle)
            .localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
    }

    static func format(
        _ key: GameTextKey,
        locale: Locale = .current,
        bundle: Bundle = .main,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: localized(key, locale: locale, bundle: bundle),
            locale: locale,
            arguments: arguments
        )
    }

    private static func localizationBundle(for locale: Locale, in bundle: Bundle) -> Bundle {
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        let candidates = [languageCode, languageCode.lowercased(), "en"]
        for candidate in candidates {
            guard let path = bundle.path(forResource: candidate, ofType: "lproj"),
                  let localizedBundle = Bundle(path: path)
            else { continue }
            return localizedBundle
        }
        return bundle
    }
}

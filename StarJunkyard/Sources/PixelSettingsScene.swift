import SpriteKit

enum PixelSettingsToggle: String, CaseIterable, Sendable {
    case music
    case soundEffects = "sound_effects"
    case haptics
    case reduceMotion = "reduce_motion"
    case reduceScreenShake = "reduce_screen_shake"
    case singleTapActions = "single_tap_actions"
    case analyticsConsent = "analytics_consent"

    var textKey: GameTextKey {
        switch self {
        case .music: .settingsMusic
        case .soundEffects: .settingsSoundEffects
        case .haptics: .settingsHaptics
        case .reduceMotion: .settingsReduceMotion
        case .reduceScreenShake: .settingsReduceScreenShake
        case .singleTapActions: .settingsSingleTapActions
        case .analyticsConsent: .settingsAnalyticsConsent
        }
    }

    var iconText: String {
        switch self {
        case .music: "♪"
        case .soundEffects: "SFX"
        case .haptics: "HAP"
        case .reduceMotion: "MOVE"
        case .reduceScreenShake: "SHAKE"
        case .singleTapActions: "1 TAP"
        case .analyticsConsent: "DATA"
        }
    }
}

@MainActor
final class PixelSettingsScene: SKScene, AdaptivePixelScene {
    static let logicalSize = PixelViewport.laneSize
    static let rowHitSize = CGSize(width: 312, height: 48)

    var onClose: (() -> Void)?
    var onSettingsChanged: ((GameSettings) -> Void)?
    var onFeedback: ((GameFeedbackEvent) -> Void)?
    var onAnalyticsEvent: ((GameAnalyticsEvent) -> Void)?
    var onAccessibilitySummary: ((String) -> Void)?

    private let settingsStore: GameSettingsStore
    private let consentStore: AnalyticsConsentStore
    private let locale: Locale
    private let bundle: Bundle
    private var settings: GameSettings
    private var consent: AnalyticsConsent
    private var viewport = PixelViewport.phoneFallback

    private let backdrop = SKSpriteNode(color: PixelPalette.ink, size: logicalSize)
    private let laneRoot = SKNode()
    private let headerRoot = SKNode()
    private let footerRoot = SKNode()
    private let railRoot = SKNode()

    init(
        settingsStore: GameSettingsStore,
        consentStore: AnalyticsConsentStore,
        locale: Locale = .current,
        bundle: Bundle = .main
    ) {
        self.settingsStore = settingsStore
        self.consentStore = consentStore
        self.locale = locale
        self.bundle = bundle
        settings = settingsStore.load()
        consent = consentStore.load()
        super.init(size: Self.logicalSize)
        anchorPoint = .zero
        backgroundColor = PixelPalette.ink
        scaleMode = .aspectFit
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        removeAllChildren()
        [laneRoot, headerRoot, footerRoot, railRoot].forEach { $0.removeAllChildren() }
        backdrop.anchorPoint = .zero
        backdrop.position = .zero
        backdrop.zPosition = -100
        addChild(backdrop)
        addChild(laneRoot)
        addChild(railRoot)
        laneRoot.addChild(headerRoot)
        laneRoot.addChild(footerRoot)
        buildConsole()
        applyViewport(PixelViewport(view: view))
        publishAccessibilitySummary()
    }

    func applyViewport(_ viewport: PixelViewport) {
        self.viewport = viewport
        size = viewport.sceneSize
        backdrop.size = viewport.sceneSize
        laneRoot.position = viewport.laneFrame.origin
        let localSafeBottom = viewport.safeFrame.minY - viewport.laneFrame.minY
        let localSafeTop = viewport.safeFrame.maxY - viewport.laneFrame.minY
        headerRoot.position.y = min(0, floor(localSafeTop - 792))
        footerRoot.position.y = max(0, ceil(localSafeBottom))
        rebuildTabletRails()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        let names = Set(nodes(at: point).compactMap(\.name))
        if names.contains("settings_close") {
            onClose?()
            return
        }
        guard let name = names.first(where: { $0.hasPrefix("setting_toggle_") }),
              let toggle = PixelSettingsToggle(
                rawValue: String(name.dropFirst("setting_toggle_".count))
              )
        else { return }
        toggleSetting(toggle)
    }

    func toggleSetting(_ toggle: PixelSettingsToggle) {
        let enabled: Bool
        switch toggle {
        case .music:
            settings.musicEnabled.toggle()
            enabled = settings.musicEnabled
        case .soundEffects:
            settings.soundEffectsEnabled.toggle()
            enabled = settings.soundEffectsEnabled
        case .haptics:
            settings.hapticsEnabled.toggle()
            enabled = settings.hapticsEnabled
        case .reduceMotion:
            settings.reduceMotion.toggle()
            enabled = settings.reduceMotion
        case .reduceScreenShake:
            settings.reduceScreenShake.toggle()
            enabled = settings.reduceScreenShake
        case .singleTapActions:
            settings.singleTapActions.toggle()
            enabled = settings.singleTapActions
        case .analyticsConsent:
            consent = consent == .granted ? .denied : .granted
            consentStore.save(consent)
            enabled = consent == .granted
        }
        if toggle != .analyticsConsent {
            settings.schemaVersion = GameSettings.currentSchemaVersion
            _ = settingsStore.save(settings)
            onSettingsChanged?(settings)
        }
        refreshToggle(toggle)
        onAnalyticsEvent?(.settingChanged(identifier: toggle.rawValue, enabled: enabled))
        if toggle == .soundEffects || toggle == .haptics, enabled {
            onFeedback?(.settingChanged)
        }
        publishAccessibilitySummary()
    }

    func isEnabled(_ toggle: PixelSettingsToggle) -> Bool {
        switch toggle {
        case .music: settings.musicEnabled
        case .soundEffects: settings.soundEffectsEnabled
        case .haptics: settings.hapticsEnabled
        case .reduceMotion: settings.reduceMotion
        case .reduceScreenShake: settings.reduceScreenShake
        case .singleTapActions: settings.singleTapActions
        case .analyticsConsent: consent == .granted
        }
    }

    var accessibilitySummary: String {
        let title = GameText.localized(.accessibilitySettings, locale: locale, bundle: bundle)
        let on = GameText.localized(.commonOn, locale: locale, bundle: bundle)
        let off = GameText.localized(.commonOff, locale: locale, bundle: bundle)
        let values = PixelSettingsToggle.allCases.map { toggle in
            let label = GameText.localized(toggle.textKey, locale: locale, bundle: bundle)
            return label + " " + (isEnabled(toggle) ? on : off)
        }
        return ([title] + values).joined(separator: ". ")
    }

    private func buildConsole() {
        let panel = PixelArt.panel(size: CGSize(width: 336, height: 690), name: "settings_panel")
        panel.position = CGPoint(x: 12, y: 54)
        laneRoot.addChild(panel)

        let gear = PixelArt.sprite(blocks: [
            .init(x: 8, y: 0, width: 16, height: 32, color: PixelPalette.lightIron),
            .init(x: 0, y: 8, width: 32, height: 16, color: PixelPalette.lightIron),
            .init(x: 4, y: 4, width: 24, height: 24, color: PixelPalette.darkIron),
            .init(x: 10, y: 10, width: 12, height: 12, color: PixelPalette.warningAmber),
            .init(x: 14, y: 14, width: 4, height: 4, color: PixelPalette.ink)
        ], name: "settings_gear")
        gear.position = CGPoint(x: 24, y: 696)
        headerRoot.addChild(gear)

        addLabel(
            GameText.localized(.settingsTitle, locale: locale, bundle: bundle),
            x: 68, y: 720, size: 17, color: PixelPalette.warningAmber,
            alignment: .left, parent: headerRoot, name: "settings_title"
        )
        addLabel(
            GameText.localized(.settingsConsoleSubtitle, locale: locale, bundle: bundle),
            x: 68, y: 694, size: 8, color: PixelPalette.lightTeal,
            alignment: .left, parent: headerRoot, name: "settings_subtitle"
        )

        for (index, toggle) in PixelSettingsToggle.allCases.enumerated() {
            addToggleRow(toggle, y: 610 - index * 56)
        }

        addLabel(
            GameText.localized(.settingsAnalyticsConsentDetail, locale: locale, bundle: bundle),
            x: 180, y: 246, size: 7, color: PixelPalette.midIron,
            alignment: .center, parent: laneRoot, name: "analytics_detail"
        )

        let closePanel = PixelArt.panel(size: CGSize(width: 216, height: 52), name: "settings_close")
        closePanel.position = CGPoint(x: 72, y: 132)
        closePanel.name = "settings_close"
        footerRoot.addChild(closePanel)
        let closeHit = SKSpriteNode(color: .clear, size: CGSize(width: 216, height: 52))
        closeHit.anchorPoint = .zero
        closeHit.position = CGPoint(x: 72, y: 132)
        closeHit.zPosition = 3
        closeHit.name = "settings_close"
        footerRoot.addChild(closeHit)
        addLabel(
            "〈  " + GameText.localized(.commonClose, locale: locale, bundle: bundle),
            x: 180, y: 158, size: 11, color: PixelPalette.workWhite,
            alignment: .center, parent: footerRoot, name: "settings_close"
        )
        addLabel(
            GameText.localized(.settingsSavedImmediately, locale: locale, bundle: bundle),
            x: 180, y: 104, size: 7, color: PixelPalette.recoveryGreen,
            alignment: .center, parent: footerRoot, name: "settings_saved"
        )
    }

    private func addToggleRow(_ toggle: PixelSettingsToggle, y: Int) {
        let name = "setting_toggle_" + toggle.rawValue
        let row = PixelArt.panel(size: Self.rowHitSize, name: name)
        row.position = CGPoint(x: 24, y: y)
        row.name = name
        laneRoot.addChild(row)
        let hitArea = SKSpriteNode(color: .clear, size: Self.rowHitSize)
        hitArea.anchorPoint = .zero
        hitArea.position = CGPoint(x: 24, y: y)
        hitArea.zPosition = 3
        hitArea.name = name
        laneRoot.addChild(hitArea)

        let iconPlate = SKSpriteNode(color: PixelPalette.darkTeal, size: CGSize(width: 42, height: 32))
        iconPlate.anchorPoint = .zero
        iconPlate.position = CGPoint(x: 32, y: y + 8)
        iconPlate.zPosition = 4
        iconPlate.name = name
        laneRoot.addChild(iconPlate)
        addLabel(
            toggle.iconText, x: 53, y: y + 24, size: toggle.iconText.count > 3 ? 6 : 9,
            color: PixelPalette.warningAmber, alignment: .center, parent: laneRoot, name: name
        )
        addLabel(
            GameText.localized(toggle.textKey, locale: locale, bundle: bundle),
            x: 86, y: y + 24, size: 10, color: PixelPalette.workWhite,
            alignment: .left, parent: laneRoot, name: name
        )
        addLabel(
            "", x: 316, y: y + 24, size: 9, color: PixelPalette.recoveryGreen,
            alignment: .right, parent: laneRoot, name: valueName(toggle)
        )
        refreshToggle(toggle)
    }

    private func refreshToggle(_ toggle: PixelSettingsToggle) {
        guard let label = laneRoot.childNode(withName: "//" + valueName(toggle)) as? SKLabelNode else {
            return
        }
        label.text = isEnabled(toggle)
            ? "● " + GameText.localized(.commonOn, locale: locale, bundle: bundle)
            : "○ " + GameText.localized(.commonOff, locale: locale, bundle: bundle)
        label.fontColor = isEnabled(toggle) ? PixelPalette.recoveryGreen : PixelPalette.lightIron
    }

    private func rebuildTabletRails() {
        railRoot.removeAllChildren()
        guard viewport.usesTabletRails else { return }
        addRail(
            name: "settings_audio_rail",
            title: "AUDIO / " + GameText.localized(.settingsAudioSection, locale: locale, bundle: bundle),
            lines: [
                GameText.localized(.settingsMusic, locale: locale, bundle: bundle),
                GameText.localized(.settingsSoundEffects, locale: locale, bundle: bundle),
                GameText.localized(.settingsHaptics, locale: locale, bundle: bundle)
            ],
            x: viewport.laneFrame.minX - 150,
            accent: PixelPalette.lightTeal
        )
        addRail(
            name: "settings_access_rail",
            title: "ACCESS / " + GameText.localized(.settingsAccessSection, locale: locale, bundle: bundle),
            lines: [
                GameText.localized(.settingsReduceMotion, locale: locale, bundle: bundle),
                GameText.localized(.settingsSingleTapActions, locale: locale, bundle: bundle),
                GameText.localized(.settingsAnalyticsConsent, locale: locale, bundle: bundle)
            ],
            x: viewport.laneFrame.maxX + 16,
            accent: PixelPalette.warningAmber
        )
    }

    private func addRail(name: String, title: String, lines: [String], x: CGFloat, accent: SKColor) {
        let panel = PixelArt.panel(size: CGSize(width: 134, height: 210), name: name)
        panel.position = CGPoint(x: floor(x), y: floor(viewport.safeFrame.midY - 105))
        panel.name = name
        railRoot.addChild(panel)
        addLabel(title, x: Int(x + 10), y: Int(viewport.safeFrame.midY + 72), size: 8,
                 color: accent, alignment: .left, parent: railRoot, name: name)
        for (index, line) in lines.enumerated() {
            addLabel("• " + line, x: Int(x + 10), y: Int(viewport.safeFrame.midY + 32 - CGFloat(index * 38)),
                     size: 7, color: PixelPalette.workWhite, alignment: .left, parent: railRoot, name: name)
        }
    }

    @discardableResult
    private func addLabel(
        _ text: String,
        x: Int,
        y: Int,
        size: CGFloat,
        color: SKColor,
        alignment: SKLabelHorizontalAlignmentMode,
        parent: SKNode,
        name: String
    ) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.horizontalAlignmentMode = alignment
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: x, y: y)
        label.zPosition = 5
        label.name = name
        parent.addChild(label)
        return label
    }

    private func valueName(_ toggle: PixelSettingsToggle) -> String {
        "setting_value_" + toggle.rawValue
    }

    private func publishAccessibilitySummary() {
        onAccessibilitySummary?(accessibilitySummary)
    }
}

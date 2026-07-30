import SpriteKit
import UIKit

final class GameViewController: UIViewController {
    private let gameView = SKView(frame: .zero)
    private let content: VerticalSliceContent
    private let saveStore: GameSaveStore
    private let settingsStore: GameSettingsStore
    private let consentStore: AnalyticsConsentStore
    private let analytics: any GameAnalytics
    private let purchaseLedgerStore: PurchaseLedgerStore
    private var combatScene: CombatScene?
    private var saveSelectionScene: SaveSelectionScene?
    private var settingsScene: PixelSettingsScene?
    private var purchaseController: StoreKitPurchaseController?
    private var seasonScene: PixelSeasonScene?
    private var seasonPremiumUnlocked = false
    private lazy var cloudSave = GameCenterCloudSave(presenter: self, store: saveStore)
    private lazy var feedback = IOSGameFeedbackService(settings: settingsStore)
    private lazy var operationNotifications = IOSIdleOperationNotificationScheduler()

    init(
        content: VerticalSliceContent = ContentLoader.loadVerticalSlice(),
        saveStore: GameSaveStore = GameSaveStore(),
        settingsStore: GameSettingsStore = GameSettingsStore(),
        consentStore: AnalyticsConsentStore = AnalyticsConsentStore(),
        analytics: (any GameAnalytics)? = nil,
        purchaseLedgerStore: PurchaseLedgerStore = PurchaseLedgerStore()
    ) {
        self.content = content
        self.saveStore = saveStore
        self.settingsStore = settingsStore
        self.consentStore = consentStore
        self.analytics = analytics ?? ConsentGatedGameAnalytics(
            consentStore: consentStore,
            destination: LocalGameAnalyticsRecorder()
        )
        self.purchaseLedgerStore = purchaseLedgerStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = gameView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        gameView.backgroundColor = .black
        gameView.ignoresSiblingOrder = true
        gameView.shouldCullNonVisibleNodes = true
        gameView.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        gameView.isAccessibilityElement = true
        gameView.accessibilityTraits = [.allowsDirectInteraction, .updatesFrequently]
        gameView.accessibilityLabel = GameText.localized(.accessibilitySaveSelection)
        analytics.record(.appLaunched)
        startStoreKit()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-capture-settings") ||
            ProcessInfo.processInfo.arguments.contains("-capture-settings-en") {
            var captureSave = GameSave.newGame()
            captureSave.stageIndex = 3
            captureSave.prologueSeen = true
            captureSave.tutorialStep = 4
            startGame(with: captureSave)
            let locale = ProcessInfo.processInfo.arguments.contains("-capture-settings-en")
                ? Locale(identifier: "en")
                : Locale(identifier: "ko")
            presentSettings(locale: locale)
        } else if ProcessInfo.processInfo.arguments.contains("-capture-premium-store") {
            var captureSave = GameSave.newGame()
            captureSave.prologueSeen = true
            captureSave.tutorialStep = 4
            startGame(with: captureSave, showPremiumStoreOnLaunch: true)
        } else if ProcessInfo.processInfo.arguments.contains("-capture-season") {
            let catalog = SeasonContentLoader.loadCatalog()
            let now = Date()
            let captureDefinition = catalog.definition(at: now) ?? catalog.current
            var captureSave = GameSave.newGame(now: now)
            var progress = SeasonProgress.start(season: captureDefinition, at: now)
            progress.totalXP = 2_650
            progress.weeklyAwardedXP["\(captureDefinition.seasonID):w\(captureDefinition.weekIndex(at: now))"] = 1_240
            let daily = SeasonEngine(catalog: catalog).dailyMissions(
                for: captureDefinition,
                dayIndex: captureDefinition.dayIndex(at: now)
            )
            for (index, mission) in daily.enumerated() {
                progress.missionProgress[mission.instanceID] = index == 0
                    ? mission.definition.target
                    : max(1, mission.definition.target / (index + 2))
            }
            progress.claimedRewardKeys = ["\(captureDefinition.seasonID):free:1"]
            captureSave.seasonProgress = progress
            captureSave.credits = 1_350
            captureSave.parts = 120
            captureSave.prologueSeen = true
            captureSave.tutorialStep = 4
            try? saveStore.save(captureSave)
            startGame(with: captureSave)
            presentSeason(save: captureSave)
        } else if ProcessInfo.processInfo.arguments.contains("-capture-operations") {
            let expeditionStart = Date().addingTimeInterval(-31 * 60)
            var captureSave = GameSave.newGame(now: expeditionStart)
            var operations = IdleOperationsState.newGame(now: expeditionStart)
            _ = try? IdleOperationsEngine.start(.expedition, now: expeditionStart, identifier: "capture-expedition", state: &operations)
            _ = try? IdleOperationsEngine.start(.craft, now: Date().addingTimeInterval(-14 * 60), identifier: "capture-craft", state: &operations)
            captureSave.idleOperations = operations
            captureSave.credits = 1_200
            captureSave.prologueSeen = true
            captureSave.tutorialStep = 4
            startGame(with: captureSave, showOperationsPanelOnLaunch: true)
        } else if ProcessInfo.processInfo.arguments.contains("-capture-formation") {
            var captureSave = GameSave.newGame()
            captureSave.stageIndex = 29
            captureSave.highestStage = 30
            captureSave.credits = 12_000
            captureSave.crewLevel = 4
            captureSave.defeatedBossStages = [10, 20, 30]
            captureSave.prologueSeen = true
            captureSave.tutorialStep = 4
            startGame(with: captureSave, showCrewPanelOnLaunch: true)
        } else if ProcessInfo.processInfo.arguments.contains("-capture-boss-dismantle") {
            var captureSave = GameSave.newGame()
            captureSave.stageIndex = 9
            captureSave.enemyHPs = [0]
            captureSave.credits = 2_500
            captureSave.shelterRepairParts = 12
            captureSave.prologueSeen = true
            captureSave.tutorialStep = 4
            captureSave.pendingBossDismantleStage = 10
            captureSave.pendingBossBaseParts = 15
            startGame(with: captureSave)
        } else if ProcessInfo.processInfo.arguments.contains("-capture-boss") {
            var captureSave = GameSave.newGame()
            captureSave.stageIndex = 9
            captureSave.credits = 2_500
            captureSave.cutterLevel = 12
            captureSave.shelterRepairParts = 12
            captureSave.prologueSeen = true
            captureSave.tutorialStep = 4
            startGame(with: captureSave)
        } else if ProcessInfo.processInfo.arguments.contains("-capture-story") {
            startGame(with: .newGame())
        } else if ProcessInfo.processInfo.arguments.contains("-capture-facility") {
            var captureSave = GameSave.newGame(now: Date().addingTimeInterval(-15 * 60))
            captureSave.stageIndex = 3
            captureSave.credits = 650
            captureSave.parts = 88
            captureSave.crewLevel = 3
            captureSave.pressLevel = 3
            captureSave.sorterLevel = 1
            captureSave.discoveredEnemyIDs = ["can_bug", "umbrella_crab", "fan_bat", "fridge_boar"]
            captureSave.prologueSeen = true
            captureSave.tutorialStep = 4
            startGame(with: captureSave, showFacilityPanelOnLaunch: true)
        } else if ProcessInfo.processInfo.arguments.contains("-capture-combat") {
            var captureSave = GameSave.newGame()
            captureSave.stageIndex = 3
            captureSave.credits = 500
            captureSave.shelterRepairParts = 7
            captureSave.prologueSeen = true
            captureSave.tutorialStep = 4
            startGame(with: captureSave)
        } else {
            presentSaveSelection()
        }
        #else
        presentSaveSelection()
        #endif

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerModeChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appEnteredBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let viewport = PixelViewport(view: gameView)
        (gameView.scene as? AdaptivePixelScene)?.applyViewport(viewport)
    }

    @objc private func powerModeChanged() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        gameView.preferredFramesPerSecond = lowPower ? 30 : 60
        combatScene?.setLowPowerMode(lowPower)
    }

    @objc private func appEnteredBackground() {
        guard let save = saveStore.load(), save.cloudBackupEnabled else { return }
        cloudSave.upload(save) { _ in }
    }

    @objc private func appWillEnterForeground() {
        Task { [weak self] in
            await self?.purchaseController?.refreshEntitlements()
        }
    }

    private func presentSaveSelection(status: String? = nil, isError: Bool = false) {
        let scene = SaveSelectionScene(localSave: saveStore.load())
        scene.onContinue = { [weak self] in
            guard let self else { return }
            self.startGame(with: self.saveStore.load() ?? .newGame())
        }
        scene.onNewGame = { [weak self] in
            guard let self else { return }
            self.startGame(with: .newGame())
        }
        scene.onCloudLoad = { [weak self, weak scene] in
            guard let self else { return }
            scene?.setStatus("Game Center 저장을 확인하는 중…")
            self.cloudSave.load { result in
                switch result {
                case .success(var save):
                    save.cloudBackupEnabled = true
                    save.revision += 1
                    try? self.saveStore.save(save)
                    scene?.refresh(save: save)
                    scene?.setStatus("클라우드 진행을 로컬 슬롯에 복구했습니다.")
                case .failure(let error):
                    scene?.setStatus(error.localizedDescription, isError: true)
                }
            }
        }
        scene.onCloudBackup = { [weak self, weak scene] in
            guard let self, var save = self.saveStore.load() else {
                scene?.setStatus("먼저 새 게임을 시작해 로컬 저장을 만드세요.", isError: true)
                return
            }
            scene?.setStatus("로컬 진행을 Game Center에 백업하는 중…")
            self.cloudSave.upload(save) { result in
                switch result {
                case .success:
                    save.cloudBackupEnabled = true
                    save.revision += 1
                    save.updatedAt = Date()
                    try? self.saveStore.save(save)
                    scene?.refresh(save: save)
                    scene?.setStatus("Game Center 백업 완료 • 로컬 저장 유지")
                case .failure(let error):
                    scene?.setStatus(error.localizedDescription, isError: true)
                }
            }
        }
        if let status { scene.setStatus(status, isError: isError) }
        scene.applyViewport(PixelViewport(view: gameView))
        saveSelectionScene = scene
        settingsScene = nil
        seasonScene = nil
        combatScene = nil
        gameView.accessibilityLabel = GameText.localized(.accessibilitySaveSelection)
        gameView.accessibilityCustomActions = []
        let transitionDuration = GameMotionPolicy.transitionDuration(0.18, settings: settingsStore.load())
        gameView.presentScene(scene, transition: .fade(withDuration: transitionDuration))
    }

    private func startGame(
        with initialSave: GameSave,
        showFacilityPanelOnLaunch: Bool = false,
        showOperationsPanelOnLaunch: Bool = false,
        showCrewPanelOnLaunch: Bool = false,
        showPremiumStoreOnLaunch: Bool = false
    ) {
        let initialEntitlements = purchaseController?.entitlements
            ?? purchaseLedgerStore.loadOrEmpty().entitlementSnapshot()
        seasonPremiumUnlocked = initialEntitlements.contains(.season2026ScrapfrontierPremium)
        let scene = CombatScene(
            content: content,
            save: initialSave,
            premiumEntitlements: initialEntitlements,
            showFacilityPanelOnLaunch: showFacilityPanelOnLaunch,
            showOperationsPanelOnLaunch: showOperationsPanelOnLaunch,
            showPremiumStoreOnLaunch: showPremiumStoreOnLaunch,
            showCrewPanelOnLaunch: showCrewPanelOnLaunch,
            settings: settingsStore.load(),
            seasonPremiumUnlocked: seasonPremiumUnlocked
        )
        scene.applyViewport(PixelViewport(view: gameView))
        scene.onSave = { [weak self] save in try? self?.saveStore.save(save) }
        scene.onAccessibilitySummary = { [weak gameView] summary in gameView?.accessibilityLabel = summary }
        scene.onReturnToSaveSelection = { [weak self] in self?.presentSaveSelection() }
        scene.onOpenSettings = { [weak self] in self?.presentSettings() }
        scene.onFeedback = { [weak self] event in self?.feedback.perform(event) }
        scene.onAnalyticsEvent = { [weak self] event in self?.analytics.record(event) }
        scene.onLongOperationStarted = { [weak self] operation in
            self?.operationNotifications.operationStarted(operation)
        }
        scene.onOpenSeason = { [weak self] in self?.presentSeason() }
        if purchaseController != nil {
            scene.onStorePurchase = { [weak self] productID in
                Task { [weak self] in await self?.purchaseController?.purchase(productID) }
            }
            scene.onStoreRestore = { [weak self] in
                Task { [weak self] in await self?.purchaseController?.restorePurchases() }
            }
            scene.onStoreRetry = { [weak self] in
                Task { [weak self] in await self?.purchaseController?.retryLastOperation() }
            }
        }
        scene.updateStorefront(
            purchaseController?.snapshot ?? .unavailable(entitlements: initialEntitlements)
        )
        combatScene = scene
        saveSelectionScene = nil
        settingsScene = nil
        seasonScene = nil
        configureCombatAccessibility()
        feedback.syncMusic()
        analytics.record(.combatStarted(stage: initialSave.highestStage))
        let duration = GameMotionPolicy.transitionDuration(0.22, settings: settingsStore.load())
        let transition: SKTransition = duration == 0
            ? .fade(withDuration: 0)
            : .doorsOpenVertical(withDuration: duration)
        gameView.presentScene(scene, transition: transition)
    }

    private func presentSettings(locale: Locale = .current) {
        let scene = PixelSettingsScene(
            settingsStore: settingsStore,
            consentStore: consentStore,
            locale: locale,
            bundle: Bundle(for: GameViewController.self)
        )
        scene.onClose = { [weak self] in self?.dismissSettings() }
        scene.onSettingsChanged = { [weak self] settings in
            self?.combatScene?.applySettings(settings)
            self?.feedback.syncMusic()
        }
        scene.onFeedback = { [weak self] event in self?.feedback.perform(event) }
        scene.onAnalyticsEvent = { [weak self] event in self?.analytics.record(event) }
        scene.onAccessibilitySummary = { [weak gameView] summary in
            gameView?.accessibilityLabel = summary
        }
        scene.applyViewport(PixelViewport(view: gameView))
        settingsScene = scene
        saveSelectionScene = nil
        gameView.accessibilityLabel = scene.accessibilitySummary
        gameView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: GameText.localized(.commonClose, locale: locale, bundle: Bundle(for: GameViewController.self)),
                actionHandler: { [weak self] _ in
                    self?.dismissSettings()
                    return true
                }
            )
        ]
        let duration = GameMotionPolicy.transitionDuration(0.16, settings: settingsStore.load())
        gameView.presentScene(scene, transition: .fade(withDuration: duration))
    }

    private func dismissSettings() {
        guard let scene = combatScene else {
            presentSaveSelection()
            return
        }
        let settings = settingsStore.load()
        scene.applySettings(settings)
        scene.applyViewport(PixelViewport(view: gameView))
        settingsScene = nil
        configureCombatAccessibility()
        let duration = GameMotionPolicy.transitionDuration(0.16, settings: settings)
        gameView.presentScene(scene, transition: .fade(withDuration: duration))
    }

    private func configureCombatAccessibility() {
        gameView.accessibilityLabel = GameText.localized(.accessibilityCombat)
        gameView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: GameText.localized(.accessibilityActionSalvage),
                actionHandler: { [weak self] _ in self?.combatScene?.performPrimaryAccessibilityAction() ?? false }
            ),
            UIAccessibilityCustomAction(
                name: GameText.localized(.accessibilityActionSettings),
                actionHandler: { [weak self] _ in
                    self?.presentSettings()
                    return true
                }
            )
        ]
    }

    private func startStoreKit() {
        guard let catalog = try? IAPCatalog.load() else { return }
        let controller = StoreKitPurchaseController(catalog: catalog, ledger: purchaseLedgerStore)
        controller.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.combatScene?.updateStorefront(snapshot)
            self.updateSeasonPremiumUnlocked(
                snapshot.entitlements.contains(.season2026ScrapfrontierPremium)
            )
        }
        purchaseController = controller
        controller.start()
    }

    func updateSeasonPremiumUnlocked(_ unlocked: Bool) {
        seasonPremiumUnlocked = unlocked
        combatScene?.updateSeasonPremiumUnlocked(unlocked)
        seasonScene?.updatePremiumUnlocked(unlocked)
    }

    private func presentSeason(save suppliedSave: GameSave? = nil) {
        guard let save = suppliedSave ?? saveStore.load() else { return }
        let scene = PixelSeasonScene(
            save: save,
            premiumUnlocked: seasonPremiumUnlocked
        )
        scene.onSave = { [weak self] save in try? self?.saveStore.save(save) }
        scene.onAccessibilitySummary = { [weak gameView] summary in
            gameView?.accessibilityLabel = summary
        }
        scene.onClose = { [weak self] in self?.dismissSeason() }
        scene.applyViewport(PixelViewport(view: gameView))
        seasonScene = scene
        saveSelectionScene = nil
        gameView.accessibilityLabel = scene.accessibilitySummary
        let duration = settingsStore.load().reduceMotion ? 0 : 0.16
        gameView.presentScene(scene, transition: .fade(withDuration: duration))
    }

    private func dismissSeason() {
        seasonScene = nil
        startGame(with: saveStore.load() ?? .newGame())
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

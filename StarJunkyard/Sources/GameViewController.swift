import SpriteKit
import UIKit

final class GameViewController: UIViewController {
    private let gameView = SKView(frame: .zero)
    private let content: VerticalSliceContent
    private let saveStore: GameSaveStore
    private var combatScene: CombatScene?
    private var saveSelectionScene: SaveSelectionScene?
    private lazy var cloudSave = GameCenterCloudSave(presenter: self, store: saveStore)

    init(
        content: VerticalSliceContent = ContentLoader.loadVerticalSlice(),
        saveStore: GameSaveStore = GameSaveStore()
    ) {
        self.content = content
        self.saveStore = saveStore
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
        gameView.accessibilityLabel = "저장 선택 화면. 계속하기, 새 게임, Game Center 불러오기를 선택할 수 있습니다."
        presentSaveSelection()

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
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    @objc private func powerModeChanged() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        gameView.preferredFramesPerSecond = lowPower ? 30 : 60
        combatScene?.setLowPowerMode(lowPower)
    }

    @objc private func appEnteredBackground() {
        guard let save = saveStore.load(), save.cloudBackupEnabled else { return }
        cloudSave.upload(save) { _ in }
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
                    save.updatedAt = Date()
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
        saveSelectionScene = scene
        combatScene = nil
        gameView.accessibilityLabel = "저장 선택 화면. 저장된 진행을 계속하거나 새 게임을 시작할 수 있습니다."
        gameView.presentScene(scene, transition: .fade(withDuration: 0.18))
    }

    private func startGame(with initialSave: GameSave) {
        var save = initialSave
        save.updatedAt = Date()
        try? saveStore.save(save)
        let scene = CombatScene(content: content, save: save)
        scene.scaleMode = .aspectFit
        scene.onSave = { [weak self] save in try? self?.saveStore.save(save) }
        scene.onAccessibilitySummary = { [weak gameView] summary in gameView?.accessibilityLabel = summary }
        scene.onReturnToSaveSelection = { [weak self] in self?.presentSaveSelection() }
        combatScene = scene
        saveSelectionScene = nil
        gameView.presentScene(scene, transition: .doorsOpenVertical(withDuration: 0.22))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

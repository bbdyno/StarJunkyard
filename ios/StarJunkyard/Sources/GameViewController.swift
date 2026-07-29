import SpriteKit
import UIKit

final class GameViewController: UIViewController {
    private let gameView = SKView(frame: .zero)
    private let scene: CombatScene

    init(content: VerticalSliceContent = ContentLoader.loadVerticalSlice()) {
        self.scene = CombatScene(content: content)
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
        gameView.accessibilityLabel = "전투 화면. 스테이지 1. 자동 해체 진행 중."

        scene.scaleMode = .aspectFit
        scene.onAccessibilitySummary = { [weak gameView] summary in
            gameView?.accessibilityLabel = summary
        }
        gameView.presentScene(scene)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerModeChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    @objc private func powerModeChanged() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        gameView.preferredFramesPerSecond = lowPower ? 30 : 60
        scene.setLowPowerMode(lowPower)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

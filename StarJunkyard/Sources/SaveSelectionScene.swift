import SpriteKit

@MainActor
final class SaveSelectionScene: SKScene {
    static let logicalSize = CGSize(width: 360, height: 800)

    var onContinue: (() -> Void)?
    var onNewGame: (() -> Void)?
    var onCloudLoad: (() -> Void)?
    var onCloudBackup: (() -> Void)?

    private var localSave: GameSave?
    private let summaryLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let statusLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Medium")
    private let continueLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private var newGameArmed = false

    init(localSave: GameSave?) {
        self.localSave = localSave
        super.init(size: Self.logicalSize)
        backgroundColor = PixelPalette.ink
        scaleMode = .aspectFit
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        removeAllChildren()
        buildBackground()
        buildStory()
        buildSavePanel()
        buildButtons()
        refresh(save: localSave)
    }

    func refresh(save: GameSave?) {
        localSave = save
        summaryLabel.text = save?.summary ?? "저장 없음  •  새 폐품장을 시작하세요"
        continueLabel.text = save == nil ? "저장된 게임 없음" : "계속하기"
        continueLabel.fontColor = save == nil ? PixelPalette.midIron : PixelPalette.warningAmber
    }

    func setStatus(_ message: String, isError: Bool = false) {
        statusLabel.text = message
        statusLabel.fontColor = isError ? PixelPalette.sparkOrange : PixelPalette.lightTeal
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        let names = Set(nodes(at: point).compactMap(\.name))
        if names.contains("continue_save") {
            if localSave == nil {
                setStatus("저장된 진행이 없습니다. [새 게임]을 선택하세요.", isError: true)
            } else {
                onContinue?()
            }
            return
        }
        if names.contains("new_game") {
            if localSave != nil && !newGameArmed {
                newGameArmed = true
                setStatus("새 게임은 로컬 진행을 교체합니다. 한 번 더 누르세요.", isError: true)
            } else {
                onNewGame?()
            }
            return
        }
        if names.contains("cloud_load") { onCloudLoad?(); return }
        if names.contains("cloud_backup") { onCloudBackup?() }
    }

    private func buildBackground() {
        let yard = PixelArt.asset("background_r01_back_alley")
        yard.position = CGPoint(x: 180, y: 514)
        yard.zPosition = -20
        addChild(yard)

        let mechanic = PixelArt.asset("actor_mo_base", scale: 2)
        mechanic.position = CGPoint(x: 82, y: 468)
        mechanic.zPosition = 3
        mechanic.run(stepLoop(points: [0, 1, 0, -1], duration: 0.15))
        addChild(mechanic)

        let drone = PixelArt.asset("drone_riv0_base")
        drone.position = CGPoint(x: 148, y: 570)
        drone.zPosition = 4
        drone.run(stepLoop(points: [0, 2, 0, -2], duration: 0.11))
        addChild(drone)

        let shade = SKSpriteNode(color: PixelPalette.ink.withAlphaComponent(0.78), size: CGSize(width: 360, height: 800))
        shade.anchorPoint = .zero
        shade.zPosition = 10
        addChild(shade)
    }

    private func buildStory() {
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        configure(title, size: 24, color: PixelPalette.warningAmber)
        title.text = "STAR JUNKYARD"
        title.position = CGPoint(x: 180, y: 728)
        title.zPosition = 20
        addChild(title)

        let subtitle = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configure(subtitle, size: 13, color: PixelPalette.workWhite)
        subtitle.text = "별을 줍는 고물상"
        subtitle.position = CGPoint(x: 180, y: 696)
        subtitle.zPosition = 20
        addChild(subtitle)

        let story = [
            "살아 움직이는 우주 폐기물을 해체하고",
            "고철과 부품으로 피난처 7호를 복구하세요."
        ]
        for (index, line) in story.enumerated() {
            let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Medium")
            configure(label, size: 10, color: PixelPalette.lightTeal)
            label.text = line
            label.position = CGPoint(x: 180, y: 648 - index * 20)
            label.zPosition = 20
            addChild(label)
        }
    }

    private func buildSavePanel() {
        let panel = PixelArt.panel(size: CGSize(width: 324, height: 92), name: "save_slot")
        panel.position = CGPoint(x: 18, y: 492)
        panel.zPosition = 20
        addChild(panel)

        let slot = SKLabelNode(fontNamed: "Menlo-Bold")
        configure(slot, size: 10, color: PixelPalette.warningAmber)
        slot.horizontalAlignmentMode = .left
        slot.text = "LOCAL SLOT 01"
        slot.position = CGPoint(x: 34, y: 555)
        slot.zPosition = 22
        addChild(slot)

        configure(summaryLabel, size: 11, color: PixelPalette.workWhite)
        summaryLabel.position = CGPoint(x: 180, y: 522)
        summaryLabel.zPosition = 22
        addChild(summaryLabel)

        configure(statusLabel, size: 9, color: PixelPalette.lightTeal)
        statusLabel.text = "로컬 저장이 원본입니다. 클라우드는 선택 백업입니다."
        statusLabel.position = CGPoint(x: 180, y: 474)
        statusLabel.zPosition = 22
        addChild(statusLabel)
    }

    private func buildButtons() {
        addButton(name: "continue_save", title: "", y: 388, color: PixelPalette.warningAmber, label: continueLabel)
        addButton(name: "new_game", title: "새 게임", y: 324, color: PixelPalette.lightTeal)
        addButton(name: "cloud_load", title: "Game Center에서 불러오기", y: 260, color: PixelPalette.workBlue)
        addButton(name: "cloud_backup", title: "로컬 진행을 Game Center에 백업", y: 196, color: PixelPalette.midIron)

        let hint = SKLabelNode(fontNamed: "AppleSDGothicNeo-Medium")
        configure(hint, size: 9, color: PixelPalette.lightIron)
        hint.text = "로그인 없이도 새 게임과 로컬 저장은 항상 가능합니다."
        hint.position = CGPoint(x: 180, y: 156)
        hint.zPosition = 20
        addChild(hint)
    }

    private func addButton(
        name: String,
        title: String,
        y: Int,
        color: SKColor,
        label suppliedLabel: SKLabelNode? = nil
    ) {
        let panel = PixelArt.panel(size: CGSize(width: 284, height: 50), name: name)
        panel.position = CGPoint(x: 38, y: y)
        panel.zPosition = 20
        panel.name = name
        addChild(panel)

        let label = suppliedLabel ?? SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configure(label, size: 12, color: color)
        label.text = title.isEmpty ? label.text : title
        label.position = CGPoint(x: 180, y: y + 25)
        label.zPosition = 22
        label.name = name
        addChild(label)
    }

    private func configure(_ label: SKLabelNode, size: CGFloat, color: SKColor) {
        label.fontSize = size
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
    }

    private func stepLoop(points: [Int], duration: TimeInterval) -> SKAction {
        var actions: [SKAction] = []
        var previous = 0
        for point in points {
            actions.append(.moveBy(x: 0, y: CGFloat(point - previous), duration: 0))
            actions.append(.wait(forDuration: duration))
            previous = point
        }
        actions.append(.moveBy(x: 0, y: CGFloat(-previous), duration: 0))
        return .repeatForever(.sequence(actions))
    }
}

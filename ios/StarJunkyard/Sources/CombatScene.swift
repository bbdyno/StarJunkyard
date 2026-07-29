import SpriteKit

@MainActor
final class CombatScene: SKScene {
    static let logicalSize = CGSize(width: 360, height: 800)

    var onAccessibilitySummary: ((String) -> Void)?

    private let content: VerticalSliceContent
    private let enemyByID: [String: VerticalSliceContent.Enemy]
    private var stageIndex = 0
    private var waveIndex = 0
    private var enemyHP = 0
    private var enemyMaxHP = 1
    private var combatTick = 0
    private var nextPlayerAttackTick = 1
    private var nextDroneAttackTick = 1
    private var overclockUntilTick = 0
    private var credits = 0
    private var parts = 0
    private var accumulator: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var rng = PCG32(seed: 42, stream: 54)

    private let enemyAnchor = SKNode()
    private let scrapLayer = SKNode()
    private let rainLayer = SKNode()
    private let stageLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let currencyLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let enemyLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let hpFill = SKSpriteNode(color: PixelPalette.recoveryGreen, size: CGSize(width: 116, height: 6))
    private let overclockButton = SKNode()
    private let overclockFill = SKSpriteNode(color: PixelPalette.warningAmber, size: CGSize(width: 54, height: 5))

    init(content: VerticalSliceContent) {
        self.content = content
        self.enemyByID = Dictionary(uniqueKeysWithValues: content.enemies.map { ($0.id, $0) })
        super.init(size: Self.logicalSize)
        anchorPoint = .zero
        backgroundColor = PixelPalette.ink
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        removeAllChildren()
        buildBackground()
        buildBase()
        buildCombatants()
        buildHUD()
        buildControls()
        buildBottomTabs()
        spawnCurrentEnemy()
        setLowPowerMode(ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    func setLowPowerMode(_ enabled: Bool) {
        rainLayer.children.enumerated().forEach { index, node in
            node.isHidden = enabled && index.isMultiple(of: 2)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }
        accumulator += min(0.25, currentTime - lastUpdateTime)
        lastUpdateTime = currentTime
        var steps = 0
        while accumulator >= 0.05 && steps < 5 {
            simulateTick()
            accumulator -= 0.05
            steps += 1
        }
        if steps == 5 && accumulator >= 0.05 {
            accumulator = 0
        }
        snapToPixelGrid(self)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        let touchedNodes = nodes(at: point)
        if touchedNodes.contains(where: { $0.name == "overclock" || $0.parent?.name == "overclock" }) {
            activateOverclock()
        }
    }

    private func simulateTick() {
        guard enemyHP > 0 else { return }
        combatTick += 1

        if combatTick >= nextPlayerAttackTick {
            let interval = combatTick < overclockUntilTick ? 15 : 24
            nextPlayerAttackTick = combatTick + interval
            dealDamage(base: content.player.baseDamage * 3, source: CGPoint(x: 91, y: 286))
        }
        if combatTick >= nextDroneAttackTick {
            nextDroneAttackTick = combatTick + 20
            dealDamage(base: content.drones[0].baseDamage * 2, source: CGPoint(x: 128, y: 376))
        }

        if combatTick.isMultiple(of: 100) {
            let stage = content.stages[stageIndex]
            let enemyName = currentEnemy.map(\.nameKo) ?? "없음"
            onAccessibilitySummary?("전투 화면. 스테이지 \(stage.number). \(enemyName) 내구도 \(max(0, enemyHP)) / \(enemyMaxHP). 오버클럭 버튼 사용 가능.")
        }
        updateHUD()
    }

    private func dealDamage(base: Int, source: CGPoint) {
        let critical = rng.bounded(1_000_000) < UInt32(content.player.criticalChancePpm)
        let damage = critical ? base * content.player.criticalDamagePpm / 1_000_000 : base
        enemyHP -= damage
        spawnProjectile(from: source, critical: critical)
        if enemyHP <= 0 {
            dismantleCurrentEnemy()
        }
    }

    private var currentEnemy: VerticalSliceContent.Enemy? {
        let stage = content.stages[stageIndex]
        guard waveIndex < stage.wave.count else { return nil }
        return enemyByID[stage.wave[waveIndex]]
    }

    private func spawnCurrentEnemy() {
        guard let enemy = currentEnemy else { return }
        enemyAnchor.removeAllChildren()
        #if DEBUG
        let pixelEnemy = DebugPixelArt.enemy(id: enemy.id)
        #else
        preconditionFailure("Production atlas is not available")
        #endif
        pixelEnemy.position = enemy.enemyClass == "boss" ? CGPoint(x: -48, y: -36) : CGPoint(x: -20, y: -18)
        enemyAnchor.addChild(pixelEnemy)
        enemyLabel.text = enemy.nameKo
        let stage = content.stages[stageIndex]
        enemyMaxHP = max(1, stage.baseHp * enemy.hpMultiplierPpm / 1_000_000)
        enemyHP = enemyMaxHP
        updateHUD()
    }

    private func dismantleCurrentEnemy() {
        guard let enemy = currentEnemy else { return }
        let stage = content.stages[stageIndex]
        credits += stage.baseReward * stage.rewardMultiplierPpm / 1_000_000
        parts += enemy.enemyClass == "boss" ? 15 : (enemy.enemyClass == "elite" ? 6 : 3)
        spawnScrapBurst()
        enemyAnchor.removeAllChildren()
        waveIndex += 1
        if waveIndex >= stage.wave.count {
            stageIndex = (stageIndex + 1) % content.stages.count
            waveIndex = 0
            rng = PCG32(seed: UInt64(content.stages[stageIndex].number), stream: 54)
        }
        run(.sequence([
            .wait(forDuration: 0.3),
            .run { [weak self] in self?.spawnCurrentEnemy() }
        ]))
    }

    private func activateOverclock() {
        guard combatTick >= overclockUntilTick else { return }
        overclockUntilTick = combatTick + 160
        overclockFill.color = PixelPalette.workWhite
        let pulse = SKAction.sequence([
            .run { [weak overclockButton] in overclockButton?.position.y += 2 },
            .wait(forDuration: 0.08),
            .run { [weak overclockButton] in overclockButton?.position.y -= 2 }
        ])
        overclockButton.run(pulse)
    }

    private func buildBackground() {
        addBlock(size: CGSize(width: 360, height: 800), color: PixelPalette.deepNavy, position: .zero, z: -100)
        addBlock(size: CGSize(width: 360, height: 246), color: PixelPalette.darkRust, position: CGPoint(x: 0, y: 484), z: -90)
        addBlock(size: CGSize(width: 360, height: 8), color: PixelPalette.rust, position: CGPoint(x: 0, y: 484), z: -89)
        for index in 0..<12 {
            let window = addBlock(
                size: CGSize(width: 12, height: 18),
                color: index.isMultiple(of: 3) ? PixelPalette.warningAmber : PixelPalette.darkIron,
                position: CGPoint(x: 12 + index * 29, y: 620 + (index % 2) * 22),
                z: -88
            )
            window.alpha = index.isMultiple(of: 3) ? 1 : 0.65
        }
        addChild(rainLayer)
        rainLayer.name = "rain"
        for index in 0..<24 {
            let drop = SKSpriteNode(color: PixelPalette.workBlue, size: CGSize(width: 1, height: 5 + index % 3))
            drop.anchorPoint = .zero
            drop.position = CGPoint(x: (index * 17) % 360, y: 470 + (index * 31) % 250)
            drop.zPosition = -70
            let fall = SKAction.sequence([
                .moveBy(x: 0, y: -120, duration: 1.2 + Double(index % 4) * 0.15),
                .moveBy(x: 0, y: 120, duration: 0)
            ])
            drop.run(.repeatForever(fall))
            rainLayer.addChild(drop)
        }
    }

    private func buildBase() {
        addBlock(size: CGSize(width: 360, height: 8), color: PixelPalette.ink, position: CGPoint(x: 0, y: 484), z: -10)
        addBlock(size: CGSize(width: 190, height: 8), color: PixelPalette.midIron, position: CGPoint(x: 8, y: 514), z: -8)
        for index in 0..<8 {
            addBlock(size: CGSize(width: 10, height: 4), color: PixelPalette.lightIron, position: CGPoint(x: 14 + index * 22, y: 516), z: -7)
        }
        addBlock(size: CGSize(width: 70, height: 64), color: PixelPalette.darkIron, position: CGPoint(x: 8, y: 526), z: -12)
        addBlock(size: CGSize(width: 58, height: 6), color: PixelPalette.teal, position: CGPoint(x: 14, y: 578), z: -11)
        addBlock(size: CGSize(width: 32, height: 36), color: PixelPalette.darkRust, position: CGPoint(x: 92, y: 526), z: -11)
        addBlock(size: CGSize(width: 5, height: 5), color: PixelPalette.warningAmber, position: CGPoint(x: 105, y: 552), z: -10)
    }

    private func buildCombatants() {
        #if DEBUG
        let mechanic = DebugPixelArt.mechanic()
        let drone = DebugPixelArt.rivetDrone()
        #else
        preconditionFailure("Production atlas is not available")
        #endif
        mechanic.position = CGPoint(x: 66, y: 248)
        mechanic.zPosition = 20
        addChild(mechanic)
        drone.position = CGPoint(x: 110, y: 354)
        drone.zPosition = 22
        drone.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 2, duration: 0.25),
            .moveBy(x: 0, y: -2, duration: 0.25)
        ])))
        addChild(drone)
        enemyAnchor.position = CGPoint(x: 260, y: 276)
        enemyAnchor.zPosition = 20
        addChild(enemyAnchor)
        scrapLayer.zPosition = 30
        addChild(scrapLayer)
    }

    private func buildHUD() {
        let hud = DebugPixelArt.panel(size: CGSize(width: 344, height: 62), name: "hud_panel")
        hud.position = CGPoint(x: 8, y: 730)
        hud.zPosition = 100
        addChild(hud)

        configureLabel(stageLabel, size: 13, color: PixelPalette.workWhite, alignment: .left)
        stageLabel.position = CGPoint(x: 18, y: 760)
        stageLabel.zPosition = 101
        addChild(stageLabel)

        configureLabel(currencyLabel, size: 11, color: PixelPalette.warningAmber, alignment: .right)
        currencyLabel.position = CGPoint(x: 342, y: 760)
        currencyLabel.zPosition = 101
        addChild(currencyLabel)

        configureLabel(enemyLabel, size: 10, color: PixelPalette.workWhite, alignment: .center)
        enemyLabel.position = CGPoint(x: 260, y: 390)
        enemyLabel.zPosition = 40
        addChild(enemyLabel)

        addBlock(size: CGSize(width: 120, height: 10), color: PixelPalette.ink, position: CGPoint(x: 200, y: 372), z: 39)
        hpFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpFill.position = CGPoint(x: 202, y: 377)
        hpFill.zPosition = 40
        addChild(hpFill)

        let debug = SKLabelNode(fontNamed: "Menlo-Bold")
        debug.text = "DEBUG PIXEL ART"
        debug.fontSize = 7
        debug.fontColor = PixelPalette.memoryMagenta
        debug.horizontalAlignmentMode = .right
        debug.position = CGPoint(x: 346, y: 739)
        debug.zPosition = 102
        addChild(debug)
    }

    private func buildControls() {
        let panel = DebugPixelArt.panel(size: CGSize(width: 344, height: 94), name: "combat_controls")
        panel.position = CGPoint(x: 8, y: 72)
        panel.zPosition = 90
        addChild(panel)

        let retry = DebugPixelArt.panel(size: CGSize(width: 54, height: 38), name: "retry")
        retry.position = CGPoint(x: 18, y: 96)
        retry.zPosition = 91
        addChild(retry)
        addPixelIcon(at: CGPoint(x: 34, y: 107), type: .loop, z: 92)

        let speeds = ["1x", "2x", "3x"]
        for (index, text) in speeds.enumerated() {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = text
            label.fontSize = 9
            label.fontColor = index == 0 ? PixelPalette.warningAmber : PixelPalette.midIron
            label.position = CGPoint(x: 98 + index * 34, y: 112)
            label.zPosition = 92
            addChild(label)
        }

        let overclockPanel = DebugPixelArt.panel(size: CGSize(width: 72, height: 48), name: "overclock")
        overclockPanel.position = .zero
        overclockButton.name = "overclock"
        overclockButton.position = CGPoint(x: 268, y: 92)
        overclockButton.zPosition = 92
        overclockButton.addChild(overclockPanel)
        let bolt = DebugPixelArt.sprite(blocks: [
            .init(x: 29, y: 23, width: 8, height: 16, color: PixelPalette.warningAmber),
            .init(x: 21, y: 17, width: 16, height: 8, color: PixelPalette.warningAmber),
            .init(x: 21, y: 9, width: 8, height: 10, color: PixelPalette.warningAmber)
        ], name: "overclock")
        overclockButton.addChild(bolt)
        overclockFill.anchorPoint = .zero
        overclockFill.position = CGPoint(x: 9, y: 5)
        overclockFill.name = "overclock"
        overclockButton.addChild(overclockFill)
        addChild(overclockButton)
    }

    private func buildBottomTabs() {
        addBlock(size: CGSize(width: 360, height: 68), color: PixelPalette.ink, position: .zero, z: 110)
        let iconTypes: [PixelIcon] = [.cutter, .base, .crate, .expedition]
        for index in 0..<4 {
            let x = 8 + index * 88
            let selected = index == 0
            addBlock(
                size: CGSize(width: 80, height: 56),
                color: selected ? PixelPalette.darkTeal : PixelPalette.deepNavy,
                position: CGPoint(x: x, y: 6),
                z: 111
            )
            addPixelIcon(at: CGPoint(x: x + 28, y: 19), type: iconTypes[index], z: 112)
            if selected {
                addBlock(size: CGSize(width: 48, height: 3), color: PixelPalette.warningAmber, position: CGPoint(x: x + 16, y: 6), z: 113)
            }
        }
    }

    private func spawnProjectile(from source: CGPoint, critical: Bool) {
        let color = critical ? PixelPalette.warningAmber : PixelPalette.lightTeal
        let projectile = SKSpriteNode(color: color, size: CGSize(width: critical ? 8 : 5, height: 3))
        projectile.position = source
        projectile.zPosition = 31
        addChild(projectile)
        let target = CGPoint(x: 246, y: 306)
        let points = [
            CGPoint(x: source.x + 38, y: source.y + 14),
            CGPoint(x: source.x + 82, y: source.y + 8),
            CGPoint(x: target.x, y: target.y)
        ]
        var actions: [SKAction] = points.flatMap { point in [.move(to: point, duration: 0), .wait(forDuration: 0.035)] }
        actions.append(.removeFromParent())
        projectile.run(.sequence(actions))
    }

    private func spawnScrapBurst() {
        for index in 0..<8 {
            let scrap = SKSpriteNode(
                color: index.isMultiple(of: 3) ? PixelPalette.warningAmber : PixelPalette.lightIron,
                size: CGSize(width: 3 + index % 3, height: 3 + (index + 1) % 2)
            )
            scrap.position = CGPoint(x: 258 + (index % 4) * 4, y: 300 + (index / 4) * 7)
            scrapLayer.addChild(scrap)
            let points = [
                CGPoint(x: 230 - index * 2, y: 340 + (index % 3) * 5),
                CGPoint(x: 180 - index * 4, y: 412),
                CGPoint(x: 130 - index * 5, y: 520)
            ]
            var actions: [SKAction] = points.flatMap { point in [.move(to: point, duration: 0), .wait(forDuration: 0.06)] }
            actions.append(.removeFromParent())
            scrap.run(.sequence(actions))
        }
    }

    private func updateHUD() {
        let stage = content.stages[stageIndex]
        stageLabel.text = "R1  STAGE \(String(format: "%03d", stage.number))"
        currencyLabel.text = "C \(credits)   P \(parts)"
        let ratio = CGFloat(max(0, enemyHP)) / CGFloat(max(1, enemyMaxHP))
        hpFill.size.width = floor(116 * ratio)
        let charge = combatTick >= overclockUntilTick ? 1 : CGFloat(max(0, overclockUntilTick - combatTick)) / 160
        overclockFill.size.width = floor(54 * charge)
        if combatTick >= overclockUntilTick {
            overclockFill.color = PixelPalette.warningAmber
        }
    }

    @discardableResult
    private func addBlock(size: CGSize, color: SKColor, position: CGPoint, z: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(color: color, size: size)
        node.anchorPoint = .zero
        node.position = position
        node.zPosition = z
        addChild(node)
        return node
    }

    private func configureLabel(_ label: SKLabelNode, size: CGFloat, color: SKColor, alignment: SKLabelHorizontalAlignmentMode) {
        label.fontSize = size
        label.fontColor = color
        label.horizontalAlignmentMode = alignment
        label.verticalAlignmentMode = .center
    }

    private enum PixelIcon { case cutter, base, crate, expedition, loop }

    private func addPixelIcon(at position: CGPoint, type: PixelIcon, z: CGFloat) {
        let blocks: [DebugPixelArt.Block]
        switch type {
        case .cutter:
            blocks = [.init(x: 0, y: 10, width: 22, height: 5, color: PixelPalette.lightIron), .init(x: 15, y: 5, width: 6, height: 15, color: PixelPalette.sparkOrange)]
        case .base:
            blocks = [.init(x: 2, y: 4, width: 20, height: 15, color: PixelPalette.midIron), .init(x: 7, y: 18, width: 10, height: 7, color: PixelPalette.rust)]
        case .crate:
            blocks = [.init(x: 2, y: 4, width: 22, height: 20, color: PixelPalette.rust), .init(x: 6, y: 8, width: 14, height: 3, color: PixelPalette.warningAmber)]
        case .expedition:
            blocks = [.init(x: 10, y: 1, width: 5, height: 25, color: PixelPalette.lightIron), .init(x: 2, y: 7, width: 21, height: 5, color: PixelPalette.teal)]
        case .loop:
            blocks = [.init(x: 2, y: 16, width: 20, height: 4, color: PixelPalette.teal), .init(x: 2, y: 5, width: 4, height: 14, color: PixelPalette.teal), .init(x: 6, y: 4, width: 16, height: 4, color: PixelPalette.warningAmber)]
        }
        let icon = DebugPixelArt.sprite(blocks: blocks, name: "pixel_icon")
        icon.position = position
        icon.zPosition = z
        addChild(icon)
    }

    private func snapToPixelGrid(_ node: SKNode) {
        for child in node.children {
            child.position = CGPoint(x: child.position.x.rounded(), y: child.position.y.rounded())
            snapToPixelGrid(child)
        }
    }
}

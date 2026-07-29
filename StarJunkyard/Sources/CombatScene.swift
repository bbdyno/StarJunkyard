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

    private let mechanicAnchor = SKNode()
    private let mechanicMotion = SKNode()
    private let droneAnchor = SKNode()
    private let droneMotion = SKNode()
    private let enemyAnchor = SKNode()
    private var enemyArt: SKSpriteNode?
    private let scrapLayer = SKNode()
    private let rainLayer = SKNode()
    private let stageLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let locationLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let currencyLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let enemyLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let hpFill = SKSpriteNode(color: PixelPalette.recoveryGreen, size: CGSize(width: 116, height: 6))
    private let overclockButton = SKNode()
    private let overclockFill = SKSpriteNode(color: PixelPalette.warningAmber, size: CGSize(width: 62, height: 5))

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
        buildCombatants()
        buildHUD()
        buildControls()
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
        if steps == 5 && accumulator >= 0.05 { accumulator = 0 }
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
            playMechanicAttack()
            dealDamage(base: content.player.baseDamage * 3, source: CGPoint(x: 126, y: 286))
        }
        if combatTick >= nextDroneAttackTick {
            nextDroneAttackTick = combatTick + 20
            playDroneAttack()
            dealDamage(base: content.drones[0].baseDamage * 2, source: CGPoint(x: 150, y: 420))
        }

        if combatTick.isMultiple(of: 100) {
            let stage = content.stages[stageIndex]
            let enemyName = currentEnemy.map(\.nameKo) ?? "없음"
            onAccessibilitySummary?("전투 화면. 스테이지 \(stage.number). \(enemyName) 내구도 \(max(0, enemyHP)) / \(enemyMaxHP). 과부하 버튼 사용 가능.")
        }
        updateHUD()
    }

    private func dealDamage(base: Int, source: CGPoint) {
        let critical = rng.bounded(1_000_000) < UInt32(content.player.criticalChancePpm)
        let damage = critical ? base * content.player.criticalDamagePpm / 1_000_000 : base
        enemyHP -= damage
        spawnProjectile(from: source, critical: critical)
        playEnemyHit()
        if enemyHP <= 0 { dismantleCurrentEnemy() }
    }

    private var currentEnemy: VerticalSliceContent.Enemy? {
        let stage = content.stages[stageIndex]
        guard waveIndex < stage.wave.count else { return nil }
        return enemyByID[stage.wave[waveIndex]]
    }

    private func spawnCurrentEnemy() {
        guard let enemy = currentEnemy else { return }
        enemyAnchor.removeAllActions()
        enemyAnchor.removeAllChildren()

        let scale: CGFloat
        switch enemy.id {
        case "can_bug", "umbrella_crab", "fan_bat", "vending_knight": scale = 2
        default: scale = 1
        }
        let art = PixelArt.asset(enemy.spriteId, scale: scale)
        art.zPosition = 2
        enemyAnchor.addChild(art)
        enemyArt = art
        enemyLabel.text = enemy.nameKo
        configureEnemyMotion(enemy.id)

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
        enemyAnchor.removeAllActions()
        enemyAnchor.removeAllChildren()
        waveIndex += 1
        if waveIndex >= stage.wave.count {
            stageIndex = (stageIndex + 1) % content.stages.count
            waveIndex = 0
            rng = PCG32(seed: UInt64(content.stages[stageIndex].number), stream: 54)
        }
        run(.sequence([
            .wait(forDuration: 0.34),
            .run { [weak self] in self?.spawnCurrentEnemy() }
        ]))
    }

    private func activateOverclock() {
        guard combatTick >= overclockUntilTick else { return }
        overclockUntilTick = combatTick + 160
        overclockFill.color = PixelPalette.workWhite
        overclockButton.run(.sequence([
            .moveBy(x: 0, y: 3, duration: 0),
            .wait(forDuration: 0.08),
            .moveBy(x: 0, y: -3, duration: 0)
        ]))
    }

    private func buildBackground() {
        addBlock(size: Self.logicalSize, color: PixelPalette.deepNavy, position: .zero, z: -120)
        let yard = PixelArt.asset("background_r01_back_alley")
        yard.position = CGPoint(x: 180, y: 446)
        yard.zPosition = -110
        addChild(yard)

        addChild(rainLayer)
        rainLayer.name = "rain"
        for index in 0..<20 {
            let drop = SKSpriteNode(color: PixelPalette.workBlue, size: CGSize(width: 1, height: 4 + index % 3))
            drop.anchorPoint = .zero
            drop.position = CGPoint(x: (index * 19) % 360, y: 176 + (index * 31) % 530)
            drop.zPosition = -80
            let reset = SKAction.moveBy(x: 0, y: 128, duration: 0)
            let fall = SKAction.moveBy(x: 0, y: -128, duration: 1.0 + Double(index % 4) * 0.12)
            drop.run(.repeatForever(.sequence([fall, reset])))
            rainLayer.addChild(drop)
        }
    }

    private func buildCombatants() {
        mechanicAnchor.position = CGPoint(x: 76, y: 284)
        mechanicAnchor.zPosition = 20
        let mechanic = PixelArt.asset(content.player.spriteId, scale: 2)
        mechanicMotion.addChild(mechanic)
        mechanicAnchor.addChild(mechanicMotion)
        mechanicAnchor.run(stepLoop(points: [0, 1, 0, -1], duration: 0.14), withKey: "idle")
        addChild(mechanicAnchor)

        droneAnchor.position = CGPoint(x: 128, y: 420)
        droneAnchor.zPosition = 24
        let drone = PixelArt.asset(content.drones[0].spriteId)
        droneMotion.addChild(drone)
        droneAnchor.addChild(droneMotion)
        droneAnchor.run(stepLoop(points: [0, 2, 0, -2], duration: 0.11), withKey: "hover")
        addChild(droneAnchor)

        enemyAnchor.position = CGPoint(x: 276, y: 284)
        enemyAnchor.zPosition = 20
        addChild(enemyAnchor)
        scrapLayer.zPosition = 34
        addChild(scrapLayer)
    }

    private func buildHUD() {
        let hud = PixelArt.panel(size: CGSize(width: 344, height: 62), name: "hud_panel")
        hud.position = CGPoint(x: 8, y: 730)
        hud.zPosition = 100
        addChild(hud)

        configureLabel(stageLabel, size: 12, color: PixelPalette.workWhite, alignment: .left)
        stageLabel.position = CGPoint(x: 18, y: 764)
        stageLabel.zPosition = 101
        addChild(stageLabel)

        configureLabel(locationLabel, size: 8, color: PixelPalette.lightTeal, alignment: .left)
        locationLabel.text = "뒷골목 압착장"
        locationLabel.position = CGPoint(x: 18, y: 742)
        locationLabel.zPosition = 101
        addChild(locationLabel)

        configureLabel(currencyLabel, size: 9, color: PixelPalette.warningAmber, alignment: .right)
        currencyLabel.position = CGPoint(x: 342, y: 764)
        currencyLabel.zPosition = 101
        addChild(currencyLabel)

        configureLabel(enemyLabel, size: 11, color: PixelPalette.workWhite, alignment: .center)
        enemyLabel.position = CGPoint(x: 276, y: 386)
        enemyLabel.zPosition = 42
        addChild(enemyLabel)

        addBlock(size: CGSize(width: 124, height: 12), color: PixelPalette.ink, position: CGPoint(x: 214, y: 364), z: 39)
        addBlock(size: CGSize(width: 118, height: 6), color: PixelPalette.darkIron, position: CGPoint(x: 217, y: 367), z: 40)
        hpFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpFill.position = CGPoint(x: 218, y: 370)
        hpFill.zPosition = 41
        addChild(hpFill)
    }

    private func buildControls() {
        addBlock(size: CGSize(width: 360, height: 160), color: PixelPalette.ink, position: .zero, z: 85)
        let panel = PixelArt.panel(size: CGSize(width: 344, height: 144), name: "workshop_console")
        panel.position = CGPoint(x: 8, y: 8)
        panel.zPosition = 90
        addChild(panel)

        let status = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(status, size: 12, color: PixelPalette.lightTeal, alignment: .left)
        status.text = "자동 해체 가동 중"
        status.position = CGPoint(x: 24, y: 126)
        status.zPosition = 93
        addChild(status)

        let loadout = SKLabelNode(fontNamed: "AppleSDGothicNeo-Medium")
        configureLabel(loadout, size: 9, color: PixelPalette.workWhite, alignment: .left)
        loadout.text = "절단기 LV.1  •  리벳 지원  •  자석 회수"
        loadout.position = CGPoint(x: 24, y: 106)
        loadout.zPosition = 93
        addChild(loadout)

        addBlock(size: CGSize(width: 184, height: 14), color: PixelPalette.ink, position: CGPoint(x: 22, y: 70), z: 92)
        for index in 0..<8 {
            addBlock(
                size: CGSize(width: 16, height: 6),
                color: index.isMultiple(of: 2) ? PixelPalette.midIron : PixelPalette.darkIron,
                position: CGPoint(x: 28 + index * 21, y: 74),
                z: 93
            )
        }
        for (index, speed) in ["1X", "2X", "3X"].enumerated() {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            configureLabel(label, size: 9, color: index == 0 ? PixelPalette.warningAmber : PixelPalette.midIron, alignment: .center)
            label.text = speed
            label.position = CGPoint(x: 48 + index * 50, y: 40)
            label.zPosition = 93
            addChild(label)
        }

        let overclockPanel = PixelArt.panel(size: CGSize(width: 112, height: 112), name: "overclock")
        overclockButton.name = "overclock"
        overclockButton.position = CGPoint(x: 226, y: 24)
        overclockButton.zPosition = 94
        overclockButton.addChild(overclockPanel)

        let bolt = PixelArt.sprite(blocks: [
            .init(x: 50, y: 52, width: 12, height: 34, color: PixelPalette.warningAmber),
            .init(x: 38, y: 44, width: 24, height: 12, color: PixelPalette.warningAmber),
            .init(x: 38, y: 26, width: 12, height: 22, color: PixelPalette.warningAmber)
        ], name: "overclock")
        overclockButton.addChild(bolt)

        let overclockLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(overclockLabel, size: 10, color: PixelPalette.workWhite, alignment: .center)
        overclockLabel.text = "과부하"
        overclockLabel.position = CGPoint(x: 56, y: 94)
        overclockLabel.name = "overclock"
        overclockButton.addChild(overclockLabel)

        overclockFill.anchorPoint = .zero
        overclockFill.position = CGPoint(x: 25, y: 14)
        overclockFill.name = "overclock"
        overclockButton.addChild(overclockFill)
        addChild(overclockButton)
    }

    private func configureEnemyMotion(_ enemyID: String) {
        let points: [Int]
        let duration: TimeInterval
        switch enemyID {
        case "fan_bat":
            points = [0, 4, 0, -4]
            duration = 0.09
        case "cancrab_king":
            points = [0, 1, 0, -1]
            duration = 0.18
        default:
            points = [0, 2, 0, -2]
            duration = 0.13
        }
        enemyAnchor.run(stepLoop(points: points, duration: duration), withKey: "locomotion")
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

    private func playMechanicAttack() {
        mechanicMotion.removeAction(forKey: "attack")
        mechanicMotion.run(.sequence([
            .moveTo(x: 2, duration: 0), .wait(forDuration: 0.05),
            .moveTo(x: 7, duration: 0), .wait(forDuration: 0.05),
            .moveTo(x: 4, duration: 0), .wait(forDuration: 0.05),
            .moveTo(x: 0, duration: 0)
        ]), withKey: "attack")
    }

    private func playDroneAttack() {
        droneMotion.removeAction(forKey: "attack")
        droneMotion.run(.sequence([
            .moveTo(x: 3, duration: 0), .wait(forDuration: 0.05),
            .moveTo(x: -2, duration: 0), .wait(forDuration: 0.05),
            .moveTo(x: 0, duration: 0)
        ]), withKey: "attack")
    }

    private func playEnemyHit() {
        guard let enemyArt else { return }
        enemyArt.removeAction(forKey: "hit")
        enemyArt.color = PixelPalette.workWhite
        enemyArt.run(.sequence([
            .group([.moveTo(x: 5, duration: 0), .colorize(withColorBlendFactor: 0.9, duration: 0)]),
            .wait(forDuration: 0.05),
            .group([.moveTo(x: -3, duration: 0), .colorize(withColorBlendFactor: 0, duration: 0)]),
            .wait(forDuration: 0.05),
            .moveTo(x: 0, duration: 0)
        ]), withKey: "hit")
    }

    private func spawnProjectile(from source: CGPoint, critical: Bool) {
        let color = critical ? PixelPalette.warningAmber : PixelPalette.lightTeal
        let projectile = SKSpriteNode(color: color, size: CGSize(width: critical ? 10 : 6, height: critical ? 5 : 3))
        projectile.position = source
        projectile.zPosition = 32
        addChild(projectile)
        let target = CGPoint(x: 252, y: 294)
        let points = [
            CGPoint(x: source.x + 34, y: source.y + 10),
            CGPoint(x: source.x + 78, y: source.y + 4),
            target
        ]
        var actions: [SKAction] = points.flatMap { point in [.move(to: point, duration: 0), .wait(forDuration: 0.035)] }
        actions.append(.removeFromParent())
        projectile.run(.sequence(actions))
    }

    private func spawnScrapBurst() {
        for index in 0..<10 {
            let scrap = SKSpriteNode(
                color: index.isMultiple(of: 3) ? PixelPalette.warningAmber : PixelPalette.lightIron,
                size: CGSize(width: 3 + index % 3, height: 3 + (index + 1) % 2)
            )
            scrap.position = CGPoint(x: 276 + (index % 5) * 3, y: 286 + (index / 5) * 5)
            scrapLayer.addChild(scrap)
            let points = [
                CGPoint(x: 242 - index, y: 330 + (index % 3) * 7),
                CGPoint(x: 186 - index * 2, y: 392),
                CGPoint(x: 132, y: 420)
            ]
            var actions: [SKAction] = points.flatMap { point in [.move(to: point, duration: 0), .wait(forDuration: 0.055)] }
            actions.append(.removeFromParent())
            scrap.run(.sequence(actions))
        }
    }

    private func updateHUD() {
        let stage = content.stages[stageIndex]
        stageLabel.text = "R1 • \(String(format: "%02d", stage.number))"
        currencyLabel.text = "고철 \(credits)  부품 \(parts)"
        let ratio = CGFloat(max(0, enemyHP)) / CGFloat(max(1, enemyMaxHP))
        hpFill.size.width = floor(116 * ratio)
        let charge = combatTick >= overclockUntilTick ? 1 : CGFloat(max(0, overclockUntilTick - combatTick)) / 160
        overclockFill.size.width = floor(62 * charge)
        if combatTick >= overclockUntilTick { overclockFill.color = PixelPalette.warningAmber }
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

    private func configureLabel(
        _ label: SKLabelNode,
        size: CGFloat,
        color: SKColor,
        alignment: SKLabelHorizontalAlignmentMode
    ) {
        label.fontSize = size
        label.fontColor = color
        label.horizontalAlignmentMode = alignment
        label.verticalAlignmentMode = .center
    }

    private func snapToPixelGrid(_ node: SKNode) {
        for child in node.children {
            child.position = CGPoint(x: child.position.x.rounded(), y: child.position.y.rounded())
            snapToPixelGrid(child)
        }
    }
}

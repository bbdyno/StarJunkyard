import SpriteKit

@MainActor
final class CombatScene: SKScene {
    static let logicalSize = CGSize(width: 360, height: 800)

    var onAccessibilitySummary: ((String) -> Void)?
    var onSave: ((GameSave) -> Void)?
    var onReturnToSaveSelection: (() -> Void)?

    private let content: VerticalSliceContent
    private let enemyByID: [String: VerticalSliceContent.Enemy]
    private var save: GameSave
    private var stageIndex: Int
    private var waveIndex: Int
    private var enemyHP = 0
    private var enemyMaxHP = 1
    private var restoredEnemyHP: Int?
    private var combatTick: Int
    private var nextPlayerAttackTick = 1
    private var nextDroneAttackTick = 1
    private var overclockUntilTick = 0
    private var credits: Int
    private var parts: Int
    private var cutterLevel: Int
    private var droneLevel: Int
    private var magnetLevel: Int
    private var tutorialStep: Int
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
    private let loadoutLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Medium")
    private let tutorialLayer = SKNode()
    private let tutorialLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let shopLayer = SKNode()
    private let shopStatusLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")

    convenience init(content: VerticalSliceContent) {
        self.init(content: content, save: .newGame())
    }

    init(content: VerticalSliceContent, save: GameSave) {
        self.content = content
        self.enemyByID = Dictionary(uniqueKeysWithValues: content.enemies.map { ($0.id, $0) })
        self.save = save
        stageIndex = min(max(0, save.stageIndex), max(0, content.stages.count - 1))
        let waveCount = content.stages[stageIndex].wave.count
        waveIndex = min(max(0, save.waveIndex), max(0, waveCount - 1))
        restoredEnemyHP = save.enemyHP
        combatTick = max(0, save.combatTick)
        credits = max(0, save.credits)
        parts = max(0, save.parts)
        cutterLevel = max(1, save.cutterLevel)
        droneLevel = max(1, save.droneLevel)
        magnetLevel = max(1, save.magnetLevel)
        tutorialStep = max(0, save.tutorialStep)
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
        buildTutorial()
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
        let names = Set(nodes(at: point).compactMap(\.name))
        if !shopLayer.isHidden {
            if names.contains("buy_cutter") { buy(.cutter) }
            else if names.contains("buy_drone") { buy(.drone) }
            else if names.contains("buy_magnet") { buy(.magnet) }
            else if names.contains("shop_close") { closeShop() }
            return
        }
        if names.contains("overclock") {
            activateOverclock()
        } else if names.contains("shop_open") {
            openShop()
        } else if names.contains("save_menu") {
            persist()
            onReturnToSaveSelection?()
        } else if names.contains("tutorial_help") {
            tutorialStep = 0
            refreshTutorial()
        }
    }

    private func simulateTick() {
        guard enemyHP > 0 else { return }
        combatTick += 1

        if tutorialStep == 0 && combatTick >= max(24, save.combatTick + 24) {
            tutorialStep = 1
            refreshTutorial()
            persist()
        }

        if combatTick >= nextPlayerAttackTick {
            let interval = combatTick < overclockUntilTick ? 15 : 24
            nextPlayerAttackTick = combatTick + interval
            playMechanicAttack()
            fireDamage(
                base: content.player.baseDamage * 3 + (cutterLevel - 1) * 6,
                source: CGPoint(x: 126, y: 304),
                steps: 6
            )
        }
        if combatTick >= nextDroneAttackTick {
            nextDroneAttackTick = combatTick + 20
            playDroneAttack()
            fireDamage(
                base: content.drones[0].baseDamage * 2 + (droneLevel - 1) * 4,
                source: CGPoint(x: 150, y: 420),
                steps: 5
            )
        }

        if combatTick.isMultiple(of: 100) {
            let stage = content.stages[stageIndex]
            let enemyName = currentEnemy.map(\.nameKo) ?? "없음"
            onAccessibilitySummary?("전투 화면. 스테이지 \(stage.number). \(enemyName) 내구도 \(max(0, enemyHP)) / \(enemyMaxHP). 과부하 버튼 사용 가능.")
        }
        updateHUD()
        if combatTick.isMultiple(of: 200) { persist() }
    }

    private func fireDamage(base: Int, source: CGPoint, steps: Int) {
        let critical = rng.bounded(1_000_000) < UInt32(content.player.criticalChancePpm)
        let damage = critical ? base * content.player.criticalDamagePpm / 1_000_000 : base
        let targetStage = stageIndex
        let targetWave = waveIndex
        spawnProjectile(from: source, critical: critical, steps: steps) { [weak self] in
            guard let self, self.stageIndex == targetStage, self.waveIndex == targetWave else { return }
            self.applyDamage(damage)
        }
    }

    private func applyDamage(_ damage: Int) {
        guard enemyHP > 0 else { return }
        enemyHP -= damage
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
        enemyHP = min(enemyMaxHP, max(1, restoredEnemyHP ?? enemyMaxHP))
        restoredEnemyHP = nil
        updateHUD()
    }

    private func dismantleCurrentEnemy() {
        guard let enemy = currentEnemy else { return }
        let stage = content.stages[stageIndex]
        credits += stage.baseReward * stage.rewardMultiplierPpm / 1_000_000
        let baseParts = enemy.enemyClass == "boss" ? 15 : (enemy.enemyClass == "elite" ? 6 : 3)
        parts += baseParts + magnetLevel - 1
        spawnScrapBurst()
        enemyAnchor.removeAllActions()
        enemyAnchor.removeAllChildren()
        waveIndex += 1
        if waveIndex >= stage.wave.count {
            stageIndex = (stageIndex + 1) % content.stages.count
            waveIndex = 0
            rng = PCG32(seed: UInt64(content.stages[stageIndex].number), stream: 54)
        }
        if tutorialStep == 2 && credits >= cutterCost {
            tutorialStep = 3
            refreshTutorial()
        }
        persist()
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
        if tutorialStep == 1 {
            tutorialStep = credits >= cutterCost ? 3 : 2
            refreshTutorial()
        }
        persist()
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

        let saveMenu = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(saveMenu, size: 8, color: PixelPalette.warningAmber, alignment: .right)
        saveMenu.text = "저장/나가기"
        saveMenu.position = CGPoint(x: 342, y: 742)
        saveMenu.zPosition = 103
        saveMenu.name = "save_menu"
        addChild(saveMenu)

        let help = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(help, size: 8, color: PixelPalette.lightTeal, alignment: .center)
        help.text = "도움"
        help.position = CGPoint(x: 250, y: 742)
        help.zPosition = 103
        help.name = "tutorial_help"
        addChild(help)

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

        configureLabel(loadoutLabel, size: 9, color: PixelPalette.workWhite, alignment: .left)
        loadoutLabel.position = CGPoint(x: 24, y: 106)
        loadoutLabel.zPosition = 93
        addChild(loadoutLabel)

        let shopButton = PixelArt.panel(size: CGSize(width: 184, height: 58), name: "shop_open")
        shopButton.position = CGPoint(x: 22, y: 24)
        shopButton.zPosition = 94
        shopButton.name = "shop_open"
        addChild(shopButton)

        let shopTitle = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(shopTitle, size: 11, color: PixelPalette.warningAmber, alignment: .left)
        shopTitle.text = "장비 상점"
        shopTitle.position = CGPoint(x: 36, y: 64)
        shopTitle.zPosition = 96
        shopTitle.name = "shop_open"
        addChild(shopTitle)

        let shopHint = SKLabelNode(fontNamed: "AppleSDGothicNeo-Medium")
        configureLabel(shopHint, size: 8, color: PixelPalette.lightTeal, alignment: .left)
        shopHint.text = "고철로 피해·드론·회수 강화"
        shopHint.position = CGPoint(x: 36, y: 43)
        shopHint.zPosition = 96
        shopHint.name = "shop_open"
        addChild(shopHint)

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
        refreshLoadout()
    }

    private func buildTutorial() {
        tutorialLayer.zPosition = 150
        let panel = PixelArt.panel(size: CGSize(width: 336, height: 72), name: "tutorial_panel")
        panel.position = CGPoint(x: 12, y: 648)
        tutorialLayer.addChild(panel)

        configureLabel(tutorialLabel, size: 10, color: PixelPalette.workWhite, alignment: .center)
        tutorialLabel.position = CGPoint(x: 180, y: 684)
        tutorialLabel.zPosition = 2
        tutorialLayer.addChild(tutorialLabel)
        addChild(tutorialLayer)
        refreshTutorial()

        shopLayer.zPosition = 220
        shopLayer.isHidden = true
        addChild(shopLayer)
    }

    private func refreshTutorial() {
        tutorialLayer.isHidden = false
        switch tutorialStep {
        case 0:
            tutorialLabel.text = "① 모가 자동으로 해체합니다. 첫 공격을 지켜보세요."
        case 1:
            tutorialLabel.text = "② 오른쪽 [과부하]를 눌러 절단 속도를 올리세요."
            overclockButton.run(.repeat(.sequence([.fadeAlpha(to: 0.55, duration: 0.15), .fadeAlpha(to: 1, duration: 0.15)]), count: 4))
        case 2:
            tutorialLabel.text = "③ 첫 고철 10개를 모으면 장비를 살 수 있습니다."
        case 3:
            tutorialLabel.text = "③ [장비 상점]에서 강화 절단날을 구매하세요."
        default:
            tutorialLabel.text = "완료: 자동 해체 → 고철 획득 → 장비 강화 • S10 보스가 목표"
            tutorialLayer.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 0.15), .hide()]))
        }
    }

    private enum ShopItem { case cutter, drone, magnet }

    private var cutterCost: Int { 10 * cutterLevel }
    private var droneCost: Int { 25 * droneLevel }
    private var magnetCost: Int { 15 * magnetLevel }

    private func openShop() {
        shopLayer.removeAllChildren()
        shopLayer.isHidden = false
        let shade = SKSpriteNode(color: PixelPalette.ink.withAlphaComponent(0.82), size: Self.logicalSize)
        shade.anchorPoint = .zero
        shade.name = "shop_close"
        shopLayer.addChild(shade)

        let panel = PixelArt.panel(size: CGSize(width: 328, height: 382), name: "shop_panel")
        panel.position = CGPoint(x: 16, y: 214)
        panel.zPosition = 1
        shopLayer.addChild(panel)

        addShopLabel("폐품 장비 작업대", x: 180, y: 560, size: 16, color: PixelPalette.warningAmber)
        addShopLabel("고철 \(credits)  •  구매 즉시 전투에 적용", x: 180, y: 532, size: 9, color: PixelPalette.lightTeal)
        addShopItem(name: "buy_cutter", title: "강화 절단날 LV.\(cutterLevel + 1)", effect: "모 피해 +6", cost: cutterCost, y: 438)
        addShopItem(name: "buy_drone", title: "리벳 출력 코일 LV.\(droneLevel + 1)", effect: "드론 피해 +4", cost: droneCost, y: 346)
        addShopItem(name: "buy_magnet", title: "자석 바구니 LV.\(magnetLevel + 1)", effect: "적마다 부품 +1", cost: magnetCost, y: 254)

        configureLabel(shopStatusLabel, size: 9, color: PixelPalette.workWhite, alignment: .center)
        shopStatusLabel.text = "아이템을 눌러 구매하세요"
        shopStatusLabel.position = CGPoint(x: 180, y: 230)
        shopStatusLabel.zPosition = 4
        shopLayer.addChild(shopStatusLabel)

        let close = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(close, size: 10, color: PixelPalette.lightIron, alignment: .right)
        close.text = "닫기 ×"
        close.position = CGPoint(x: 326, y: 574)
        close.zPosition = 4
        close.name = "shop_close"
        shopLayer.addChild(close)
    }

    private func addShopItem(name: String, title: String, effect: String, cost: Int, y: Int) {
        let button = PixelArt.panel(size: CGSize(width: 292, height: 78), name: name)
        button.position = CGPoint(x: 34, y: y)
        button.zPosition = 2
        button.name = name
        shopLayer.addChild(button)
        addShopLabel(title, x: 50, y: y + 53, size: 11, color: PixelPalette.workWhite, name: name, alignment: .left)
        addShopLabel(effect, x: 50, y: y + 27, size: 9, color: PixelPalette.lightTeal, name: name, alignment: .left)
        addShopLabel("고철 \(cost)", x: 308, y: y + 39, size: 10, color: credits >= cost ? PixelPalette.warningAmber : PixelPalette.midIron, name: name, alignment: .right)
    }

    private func addShopLabel(
        _ text: String,
        x: Int,
        y: Int,
        size: CGFloat,
        color: SKColor,
        name: String? = nil,
        alignment: SKLabelHorizontalAlignmentMode = .center
    ) {
        let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(label, size: size, color: color, alignment: alignment)
        label.text = text
        label.position = CGPoint(x: x, y: y)
        label.zPosition = 4
        label.name = name
        shopLayer.addChild(label)
    }

    private func buy(_ item: ShopItem) {
        let cost: Int
        switch item {
        case .cutter: cost = cutterCost
        case .drone: cost = droneCost
        case .magnet: cost = magnetCost
        }
        guard credits >= cost else {
            shopStatusLabel.text = "고철이 부족합니다 • 적을 더 해체하세요"
            shopStatusLabel.fontColor = PixelPalette.sparkOrange
            return
        }
        credits -= cost
        switch item {
        case .cutter:
            cutterLevel += 1
            shopStatusLabel.text = "강화 절단날 장착 • 다음 탄부터 피해 증가"
            if tutorialStep == 3 { tutorialStep = 4; refreshTutorial() }
        case .drone:
            droneLevel += 1
            shopStatusLabel.text = "리벳 출력 코일 장착"
        case .magnet:
            magnetLevel += 1
            shopStatusLabel.text = "자석 바구니 장착 • 부품 회수 증가"
        }
        shopStatusLabel.fontColor = PixelPalette.recoveryGreen
        refreshLoadout()
        updateHUD()
        persist()
        run(.sequence([.wait(forDuration: 0.35), .run { [weak self] in self?.openShop() }]))
    }

    private func closeShop() {
        shopLayer.isHidden = true
        shopLayer.removeAllChildren()
    }

    private func refreshLoadout() {
        loadoutLabel.text = "절단날 LV.\(cutterLevel)  •  리벳 LV.\(droneLevel)  •  자석 LV.\(magnetLevel)"
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

    private func spawnProjectile(
        from source: CGPoint,
        critical: Bool,
        steps: Int,
        completion: @escaping () -> Void
    ) {
        let color = critical ? PixelPalette.warningAmber : PixelPalette.lightTeal
        let projectile = SKSpriteNode(color: color, size: CGSize(width: critical ? 10 : 6, height: critical ? 5 : 3))
        projectile.position = source
        projectile.zPosition = 32
        addChild(projectile)
        let target = CGPoint(x: enemyAnchor.position.x - 14, y: enemyAnchor.position.y + 12)
        let delta = CGVector(dx: target.x - source.x, dy: target.y - source.y)
        projectile.zRotation = atan2(delta.dy, delta.dx)
        let points = (1...steps).map { step in
            let ratio = CGFloat(step) / CGFloat(steps)
            return CGPoint(
                x: (source.x + delta.dx * ratio).rounded(),
                y: (source.y + delta.dy * ratio).rounded()
            )
        }
        var actions: [SKAction] = points.flatMap { point in [.move(to: point, duration: 0), .wait(forDuration: 0.05)] }
        actions.append(.run(completion))
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

    private func persist() {
        save.revision += 1
        save.updatedAt = Date()
        save.stageIndex = stageIndex
        save.waveIndex = waveIndex
        save.enemyHP = enemyHP > 0 ? enemyHP : nil
        save.credits = credits
        save.parts = parts
        save.cutterLevel = cutterLevel
        save.droneLevel = droneLevel
        save.magnetLevel = magnetLevel
        save.tutorialStep = tutorialStep
        save.combatTick = combatTick
        save.highestStage = max(save.highestStage, content.stages[stageIndex].number)
        onSave?(save)
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

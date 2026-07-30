import SpriteKit

@MainActor
final class CombatScene: SKScene, AdaptivePixelScene {
    static let logicalSize = PixelViewport.laneSize

    var onAccessibilitySummary: ((String) -> Void)?
    var onSave: ((GameSave) -> Void)?
    var onReturnToSaveSelection: (() -> Void)?

    @MainActor
    private final class ActiveEnemy {
        let token: Int
        let spec: VerticalSliceContent.Enemy
        let maxHP: Int
        var hp: Int
        let root = SKNode()
        let art: SKSpriteNode
        let hpFill = SKSpriteNode(color: PixelPalette.recoveryGreen, size: CGSize(width: 56, height: 4))

        init(token: Int, spec: VerticalSliceContent.Enemy, maxHP: Int, hp: Int, art: SKSpriteNode) {
            self.token = token
            self.spec = spec
            self.maxHP = maxHP
            self.hp = hp
            self.art = art
        }
    }

    private let content: VerticalSliceContent
    private let enemyByID: [String: VerticalSliceContent.Enemy]
    private var save: GameSave
    private var stageIndex: Int
    private var waveIndex: Int
    private var restoredEnemyHPs: [Int]?
    private var activeEnemies: [ActiveEnemy] = []
    private var nextEnemyToken = 1
    private var groupTransitioning = false
    private var combatTick: Int
    private var nextPlayerAttackTick: Int
    private var nextDroneAttackTick: Int
    private var nextCrewAttackTick: Int
    private var overclockUntilTick = 0
    private var credits: Int
    private var parts: Int
    private var cutterLevel: Int
    private var droneLevel: Int
    private var magnetLevel: Int
    private var crewLevel: Int
    private var tutorialStep: Int
    private var accumulator: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var rng = PCG32(seed: 42, stream: 54)
    private var viewport = PixelViewport.phoneFallback

    private let backdrop = SKSpriteNode(color: PixelPalette.deepNavy, size: logicalSize)
    private let laneRoot = SKNode()
    private let combatLayer = SKNode()
    private let hudLayer = SKNode()
    private let controlsLayer = SKNode()
    private let adaptiveRailLayer = SKNode()
    private let mechanicAnchor = SKNode()
    private let mechanicMotion = SKNode()
    private let droneAnchor = SKNode()
    private let droneMotion = SKNode()
    private let crewAnchor = SKNode()
    private let crewMotion = SKNode()
    private let enemyLayer = SKNode()
    private let effectsLayer = SKNode()
    private let rainLayer = SKNode()
    private let stageLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let locationLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let currencyLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let groupLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
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
        enemyByID = Dictionary(uniqueKeysWithValues: content.enemies.map { ($0.id, $0) })
        self.save = save
        stageIndex = min(max(0, save.stageIndex), max(0, content.stages.count - 1))
        let waveCount = content.stages[stageIndex].wave.count
        waveIndex = min(max(0, save.waveIndex), max(0, waveCount - 1))
        restoredEnemyHPs = save.enemyHPs ?? save.enemyHP.map { [$0] }
        combatTick = max(0, save.combatTick)
        nextPlayerAttackTick = combatTick + 1
        nextDroneAttackTick = combatTick + 8
        nextCrewAttackTick = combatTick + 15
        credits = max(0, save.credits)
        parts = max(0, save.parts)
        cutterLevel = max(1, save.cutterLevel)
        droneLevel = max(1, save.droneLevel)
        magnetLevel = max(1, save.magnetLevel)
        crewLevel = max(1, save.crewLevel)
        tutorialStep = max(0, save.tutorialStep)
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
        [laneRoot, combatLayer, hudLayer, controlsLayer, adaptiveRailLayer, mechanicAnchor,
         mechanicMotion, droneAnchor, droneMotion, crewAnchor, crewMotion, enemyLayer,
         effectsLayer, rainLayer, tutorialLayer, shopLayer].forEach { $0.removeAllChildren() }
        backdrop.zPosition = -1_000
        addChild(backdrop)
        addChild(laneRoot)
        laneRoot.addChild(combatLayer)
        laneRoot.addChild(hudLayer)
        laneRoot.addChild(controlsLayer)
        laneRoot.addChild(tutorialLayer)
        laneRoot.addChild(shopLayer)
        addChild(adaptiveRailLayer)
        buildBackground()
        buildCombatants()
        buildHUD()
        buildControls()
        buildTutorial()
        spawnCurrentGroup()
        applyViewport(PixelViewport(view: view))
        setLowPowerMode(ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    func applyViewport(_ viewport: PixelViewport) {
        self.viewport = viewport
        size = viewport.sceneSize
        laneRoot.position = viewport.laneFrame.origin
        backdrop.anchorPoint = .zero
        backdrop.position = .zero
        backdrop.size = viewport.sceneSize

        let localSafeBottom = viewport.safeFrame.minY - viewport.laneFrame.minY
        let localSafeTop = viewport.safeFrame.maxY - viewport.laneFrame.minY
        controlsLayer.position.y = max(0, ceil(localSafeBottom))
        let topShift = min(0, floor(localSafeTop - 792))
        hudLayer.position.y = topShift
        tutorialLayer.position.y = topShift
        rebuildAdaptiveRails()
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
            else if names.contains("buy_crew") { buy(.crew) }
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
        guard !groupTransitioning, currentTarget != nil else { return }
        combatTick += 1

        if tutorialStep == 0 && combatTick >= max(24, save.combatTick + 24) {
            tutorialStep = 1
            refreshTutorial()
            persist()
        }

        if combatTick.isMultiple(of: 120) {
            playMechanicAttack()
            playCrewAttack()
            performCooperativeSweep()
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
        if combatTick >= nextCrewAttackTick {
            nextCrewAttackTick = combatTick + 30
            playCrewAttack()
            fireDamage(
                base: 5 + (crewLevel - 1) * 5,
                source: CGPoint(x: 72, y: 248),
                steps: 7,
                color: PixelPalette.sparkOrange
            )
        }

        if combatTick.isMultiple(of: 100) {
            let stage = content.stages[stageIndex]
            let remaining = activeEnemies.filter { $0.hp > 0 }
            let names = remaining.map { $0.spec.nameKo }.joined(separator: ", ")
            let durability = remaining.reduce(0) { $0 + $1.hp }
            onAccessibilitySummary?("전투 화면. 스테이지 \(stage.number). 적 \(remaining.count)체 \(names). 남은 내구도 \(durability). 보라 직원이 협동 공격 중입니다.")
        }
        updateHUD()
        if combatTick.isMultiple(of: 200) { persist() }
    }

    private var currentTarget: ActiveEnemy? {
        activeEnemies.first { $0.hp > 0 }
    }

    private func fireDamage(
        base: Int,
        source: CGPoint,
        steps: Int,
        color: SKColor? = nil
    ) {
        guard let target = currentTarget else { return }
        let critical = rng.bounded(1_000_000) < UInt32(content.player.criticalChancePpm)
        let damage = critical ? base * content.player.criticalDamagePpm / 1_000_000 : base
        let token = target.token
        spawnProjectile(from: source, to: target.root.position, critical: critical, color: color, steps: steps) { [weak self] in
            self?.applyDamage(damage, to: token)
        }
    }

    private func applyDamage(_ damage: Int, to token: Int) {
        guard !groupTransitioning,
              let enemy = activeEnemies.first(where: { $0.token == token }),
              enemy.hp > 0
        else { return }
        enemy.hp = max(0, enemy.hp - damage)
        playEnemyHit(enemy)
        updateEnemyHUD(enemy)
        if enemy.hp == 0 { dismantle(enemy) }
    }

    private func spawnCurrentGroup() {
        groupTransitioning = false
        enemyLayer.removeAllChildren()
        activeEnemies.removeAll()
        guard !content.stages.isEmpty else { return }
        let stage = content.stages[stageIndex]
        guard waveIndex < stage.wave.count, let first = enemyByID[stage.wave[waveIndex]] else { return }

        var specs: [VerticalSliceContent.Enemy] = [first]
        if first.enemyClass == "normal" {
            for index in (waveIndex + 1)..<min(stage.wave.count, waveIndex + 3) {
                guard let candidate = enemyByID[stage.wave[index]], candidate.enemyClass == "normal" else { break }
                specs.append(candidate)
            }
        }
        let positions: [CGPoint]
        switch specs.count {
        case 1: positions = [CGPoint(x: 276, y: 292)]
        case 2: positions = [CGPoint(x: 246, y: 320), CGPoint(x: 304, y: 270)]
        default: positions = [CGPoint(x: 224, y: 334), CGPoint(x: 272, y: 292), CGPoint(x: 320, y: 250)]
        }

        for (index, spec) in specs.enumerated() {
            let maxHP = max(1, stage.baseHp * spec.hpMultiplierPpm / 1_000_000)
            let restored = restoredEnemyHPs.flatMap { index < $0.count ? $0[index] : nil }
            let hp = min(maxHP, max(0, restored ?? maxHP))
            let scale: CGFloat = spec.id == "can_bug" ? 2 : 1
            let art = PixelArt.asset(spec.spriteId, scale: scale)
            let enemy = ActiveEnemy(token: nextEnemyToken, spec: spec, maxHP: maxHP, hp: hp, art: art)
            nextEnemyToken += 1
            enemy.root.name = "enemy_slot_\(index)"
            enemy.root.position = positions[index]
            enemy.root.zPosition = CGFloat(24 + (specs.count - index))
            art.zPosition = 2
            enemy.root.addChild(art)

            let name = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
            configureLabel(name, size: 7, color: PixelPalette.workWhite, alignment: .center)
            name.text = spec.nameKo
            name.position = CGPoint(x: 0, y: 54)
            name.zPosition = 5
            enemy.root.addChild(name)

            let hpBack = SKSpriteNode(color: PixelPalette.ink, size: CGSize(width: 60, height: 8))
            hpBack.position = CGPoint(x: 0, y: 43)
            hpBack.zPosition = 4
            enemy.root.addChild(hpBack)
            enemy.hpFill.anchorPoint = CGPoint(x: 0, y: 0.5)
            enemy.hpFill.position = CGPoint(x: -28, y: 43)
            enemy.hpFill.zPosition = 5
            enemy.root.addChild(enemy.hpFill)
            if hp == 0 { enemy.root.isHidden = true }
            enemy.root.run(enemyMotion(spec.id), withKey: "locomotion")
            enemyLayer.addChild(enemy.root)
            activeEnemies.append(enemy)
            updateEnemyHUD(enemy)
        }
        restoredEnemyHPs = nil
        updateHUD()
        rebuildAdaptiveRails()
    }

    private func dismantle(_ enemy: ActiveEnemy) {
        let stage = content.stages[stageIndex]
        credits += stage.baseReward * stage.rewardMultiplierPpm / 1_000_000
        let baseParts = enemy.spec.enemyClass == "boss" ? 15 : (enemy.spec.enemyClass == "elite" ? 6 : 3)
        parts += baseParts + magnetLevel - 1
        spawnScrapBurst(at: enemy.root.position)
        enemy.root.removeAllActions()
        enemy.root.run(.sequence([.fadeOut(withDuration: 0.14), .hide()]))

        guard activeEnemies.allSatisfy({ $0.hp == 0 }) else {
            persist()
            updateHUD()
            rebuildAdaptiveRails()
            return
        }

        groupTransitioning = true
        waveIndex += activeEnemies.count
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
            .wait(forDuration: 0.42),
            .run { [weak self] in self?.spawnCurrentGroup() }
        ]))
    }

    private func performCooperativeSweep() {
        let tokens = activeEnemies.filter { $0.hp > 0 }.map(\.token)
        guard !tokens.isEmpty else { return }
        let banner = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(banner, size: 13, color: PixelPalette.warningAmber, alignment: .center)
        banner.text = "모 × 보라  협동 해체!"
        banner.position = CGPoint(x: 180, y: 468)
        banner.zPosition = 80
        effectsLayer.addChild(banner)
        banner.run(.sequence([
            .moveBy(x: 0, y: 8, duration: 0.12),
            .wait(forDuration: 0.18),
            .fadeOut(withDuration: 0.12),
            .removeFromParent()
        ]))
        for index in 0..<6 {
            let slash = SKSpriteNode(color: index.isMultiple(of: 2) ? PixelPalette.warningAmber : PixelPalette.lightTeal, size: CGSize(width: 30, height: 3))
            slash.position = CGPoint(x: 116 - index * 7, y: 250 + index * 20)
            slash.zPosition = 70
            effectsLayer.addChild(slash)
            slash.run(.sequence([
                .moveBy(x: 210, y: 0, duration: 0.26),
                .removeFromParent()
            ]))
        }
        let damage = 8 + cutterLevel * 2 + crewLevel * 4
        run(.sequence([
            .wait(forDuration: 0.26),
            .run { [weak self] in tokens.forEach { self?.applyDamage(damage, to: $0) } }
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
        addBlock(size: Self.logicalSize, color: PixelPalette.deepNavy, position: .zero, z: -120, to: combatLayer)
        let yard = PixelArt.asset("background_r01_back_alley")
        yard.position = CGPoint(x: 180, y: 446)
        yard.zPosition = -110
        combatLayer.addChild(yard)

        combatLayer.addChild(rainLayer)
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
        mechanicAnchor.position = CGPoint(x: 88, y: 304)
        mechanicAnchor.zPosition = 30
        mechanicMotion.addChild(PixelArt.asset(content.player.spriteId, scale: 2))
        mechanicAnchor.addChild(mechanicMotion)
        mechanicAnchor.run(stepLoop(points: [0, 1, 0, -1], duration: 0.14), withKey: "idle")
        combatLayer.addChild(mechanicAnchor)

        crewAnchor.position = CGPoint(x: 48, y: 238)
        crewAnchor.zPosition = 29
        crewMotion.addChild(PixelArt.asset("crew_bora_base", scale: 2))
        crewAnchor.addChild(crewMotion)
        crewAnchor.run(stepLoop(points: [0, 1, 0, -1], duration: 0.17), withKey: "idle")
        combatLayer.addChild(crewAnchor)

        droneAnchor.position = CGPoint(x: 128, y: 420)
        droneAnchor.zPosition = 34
        droneMotion.addChild(PixelArt.asset(content.drones[0].spriteId))
        droneAnchor.addChild(droneMotion)
        droneAnchor.run(stepLoop(points: [0, 2, 0, -2], duration: 0.11), withKey: "hover")
        combatLayer.addChild(droneAnchor)

        enemyLayer.zPosition = 20
        effectsLayer.zPosition = 50
        combatLayer.addChild(enemyLayer)
        combatLayer.addChild(effectsLayer)
    }

    private func buildHUD() {
        let hud = PixelArt.panel(size: CGSize(width: 344, height: 62), name: "hud_panel")
        hud.position = CGPoint(x: 8, y: 730)
        hud.zPosition = 100
        hudLayer.addChild(hud)

        configureLabel(stageLabel, size: 12, color: PixelPalette.workWhite, alignment: .left)
        stageLabel.position = CGPoint(x: 18, y: 764)
        stageLabel.zPosition = 101
        hudLayer.addChild(stageLabel)

        configureLabel(locationLabel, size: 8, color: PixelPalette.lightTeal, alignment: .left)
        locationLabel.text = "뒷골목 압착장"
        locationLabel.position = CGPoint(x: 18, y: 742)
        locationLabel.zPosition = 101
        hudLayer.addChild(locationLabel)

        configureLabel(currencyLabel, size: 9, color: PixelPalette.warningAmber, alignment: .right)
        currencyLabel.position = CGPoint(x: 342, y: 764)
        currencyLabel.zPosition = 101
        hudLayer.addChild(currencyLabel)

        let saveMenu = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(saveMenu, size: 8, color: PixelPalette.warningAmber, alignment: .right)
        saveMenu.text = "저장/나가기"
        saveMenu.position = CGPoint(x: 342, y: 742)
        saveMenu.zPosition = 103
        saveMenu.name = "save_menu"
        hudLayer.addChild(saveMenu)

        let help = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(help, size: 8, color: PixelPalette.lightTeal, alignment: .center)
        help.text = "도움"
        help.position = CGPoint(x: 250, y: 742)
        help.zPosition = 103
        help.name = "tutorial_help"
        hudLayer.addChild(help)

        configureLabel(groupLabel, size: 10, color: PixelPalette.workWhite, alignment: .center)
        groupLabel.position = CGPoint(x: 272, y: 410)
        groupLabel.zPosition = 44
        combatLayer.addChild(groupLabel)
    }

    private func buildControls() {
        addBlock(size: CGSize(width: 360, height: 160), color: PixelPalette.ink, position: .zero, z: 85, to: controlsLayer)
        let panel = PixelArt.panel(size: CGSize(width: 344, height: 144), name: "workshop_console")
        panel.position = CGPoint(x: 8, y: 8)
        panel.zPosition = 90
        controlsLayer.addChild(panel)

        let status = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(status, size: 12, color: PixelPalette.lightTeal, alignment: .left)
        status.text = "3인 자동 해체반 가동 중"
        status.position = CGPoint(x: 24, y: 126)
        status.zPosition = 93
        controlsLayer.addChild(status)

        configureLabel(loadoutLabel, size: 8, color: PixelPalette.workWhite, alignment: .left)
        loadoutLabel.position = CGPoint(x: 24, y: 106)
        loadoutLabel.zPosition = 93
        controlsLayer.addChild(loadoutLabel)

        let shopButton = PixelArt.panel(size: CGSize(width: 184, height: 58), name: "shop_open")
        shopButton.position = CGPoint(x: 22, y: 24)
        shopButton.zPosition = 94
        shopButton.name = "shop_open"
        controlsLayer.addChild(shopButton)
        addControlLabel("장비·직원 작업대", x: 36, y: 64, size: 10, color: PixelPalette.warningAmber, name: "shop_open")
        addControlLabel("고철로 공격과 보라를 성장", x: 36, y: 43, size: 8, color: PixelPalette.lightTeal, name: "shop_open")

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
        let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(label, size: 10, color: PixelPalette.workWhite, alignment: .center)
        label.text = "과부하"
        label.position = CGPoint(x: 56, y: 94)
        label.name = "overclock"
        overclockButton.addChild(label)
        overclockFill.anchorPoint = .zero
        overclockFill.position = CGPoint(x: 25, y: 14)
        overclockFill.name = "overclock"
        overclockButton.addChild(overclockFill)
        controlsLayer.addChild(overclockButton)
        refreshLoadout()
    }

    private func addControlLabel(_ text: String, x: Int, y: Int, size: CGFloat, color: SKColor, name: String) {
        let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(label, size: size, color: color, alignment: .left)
        label.text = text
        label.position = CGPoint(x: x, y: y)
        label.zPosition = 96
        label.name = name
        controlsLayer.addChild(label)
    }

    private func buildTutorial() {
        tutorialLayer.zPosition = 150
        let panel = PixelArt.panel(size: CGSize(width: 336, height: 72), name: "tutorial_panel")
        panel.position = CGPoint(x: 12, y: 648)
        tutorialLayer.addChild(panel)
        configureLabel(tutorialLabel, size: 9, color: PixelPalette.workWhite, alignment: .center)
        tutorialLabel.position = CGPoint(x: 180, y: 684)
        tutorialLabel.zPosition = 2
        tutorialLayer.addChild(tutorialLabel)
        refreshTutorial()

        shopLayer.zPosition = 220
        shopLayer.isHidden = true
    }

    private func refreshTutorial() {
        tutorialLayer.isHidden = false
        tutorialLayer.alpha = 1
        switch tutorialStep {
        case 0: tutorialLabel.text = "① 모·리벳·보라가 여러 적을 자동 해체합니다."
        case 1:
            tutorialLabel.text = "② 오른쪽 [과부하]로 공격 속도를 올리세요."
            overclockButton.run(.repeat(.sequence([.fadeAlpha(to: 0.55, duration: 0.15), .fadeAlpha(to: 1, duration: 0.15)]), count: 4))
        case 2: tutorialLabel.text = "③ 고철 10개를 모아 첫 장비를 강화하세요."
        case 3: tutorialLabel.text = "③ [장비·직원 작업대]에서 절단날을 구매하세요."
        default:
            tutorialLabel.text = "완료: 다중 해체 → 고철 획득 → 직원 성장 • S10 보스가 목표"
            tutorialLayer.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 0.15), .hide()]))
        }
    }

    private enum ShopItem { case cutter, drone, magnet, crew }

    private var cutterCost: Int { 10 * cutterLevel }
    private var droneCost: Int { 25 * droneLevel }
    private var magnetCost: Int { 15 * magnetLevel }
    private var crewCost: Int { 30 * crewLevel }

    private func openShop() {
        shopLayer.removeAllChildren()
        shopLayer.isHidden = false
        let shade = SKSpriteNode(color: PixelPalette.ink.withAlphaComponent(0.84), size: Self.logicalSize)
        shade.anchorPoint = .zero
        shade.name = "shop_close"
        shopLayer.addChild(shade)

        let panel = PixelArt.panel(size: CGSize(width: 328, height: 500), name: "shop_panel")
        panel.position = CGPoint(x: 16, y: 150)
        panel.zPosition = 1
        shopLayer.addChild(panel)
        addShopLabel("폐품 장비·직원 작업대", x: 180, y: 616, size: 15, color: PixelPalette.warningAmber)
        addShopLabel("고철 \(credits) • 모두 플레이로 성장", x: 180, y: 590, size: 9, color: PixelPalette.lightTeal)
        addShopItem(name: "buy_cutter", title: "강화 절단날 LV.\(cutterLevel + 1)", effect: "모 피해 +6", cost: cutterCost, y: 500)
        addShopItem(name: "buy_drone", title: "리벳 출력 코일 LV.\(droneLevel + 1)", effect: "드론 피해 +4", cost: droneCost, y: 420)
        addShopItem(name: "buy_magnet", title: "자석 바구니 LV.\(magnetLevel + 1)", effect: "적마다 부품 +1", cost: magnetCost, y: 340)
        addShopItem(name: "buy_crew", title: "보라 작업 숙련 LV.\(crewLevel + 1)", effect: "직원 피해 +5 • 협동 공격 +4", cost: crewCost, y: 260)

        configureLabel(shopStatusLabel, size: 9, color: PixelPalette.workWhite, alignment: .center)
        shopStatusLabel.text = "원하는 성장을 눌러 구매하세요"
        shopStatusLabel.position = CGPoint(x: 180, y: 184)
        shopStatusLabel.zPosition = 4
        shopLayer.addChild(shopStatusLabel)
        let close = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(close, size: 10, color: PixelPalette.lightIron, alignment: .right)
        close.text = "닫기 ×"
        close.position = CGPoint(x: 326, y: 630)
        close.zPosition = 4
        close.name = "shop_close"
        shopLayer.addChild(close)
    }

    private func addShopItem(name: String, title: String, effect: String, cost: Int, y: Int) {
        let button = PixelArt.panel(size: CGSize(width: 292, height: 66), name: name)
        button.position = CGPoint(x: 34, y: y)
        button.zPosition = 2
        button.name = name
        shopLayer.addChild(button)
        addShopLabel(title, x: 50, y: y + 45, size: 10, color: PixelPalette.workWhite, name: name, alignment: .left)
        addShopLabel(effect, x: 50, y: y + 22, size: 8, color: PixelPalette.lightTeal, name: name, alignment: .left)
        addShopLabel("고철 \(cost)", x: 308, y: y + 33, size: 9, color: credits >= cost ? PixelPalette.warningAmber : PixelPalette.midIron, name: name, alignment: .right)
    }

    private func addShopLabel(_ text: String, x: Int, y: Int, size: CGFloat, color: SKColor, name: String? = nil, alignment: SKLabelHorizontalAlignmentMode = .center) {
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
        case .crew: cost = crewCost
        }
        guard credits >= cost else {
            shopStatusLabel.text = "고철이 부족합니다 • 적 무리를 더 해체하세요"
            shopStatusLabel.fontColor = PixelPalette.sparkOrange
            return
        }
        credits -= cost
        switch item {
        case .cutter:
            cutterLevel += 1
            shopStatusLabel.text = "강화 절단날 장착"
            if tutorialStep == 3 { tutorialStep = 4; refreshTutorial() }
        case .drone:
            droneLevel += 1
            shopStatusLabel.text = "리벳 출력 코일 장착"
        case .magnet:
            magnetLevel += 1
            shopStatusLabel.text = "자석 바구니 장착"
        case .crew:
            crewLevel += 1
            shopStatusLabel.text = "보라 숙련 상승 • 개인·협동 피해 증가"
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
        loadoutLabel.text = "절단 \(cutterLevel) • 리벳 \(droneLevel) • 자석 \(magnetLevel) • 보라 \(crewLevel)"
    }

    private func enemyMotion(_ enemyID: String) -> SKAction {
        switch enemyID {
        case "fan_bat": return stepLoop(points: [0, 4, 0, -4], duration: 0.09)
        case "fridge_boar": return stepLoop(points: [0, 1, 0, -1], duration: 0.08)
        case "cancrab_king": return stepLoop(points: [0, 1, 0, -1], duration: 0.18)
        default: return stepLoop(points: [0, 2, 0, -2], duration: 0.13)
        }
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

    private func playCrewAttack() {
        crewMotion.removeAction(forKey: "attack")
        crewMotion.run(.sequence([
            .rotate(toAngle: 0.12, duration: 0), .moveTo(x: 4, duration: 0), .wait(forDuration: 0.06),
            .rotate(toAngle: -0.10, duration: 0), .moveTo(x: 8, duration: 0), .wait(forDuration: 0.06),
            .rotate(toAngle: 0, duration: 0), .moveTo(x: 0, duration: 0)
        ]), withKey: "attack")
    }

    private func playEnemyHit(_ enemy: ActiveEnemy) {
        enemy.art.removeAction(forKey: "hit")
        enemy.art.color = PixelPalette.workWhite
        enemy.art.run(.sequence([
            .group([.moveTo(x: 4, duration: 0), .colorize(withColorBlendFactor: 0.9, duration: 0)]),
            .wait(forDuration: 0.05),
            .group([.moveTo(x: -3, duration: 0), .colorize(withColorBlendFactor: 0, duration: 0)]),
            .wait(forDuration: 0.05),
            .moveTo(x: 0, duration: 0)
        ]), withKey: "hit")
    }

    private func spawnProjectile(from source: CGPoint, to enemyPosition: CGPoint, critical: Bool, color suppliedColor: SKColor?, steps: Int, completion: @escaping () -> Void) {
        let color = suppliedColor ?? (critical ? PixelPalette.warningAmber : PixelPalette.lightTeal)
        let projectile = SKSpriteNode(color: color, size: CGSize(width: critical ? 10 : 7, height: critical ? 5 : 3))
        projectile.position = source
        projectile.zPosition = 62
        effectsLayer.addChild(projectile)
        let target = CGPoint(x: enemyPosition.x - 12, y: enemyPosition.y + 8)
        let delta = CGVector(dx: target.x - source.x, dy: target.y - source.y)
        projectile.zRotation = atan2(delta.dy, delta.dx)
        let points = (1...steps).map { step in
            let ratio = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: (source.x + delta.dx * ratio).rounded(), y: (source.y + delta.dy * ratio).rounded())
        }
        var actions: [SKAction] = points.flatMap { [.move(to: $0, duration: 0), .wait(forDuration: 0.05)] }
        actions.append(.run(completion))
        actions.append(.removeFromParent())
        projectile.run(.sequence(actions))
    }

    private func spawnScrapBurst(at position: CGPoint) {
        for index in 0..<10 {
            let scrap = SKSpriteNode(color: index.isMultiple(of: 3) ? PixelPalette.warningAmber : PixelPalette.lightIron, size: CGSize(width: 3 + index % 3, height: 3 + (index + 1) % 2))
            scrap.position = CGPoint(x: position.x + CGFloat((index % 5) * 3), y: position.y + CGFloat((index / 5) * 5))
            effectsLayer.addChild(scrap)
            let points = [
                CGPoint(x: position.x - 34 - CGFloat(index), y: position.y + 44 + CGFloat((index % 3) * 7)),
                CGPoint(x: 186 - CGFloat(index * 2), y: 392),
                CGPoint(x: 132, y: 420)
            ]
            var actions: [SKAction] = points.flatMap { [.move(to: $0, duration: 0), .wait(forDuration: 0.055)] }
            actions.append(.removeFromParent())
            scrap.run(.sequence(actions))
        }
    }

    private func updateEnemyHUD(_ enemy: ActiveEnemy) {
        let ratio = CGFloat(enemy.hp) / CGFloat(max(1, enemy.maxHP))
        enemy.hpFill.size.width = floor(56 * ratio)
        enemy.hpFill.color = ratio < 0.3 ? PixelPalette.sparkOrange : PixelPalette.recoveryGreen
    }

    private func updateHUD() {
        guard !content.stages.isEmpty else { return }
        let stage = content.stages[stageIndex]
        stageLabel.text = "R1 • \(String(format: "%02d", stage.number))"
        currencyLabel.text = "고철 \(credits)  부품 \(parts)"
        let living = activeEnemies.filter { $0.hp > 0 }
        groupLabel.text = living.count > 1 ? "폐품 괴수 \(living.count)체 동시 출현" : (living.first?.spec.nameKo ?? "다음 무리 탐색")
        let charge = combatTick >= overclockUntilTick ? 1 : CGFloat(max(0, overclockUntilTick - combatTick)) / 160
        overclockFill.size.width = floor(62 * charge)
        if combatTick >= overclockUntilTick { overclockFill.color = PixelPalette.warningAmber }
    }

    private func rebuildAdaptiveRails() {
        adaptiveRailLayer.removeAllChildren()
        guard viewport.usesTabletRails else { return }
        let lane = viewport.laneFrame
        let safe = viewport.safeFrame
        let available = max(96, min(140, lane.minX - safe.minX - 24))
        let leftX = max(safe.minX + 10, lane.minX - available - 12)
        let rightX = min(safe.maxX - available - 10, lane.maxX + 12)
        addRail(name: "ipad_crew_rail", title: "CREW / 직원", x: leftX, width: available, lines: [
            "모  절단 LV.\(cutterLevel)",
            "리벳  출력 LV.\(droneLevel)",
            "보라  숙련 LV.\(crewLevel)",
            "120틱 협동 해체"
        ], accent: PixelPalette.lightTeal)
        let remaining = activeEnemies.filter { $0.hp > 0 }
        addRail(name: "ipad_wave_rail", title: "WAVE / 적 무리", x: rightX, width: available, lines: [
            "현재 \(remaining.count)체",
            remaining.first.map { "표적  \($0.spec.nameKo)" } ?? "다음 무리 탐색",
            "진행  \(waveIndex + 1)/\(content.stages[stageIndex].wave.count)",
            "보상  고철+부품"
        ], accent: PixelPalette.warningAmber)
    }

    private func addRail(name: String, title: String, x: CGFloat, width: CGFloat, lines: [String], accent: SKColor) {
        let panel = PixelArt.panel(size: CGSize(width: floor(width), height: 230), name: name)
        panel.name = name
        panel.position = CGPoint(x: floor(x), y: floor(viewport.safeFrame.midY - 115))
        panel.zPosition = 90
        adaptiveRailLayer.addChild(panel)
        let titleLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        configureLabel(titleLabel, size: 10, color: accent, alignment: .left)
        titleLabel.text = title
        titleLabel.position = CGPoint(x: 12, y: 202)
        titleLabel.zPosition = 2
        panel.addChild(titleLabel)
        for (index, line) in lines.enumerated() {
            let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
            configureLabel(label, size: 8, color: index == 0 ? PixelPalette.workWhite : PixelPalette.lightIron, alignment: .left)
            label.text = line
            label.position = CGPoint(x: 12, y: 164 - index * 32)
            label.zPosition = 2
            panel.addChild(label)
        }
    }

    private func persist() {
        save.schemaVersion = GameSave.currentSchemaVersion
        save.revision += 1
        save.updatedAt = Date()
        save.stageIndex = stageIndex
        save.waveIndex = waveIndex
        let hpValues = groupTransitioning ? nil : activeEnemies.map(\.hp)
        save.enemyHPs = hpValues
        save.enemyHP = hpValues?.first(where: { $0 > 0 })
        save.credits = credits
        save.parts = parts
        save.cutterLevel = cutterLevel
        save.droneLevel = droneLevel
        save.magnetLevel = magnetLevel
        save.crewLevel = crewLevel
        save.tutorialStep = tutorialStep
        save.combatTick = combatTick
        save.highestStage = max(save.highestStage, content.stages[stageIndex].number)
        onSave?(save)
    }

    @discardableResult
    private func addBlock(size: CGSize, color: SKColor, position: CGPoint, z: CGFloat, to parent: SKNode) -> SKSpriteNode {
        let node = SKSpriteNode(color: color, size: size)
        node.anchorPoint = .zero
        node.position = position
        node.zPosition = z
        parent.addChild(node)
        return node
    }

    private func configureLabel(_ label: SKLabelNode, size: CGFloat, color: SKColor, alignment: SKLabelHorizontalAlignmentMode) {
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

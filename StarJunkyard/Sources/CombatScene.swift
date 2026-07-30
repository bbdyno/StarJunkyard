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
    private var pressLevel: Int
    private var sorterLevel: Int
    private var warehouseLevel: Int
    private var yardIncomeBank: Int
    private var manualTapCount: Int
    private var discoveredEnemyIDs: Set<String>
    private var storyChapter: Int
    private var shelterRepairParts: Int
    private var prologueSeen: Bool
    private let offlineSeconds: Int
    private let offlineAmount: Int
    private let showFacilityPanelOnLaunch: Bool
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
    private let storyLayer = SKNode()
    private let storyOverlayLayer = SKNode()
    private let storyGoalTitleLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let storyGoalDetailLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Medium")
    private let storyGoalProgressLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let storyGoalFill = SKSpriteNode(color: PixelPalette.warningAmber, size: CGSize(width: 72, height: 5))
    private let shelterReactor = SKNode()
    private let shelterCore = SKSpriteNode(color: PixelPalette.midIron, size: CGSize(width: 18, height: 18))
    private var shelterLamps: [SKSpriteNode] = []
    private var storyOverlayIsPrologue = false
    private let shopLayer = SKNode()
    private let shopStatusLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")

    private enum ManagementPanel: Equatable {
        case equipment
        case crew
        case facilities
        case records
    }

    convenience init(content: VerticalSliceContent) {
        self.init(content: content, save: .newGame())
    }

    init(content: VerticalSliceContent, save: GameSave, showFacilityPanelOnLaunch: Bool = false) {
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
        pressLevel = max(1, save.pressLevel)
        sorterLevel = max(0, save.sorterLevel)
        warehouseLevel = max(0, save.warehouseLevel)
        manualTapCount = max(0, save.manualTapCount)
        discoveredEnemyIDs = Set(save.discoveredEnemyIDs)
        storyChapter = max(0, save.storyChapter)
        shelterRepairParts = max(0, save.shelterRepairParts)
        prologueSeen = save.prologueSeen
        self.showFacilityPanelOnLaunch = showFacilityPanelOnLaunch
        let offline = YardEconomy.offlineIncome(
            rate: YardEconomy.passiveIncome(
                pressLevel: pressLevel,
                sorterLevel: sorterLevel,
                warehouseLevel: warehouseLevel,
                crewLevel: crewLevel
            ),
            elapsed: Date().timeIntervalSince(save.updatedAt)
        )
        offlineSeconds = offline.seconds
        offlineAmount = offline.amount
        yardIncomeBank = max(0, save.yardIncomeBank) + offline.amount
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
         effectsLayer, rainLayer, tutorialLayer, storyLayer, storyOverlayLayer, shelterReactor,
         shopLayer].forEach { $0.removeAllChildren() }
        shelterLamps.removeAll()
        backdrop.zPosition = -1_000
        addChild(backdrop)
        addChild(laneRoot)
        laneRoot.addChild(combatLayer)
        laneRoot.addChild(hudLayer)
        laneRoot.addChild(controlsLayer)
        laneRoot.addChild(tutorialLayer)
        laneRoot.addChild(storyLayer)
        laneRoot.addChild(shopLayer)
        laneRoot.addChild(storyOverlayLayer)
        storyOverlayLayer.isHidden = true
        addChild(adaptiveRailLayer)
        buildBackground()
        buildCombatants()
        buildHUD()
        buildControls()
        buildStoryGoal()
        buildTutorial()
        spawnCurrentGroup()
        applyViewport(PixelViewport(view: view))
        setLowPowerMode(ProcessInfo.processInfo.isLowPowerModeEnabled)
        if showFacilityPanelOnLaunch {
            openFacilities(status: offlineReportText)
        } else if !prologueSeen {
            openPrologue()
        } else if offlineSeconds >= 60 && offlineAmount > 0 {
            openFacilities(status: offlineReportText)
        }
        persist()
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
        storyLayer.position.y = topShift
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
        if !storyOverlayLayer.isHidden {
            if names.contains("story_continue") || names.contains("story_close") {
                closeStoryOverlay()
            }
            return
        }
        if !shopLayer.isHidden {
            if names.contains("buy_cutter") { buy(.cutter) }
            else if names.contains("buy_drone") { buy(.drone) }
            else if names.contains("buy_magnet") { buy(.magnet) }
            else if names.contains("buy_crew") { buy(.crew) }
            else if names.contains("buy_press") { buyFacility(.press) }
            else if names.contains("buy_sorter") { buyFacility(.sorter) }
            else if names.contains("buy_warehouse") { buyFacility(.warehouse) }
            else if names.contains("collect_yard_income") { collectYardIncome() }
            else if names.contains("management_equipment") { openShop() }
            else if names.contains("management_crew") { openCrew() }
            else if names.contains("management_facilities") { openFacilities() }
            else if names.contains("management_records") { openRecords() }
            else if names.contains("shop_close") { closeShop() }
            return
        }
        if let manualName = names.first(where: { $0.hasPrefix("manual_salvage_") }),
           let token = Int(manualName.replacingOccurrences(of: "manual_salvage_", with: "")) {
            manualSalvage(token: token)
        } else if names.contains("overclock") {
            activateOverclock()
        } else if names.contains("shop_open") {
            openShop()
        } else if names.contains("crew_open") {
            openCrew()
        } else if names.contains("facility_open") {
            openFacilities()
        } else if names.contains("records_open") {
            openRecords()
        } else if names.contains("story_goal") {
            openStoryBrief()
        } else if names.contains("save_menu") {
            persist()
            onReturnToSaveSelection?()
        } else if names.contains("tutorial_help") {
            tutorialStep = 0
            refreshTutorial()
        }
    }

    private func simulateTick() {
        guard storyOverlayLayer.isHidden else { return }
        combatTick += 1
        if combatTick.isMultiple(of: 20) {
            yardIncomeBank += passiveIncomeRate
            updateHUD()
        }
        guard !groupTransitioning, currentTarget != nil else {
            if combatTick.isMultiple(of: 200) { persist() }
            return
        }

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
            let goal = ShelterRecovery.goal(deliveredParts: shelterRepairParts, highestStage: max(save.highestStage, stage.number))
            onAccessibilitySummary?("전투 화면. 스테이지 \(stage.number). 적 \(remaining.count)체 \(names). 남은 내구도 \(durability). 현재 목표 \(goal.title) \(goal.current)/\(goal.required). 보라 직원이 협동 공격 중입니다.")
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

    private var manualDamage: Int {
        YardEconomy.manualDamage(cutterLevel: cutterLevel)
    }

    private var manualReward: Int {
        YardEconomy.manualReward(cutterLevel: cutterLevel)
    }

    private var passiveIncomeRate: Int {
        YardEconomy.passiveIncome(
            pressLevel: pressLevel,
            sorterLevel: sorterLevel,
            warehouseLevel: warehouseLevel,
            crewLevel: crewLevel
        )
    }

    private var offlineReportText: String {
        guard offlineAmount > 0 else { return "시설은 전투 중에도 매초 고철을 쌓습니다" }
        let minutes = max(1, offlineSeconds / 60)
        return "부재 " + String(minutes) + "분 • +" + String(offlineAmount) + " 고철 적립 완료"
    }

    private func manualSalvage(token: Int) {
        guard let enemy = activeEnemies.first(where: { $0.token == token }), enemy.hp > 0 else { return }
        credits += manualReward
        manualTapCount += 1
        playMechanicAttack()
        let feedback = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(feedback, size: 10, color: PixelPalette.warningAmber, alignment: .center)
        feedback.text = "직접 해체  -" + String(manualDamage) + "  +" + String(manualReward)
        feedback.position = CGPoint(x: enemy.root.position.x, y: enemy.root.position.y + 78)
        feedback.zPosition = 90
        effectsLayer.addChild(feedback)
        feedback.run(.sequence([
            .moveBy(x: 0, y: 12, duration: 0.12),
            .wait(forDuration: 0.12),
            .fadeOut(withDuration: 0.10),
            .removeFromParent()
        ]))
        applyDamage(manualDamage, to: token)
        updateHUD()
        if manualTapCount.isMultiple(of: 10) { persist() }
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
            discoveredEnemyIDs.insert(spec.id)
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

            let manualHitArea = SKSpriteNode(color: .clear, size: CGSize(width: 76, height: 96))
            manualHitArea.position = CGPoint(x: 0, y: 8)
            manualHitArea.zPosition = 8
            manualHitArea.name = "manual_salvage_\(enemy.token)"
            enemy.root.addChild(manualHitArea)

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
        refreshLoadout()
        rebuildAdaptiveRails()
    }

    private func dismantle(_ enemy: ActiveEnemy) {
        let stage = content.stages[stageIndex]
        credits += stage.baseReward * stage.rewardMultiplierPpm / 1_000_000
        let baseParts = enemy.spec.enemyClass == "boss" ? 15 : (enemy.spec.enemyClass == "elite" ? 6 : 3)
        parts += baseParts + magnetLevel - 1
        spawnScrapBurst(at: enemy.root.position)
        spawnShelterDelivery(
            from: enemy.root.position,
            amount: ShelterRecovery.deliveredComponents(enemyClass: enemy.spec.enemyClass)
        )
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
        buildShelterReactor()
    }

    private func buildShelterReactor() {
        shelterReactor.name = "shelter_reactor"
        shelterReactor.position = CGPoint(x: 16, y: 500)
        shelterReactor.zPosition = 12
        combatLayer.addChild(shelterReactor)

        let panel = PixelArt.panel(size: CGSize(width: 140, height: 68), name: "shelter_reactor_panel")
        shelterReactor.addChild(panel)
        let title = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(title, size: 8, color: PixelPalette.lightTeal, alignment: .left)
        title.text = "피난처 7호 • 반응로"
        title.position = CGPoint(x: 12, y: 54)
        title.zPosition = 3
        shelterReactor.addChild(title)

        shelterCore.position = CGPoint(x: 28, y: 28)
        shelterCore.zPosition = 3
        shelterCore.name = "shelter_reactor_core"
        shelterReactor.addChild(shelterCore)
        for index in 0..<3 {
            let lamp = SKSpriteNode(color: PixelPalette.midIron, size: CGSize(width: 10, height: 10))
            lamp.position = CGPoint(x: 62 + index * 24, y: 28)
            lamp.zPosition = 3
            lamp.name = "shelter_reactor_lamp_\(index + 1)"
            shelterReactor.addChild(lamp)
            shelterLamps.append(lamp)
        }
        refreshShelterRecoveryVisuals()
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
        status.text = "폐품장 운영 • 적을 눌러 직접 해체"
        status.position = CGPoint(x: 24, y: 126)
        status.zPosition = 93
        controlsLayer.addChild(status)

        configureLabel(loadoutLabel, size: 8, color: PixelPalette.workWhite, alignment: .left)
        loadoutLabel.position = CGPoint(x: 24, y: 106)
        loadoutLabel.zPosition = 93
        controlsLayer.addChild(loadoutLabel)

        addMenuTile(name: "shop_open", title: "장비", subtitle: "직접 +\(manualDamage)", spriteID: content.player.spriteId, x: 22, y: 62)
        addMenuTile(name: "crew_open", title: "직원", subtitle: "보라 LV.\(crewLevel)", spriteID: "crew_bora_base", x: 116, y: 62)
        addMenuTile(name: "facility_open", title: "시설", subtitle: "+\(passiveIncomeRate)/초", spriteID: content.drones[0].spriteId, x: 22, y: 24)
        addMenuTile(name: "records_open", title: "괴수 기록", subtitle: "\(discoveredEnemyIDs.count)/\(content.enemies.count)", spriteID: content.enemies.first?.spriteId ?? "enemy_can_bug", x: 116, y: 24)

        let overclockPanel = PixelArt.panel(size: CGSize(width: 112, height: 112), name: "overclock")
        overclockButton.removeAllChildren()
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

    private func addMenuTile(name: String, title: String, subtitle: String, spriteID: String, x: Int, y: Int) {
        let button = PixelArt.panel(size: CGSize(width: 88, height: 34), name: name)
        button.position = CGPoint(x: x, y: y)
        button.zPosition = 94
        button.name = name
        controlsLayer.addChild(button)

        let hitArea = SKSpriteNode(color: .clear, size: CGSize(width: 88, height: 34))
        hitArea.anchorPoint = .zero
        hitArea.position = CGPoint(x: x, y: y)
        hitArea.zPosition = 95
        hitArea.name = name
        controlsLayer.addChild(hitArea)

        let icon = PixelArt.asset(spriteID, scale: spriteID.hasPrefix("enemy_") ? 0.55 : 0.30)
        icon.position = CGPoint(x: x + 17, y: y + 17)
        icon.zPosition = 96
        icon.name = name
        controlsLayer.addChild(icon)
        addControlLabel(title, x: x + 31, y: y + 22, size: 8, color: PixelPalette.warningAmber, name: name)
        let subtitleLabel = addControlLabel(subtitle, x: x + 31, y: y + 10, size: 6, color: PixelPalette.lightTeal, name: name)
        subtitleLabel.name = "\(name)_subtitle"
    }

    @discardableResult
    private func addControlLabel(_ text: String, x: Int, y: Int, size: CGFloat, color: SKColor, name: String) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(label, size: size, color: color, alignment: .left)
        label.text = text
        label.position = CGPoint(x: x, y: y)
        label.zPosition = 96
        label.name = name
        controlsLayer.addChild(label)
        return label
    }

    private func buildStoryGoal() {
        storyLayer.zPosition = 145
        let panel = PixelArt.panel(size: CGSize(width: 336, height: 64), name: "story_goal")
        panel.position = CGPoint(x: 12, y: 656)
        panel.name = "story_goal"
        storyLayer.addChild(panel)
        let hitArea = SKSpriteNode(color: .clear, size: CGSize(width: 336, height: 64))
        hitArea.anchorPoint = .zero
        hitArea.position = CGPoint(x: 12, y: 656)
        hitArea.zPosition = 2
        hitArea.name = "story_goal"
        storyLayer.addChild(hitArea)

        configureLabel(storyGoalTitleLabel, size: 10, color: PixelPalette.warningAmber, alignment: .left)
        storyGoalTitleLabel.position = CGPoint(x: 24, y: 700)
        storyGoalTitleLabel.zPosition = 4
        storyGoalTitleLabel.name = "story_goal"
        storyLayer.addChild(storyGoalTitleLabel)
        configureLabel(storyGoalDetailLabel, size: 7, color: PixelPalette.lightTeal, alignment: .left)
        storyGoalDetailLabel.position = CGPoint(x: 24, y: 676)
        storyGoalDetailLabel.zPosition = 4
        storyGoalDetailLabel.name = "story_goal"
        storyLayer.addChild(storyGoalDetailLabel)
        configureLabel(storyGoalProgressLabel, size: 9, color: PixelPalette.workWhite, alignment: .right)
        storyGoalProgressLabel.position = CGPoint(x: 332, y: 700)
        storyGoalProgressLabel.zPosition = 4
        storyGoalProgressLabel.name = "story_goal"
        storyLayer.addChild(storyGoalProgressLabel)

        let progressBack = SKSpriteNode(color: PixelPalette.ink, size: CGSize(width: 92, height: 9))
        progressBack.anchorPoint = .zero
        progressBack.position = CGPoint(x: 240, y: 672)
        progressBack.zPosition = 3
        progressBack.name = "story_goal"
        storyLayer.addChild(progressBack)
        storyGoalFill.anchorPoint = .zero
        storyGoalFill.position = CGPoint(x: 242, y: 674)
        storyGoalFill.zPosition = 4
        storyGoalFill.name = "story_goal"
        storyLayer.addChild(storyGoalFill)
        refreshStoryGoal()
    }

    private func buildTutorial() {
        tutorialLayer.zPosition = 150
        let panel = PixelArt.panel(size: CGSize(width: 336, height: 58), name: "tutorial_panel")
        panel.position = CGPoint(x: 12, y: 590)
        tutorialLayer.addChild(panel)
        configureLabel(tutorialLabel, size: 9, color: PixelPalette.workWhite, alignment: .center)
        tutorialLabel.position = CGPoint(x: 180, y: 619)
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
        case 0: tutorialLabel.text = "① 괴수를 직접 누르면 해체 피해와 고철을 얻습니다."
        case 1:
            tutorialLabel.text = "② 직원은 자동 공격합니다. [과부하]로 속도를 올리세요."
            overclockButton.run(.repeat(.sequence([.fadeAlpha(to: 0.55, duration: 0.15), .fadeAlpha(to: 1, duration: 0.15)]), count: 4))
        case 2: tutorialLabel.text = "③ 고철 10개를 모아 첫 장비를 강화하세요."
        case 3: tutorialLabel.text = "③ [장비]에서 절단날을 강화하고 직접 해체를 키우세요."
        default:
            tutorialLabel.text = "완료: 직접 해체 → 직원 자동화 → 시설 수익 회수 • S10 목표"
            tutorialLayer.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 0.15), .hide()]))
        }
    }

    private func refreshStoryGoal() {
        let goal = ShelterRecovery.goal(
            deliveredParts: shelterRepairParts,
            highestStage: max(save.highestStage, content.stages[stageIndex].number)
        )
        storyGoalTitleLabel.text = "CH." + String(storyChapter + 1) + "  " + goal.title
        storyGoalDetailLabel.text = goal.detail
        storyGoalProgressLabel.text = String(goal.current) + " / " + String(goal.required) + "  〉"
        let ratio = CGFloat(goal.current) / CGFloat(max(1, goal.required))
        storyGoalFill.size.width = floor(88 * ratio)
        storyGoalFill.color = goal.current >= goal.required ? PixelPalette.recoveryGreen : PixelPalette.warningAmber
    }

    private func openPrologue() {
        storyOverlayIsPrologue = true
        buildStoryOverlay(
            title: "폐기 판정 • 피난처 7호",
            lines: [
                "최종 폐기까지 남은 시간  72:00:00",
                "",
                "버려진 정비사 모와 작업반은",
                "살아 있는 폐품에서 부품을 모아",
                "죽어 가는 반응로를 다시 켜야 한다.",
                "",
                "첫 목표 • 비상 조명 복구  0/3"
            ],
            action: "해체를 시작한다"
        )
    }

    private func openStoryBrief() {
        storyOverlayIsPrologue = false
        let goal = ShelterRecovery.goal(
            deliveredParts: shelterRepairParts,
            highestStage: max(save.highestStage, content.stages[stageIndex].number)
        )
        buildStoryOverlay(
            title: "피난처 7호 복구 일지",
            lines: [
                "모: 우린 아직 폐기물이 아니야.",
                "보라: 반응로가 켜지면 모두 살아남아.",
                "",
                "현재 목표 • " + goal.title,
                goal.detail,
                "진행 " + String(goal.current) + " / " + String(goal.required),
                "",
                "괴수를 해체하면 부품이 반응로로 운반됩니다."
            ],
            action: "작업장으로 돌아간다"
        )
    }

    private func buildStoryOverlay(title: String, lines: [String], action: String) {
        storyOverlayLayer.removeAllChildren()
        storyOverlayLayer.isHidden = false
        storyOverlayLayer.zPosition = 300

        let shade = SKSpriteNode(color: PixelPalette.ink.withAlphaComponent(0.92), size: Self.logicalSize)
        shade.anchorPoint = .zero
        shade.name = "story_close"
        storyOverlayLayer.addChild(shade)

        let panel = PixelArt.panel(size: CGSize(width: 324, height: 470), name: "story_panel")
        panel.position = CGPoint(x: 18, y: 170)
        panel.zPosition = 1
        storyOverlayLayer.addChild(panel)
        addStoryOverlayLabel(title, x: 38, y: 608, size: 15, color: PixelPalette.warningAmber, alignment: .left)
        addStoryOverlayLabel("STORY LOG / 생존 기록", x: 38, y: 580, size: 8, color: PixelPalette.lightTeal, alignment: .left)

        let mo = PixelArt.asset(content.player.spriteId, scale: 1.35)
        mo.position = CGPoint(x: 92, y: 492)
        mo.zPosition = 3
        storyOverlayLayer.addChild(mo)
        let bora = PixelArt.asset("crew_bora_base", scale: 1.35)
        bora.position = CGPoint(x: 250, y: 492)
        bora.zPosition = 3
        storyOverlayLayer.addChild(bora)

        let warning = PixelArt.sprite(blocks: [
            .init(x: 0, y: 0, width: 70, height: 6, color: PixelPalette.darkRust),
            .init(x: 8, y: 8, width: 54, height: 6, color: PixelPalette.rust),
            .init(x: 18, y: 16, width: 34, height: 6, color: PixelPalette.sparkOrange),
            .init(x: 29, y: 24, width: 12, height: 12, color: PixelPalette.warningAmber)
        ], name: "story_reactor_warning")
        warning.position = CGPoint(x: 145, y: 466)
        warning.zPosition = 4
        storyOverlayLayer.addChild(warning)
        warning.run(stepLoop(points: [0, 2, 0, -2], duration: 0.18), withKey: "warning")

        for (index, line) in lines.enumerated() {
            addStoryOverlayLabel(
                line,
                x: 180,
                y: 424 - index * 27,
                size: index == 0 ? 10 : 9,
                color: index == 0 ? PixelPalette.sparkOrange : PixelPalette.workWhite,
                alignment: .center
            )
        }

        let button = PixelArt.panel(size: CGSize(width: 248, height: 58), name: "story_continue")
        button.position = CGPoint(x: 56, y: 184)
        button.zPosition = 4
        button.name = "story_continue"
        storyOverlayLayer.addChild(button)
        let hitArea = SKSpriteNode(color: .clear, size: CGSize(width: 248, height: 58))
        hitArea.anchorPoint = .zero
        hitArea.position = CGPoint(x: 56, y: 184)
        hitArea.zPosition = 5
        hitArea.name = "story_continue"
        storyOverlayLayer.addChild(hitArea)
        addStoryOverlayLabel(action + "  〉", x: 180, y: 213, size: 11, color: PixelPalette.warningAmber, alignment: .center, name: "story_continue")
    }

    private func addStoryOverlayLabel(
        _ text: String,
        x: Int,
        y: Int,
        size: CGFloat,
        color: SKColor,
        alignment: SKLabelHorizontalAlignmentMode,
        name: String? = nil
    ) {
        let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(label, size: size, color: color, alignment: alignment)
        label.text = text
        label.position = CGPoint(x: x, y: y)
        label.zPosition = 6
        label.name = name
        storyOverlayLayer.addChild(label)
    }

    private func closeStoryOverlay() {
        if storyOverlayIsPrologue {
            prologueSeen = true
        }
        storyOverlayLayer.isHidden = true
        storyOverlayLayer.removeAllChildren()
        storyOverlayIsPrologue = false
        persist()
        if offlineSeconds >= 60 && offlineAmount > 0 && shopLayer.isHidden {
            openFacilities(status: offlineReportText)
        }
    }

    private func refreshShelterRecoveryVisuals() {
        let milestone = ShelterRecovery.milestone(for: shelterRepairParts)
        shelterReactor.alpha = milestone == 0 ? 0.82 : 1
        shelterCore.removeAllActions()
        shelterCore.alpha = 1
        shelterCore.color = milestone >= 3 ? PixelPalette.warningAmber : (milestone >= 1 ? PixelPalette.darkTeal : PixelPalette.midIron)
        for (index, lamp) in shelterLamps.enumerated() {
            lamp.removeAllActions()
            lamp.alpha = 1
            lamp.color = index < milestone ? PixelPalette.recoveryGreen : PixelPalette.midIron
        }
        if milestone >= 3 {
            shelterCore.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.55, duration: 0), .wait(forDuration: 0.16),
                .fadeAlpha(to: 1, duration: 0), .wait(forDuration: 0.16)
            ])), withKey: "reactor_pulse")
        }
    }

    private enum ShopItem { case cutter, drone, magnet, crew }

    private var cutterCost: Int { 10 * cutterLevel }
    private var droneCost: Int { 25 * droneLevel }
    private var magnetCost: Int { 15 * magnetLevel }
    private var crewCost: Int { 30 * crewLevel }

    private func openShop(status: String = "직접 해체 공격을 원하는 방향으로 강화하세요") {
        beginManagement(.equipment, title: "장비 작업대", subtitle: "직접 해체 +\(manualDamage) 피해 • 탭마다 고철 +\(manualReward)")
        addShopItem(name: "buy_cutter", title: "강화 절단날 LV.\(cutterLevel + 1)", effect: "직접·자동 절단 피해 증가", cost: cutterCost, y: 450)
        addShopItem(name: "buy_drone", title: "리벳 출력 코일 LV.\(droneLevel + 1)", effect: "드론 자동 피해 +4", cost: droneCost, y: 365)
        addShopItem(name: "buy_magnet", title: "자석 바구니 LV.\(magnetLevel + 1)", effect: "괴수마다 부품 +1", cost: magnetCost, y: 280)
        finishManagement(status: status)
    }

    private func openCrew(status: String = "보라는 전투 중 계속 공격하고 주기적으로 모와 협동합니다") {
        beginManagement(.crew, title: "직원 숙소", subtitle: "고용 직원 1명 • 보라가 자동 해체 중")
        let bora = PixelArt.asset("crew_bora_base", scale: 1.15)
        bora.position = CGPoint(x: 88, y: 445)
        bora.zPosition = 4
        shopLayer.addChild(bora)
        addShopLabel("보라  LV.\(crewLevel)", x: 134, y: 470, size: 14, color: PixelPalette.warningAmber, alignment: .left)
        addShopLabel("개인 공격  \(5 + (crewLevel - 1) * 5)", x: 134, y: 440, size: 9, color: PixelPalette.workWhite, alignment: .left)
        addShopLabel("협동 해체  전체 +\(8 + cutterLevel * 2 + crewLevel * 4)", x: 134, y: 414, size: 9, color: PixelPalette.lightTeal, alignment: .left)
        addShopItem(name: "buy_crew", title: "보라 작업 숙련 LV.\(crewLevel + 1)", effect: "개인 피해 +5 • 협동 전체 +4", cost: crewCost, y: 300)
        addShopLabel("다음 직원 슬롯", x: 50, y: 266, size: 8, color: PixelPalette.midIron, alignment: .left)
        addShopLabel("S10 보스 격파 후 개방", x: 308, y: 266, size: 8, color: PixelPalette.midIron, alignment: .right)
        finishManagement(status: status)
    }

    private func openFacilities(status: String = "회수 대기 고철은 사라지지 않습니다") {
        beginManagement(.facilities, title: "폐품장 시설", subtitle: "자동 생산 +\(passiveIncomeRate)/초 • 오프라인 최대 8시간")
        let collect = PixelArt.panel(size: CGSize(width: 292, height: 54), name: "collect_yard_income")
        collect.position = CGPoint(x: 34, y: 468)
        collect.zPosition = 2
        collect.name = "collect_yard_income"
        shopLayer.addChild(collect)
        addShopHitArea(name: "collect_yard_income", position: CGPoint(x: 34, y: 468), size: CGSize(width: 292, height: 54))
        addShopLabel("회수 대기  \(yardIncomeBank) 고철", x: 50, y: 501, size: 11, color: PixelPalette.workWhite, name: "collect_yard_income", alignment: .left)
        addShopLabel("수익 회수", x: 308, y: 492, size: 10, color: yardIncomeBank > 0 ? PixelPalette.warningAmber : PixelPalette.midIron, name: "collect_yard_income", alignment: .right)
        addFacilityItem(.press, level: pressLevel, y: 385)
        addFacilityItem(.sorter, level: sorterLevel, y: 305)
        addFacilityItem(.warehouse, level: warehouseLevel, y: 225)
        finishManagement(status: status)
    }

    private func openRecords() {
        beginManagement(.records, title: "괴수 해체 기록", subtitle: "발견 \(discoveredEnemyIDs.count)/\(content.enemies.count) • 싸워 본 괴수만 기록됩니다")
        for (index, enemy) in content.enemies.prefix(6).enumerated() {
            addRecordCard(enemy, index: index)
        }
        addShopLabel("다음 목표", x: 42, y: 276, size: 9, color: PixelPalette.warningAmber, alignment: .left)
        let bossGoal = save.highestStage >= 10 ? "✓ S10 폐품왕 격파" : "□ S10 폐품왕 도달"
        let regionGoal = save.highestStage >= 20 ? "✓ R1 뒷골목 정리" : "□ S20 지역 완료"
        addShopLabel(bossGoal, x: 54, y: 248, size: 9, color: PixelPalette.workWhite, alignment: .left)
        addShopLabel(regionGoal, x: 54, y: 224, size: 9, color: PixelPalette.workWhite, alignment: .left)
        addShopLabel("직접 해체 \(manualTapCount)회", x: 306, y: 236, size: 8, color: PixelPalette.lightTeal, alignment: .right)
        finishManagement(status: "괴수의 이름·모습·장기 목표를 여기서 확인하세요")
    }

    private func beginManagement(_ panelType: ManagementPanel, title: String, subtitle: String) {
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
        addShopLabel(title, x: 42, y: 622, size: 15, color: PixelPalette.warningAmber, alignment: .left)
        addShopLabel("고철 \(credits)", x: 318, y: 622, size: 10, color: PixelPalette.workWhite, alignment: .right)
        addShopLabel(subtitle, x: 42, y: 596, size: 8, color: PixelPalette.lightTeal, alignment: .left)
        addManagementTabs(selected: panelType)
        let close = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(close, size: 10, color: PixelPalette.lightIron, alignment: .right)
        close.text = "닫기 ×"
        close.position = CGPoint(x: 326, y: 642)
        close.zPosition = 4
        close.name = "shop_close"
        shopLayer.addChild(close)
    }

    private func addManagementTabs(selected: ManagementPanel) {
        let tabs: [(ManagementPanel, String, String)] = [
            (.equipment, "management_equipment", "장비"),
            (.crew, "management_crew", "직원"),
            (.facilities, "management_facilities", "시설"),
            (.records, "management_records", "기록")
        ]
        for (index, tab) in tabs.enumerated() {
            let x = 34 + index * 74
            let button = PixelArt.panel(size: CGSize(width: 68, height: 30), name: tab.1)
            button.position = CGPoint(x: x, y: 548)
            button.zPosition = 2
            button.name = tab.1
            shopLayer.addChild(button)
            addShopHitArea(name: tab.1, position: CGPoint(x: x, y: 548), size: CGSize(width: 68, height: 30))
            addShopLabel(tab.2, x: x + 34, y: 563, size: 8, color: tab.0 == selected ? PixelPalette.warningAmber : PixelPalette.lightIron, name: tab.1)
        }
    }

    private func finishManagement(status: String) {
        configureLabel(shopStatusLabel, size: 8, color: PixelPalette.workWhite, alignment: .center)
        shopStatusLabel.text = status
        shopStatusLabel.position = CGPoint(x: 180, y: 184)
        shopStatusLabel.zPosition = 4
        shopLayer.addChild(shopStatusLabel)
    }

    private func addShopItem(name: String, title: String, effect: String, cost: Int, y: Int) {
        let button = PixelArt.panel(size: CGSize(width: 292, height: 66), name: name)
        button.position = CGPoint(x: 34, y: y)
        button.zPosition = 2
        button.name = name
        shopLayer.addChild(button)
        addShopHitArea(name: name, position: CGPoint(x: 34, y: y), size: CGSize(width: 292, height: 66))
        addShopLabel(title, x: 50, y: y + 45, size: 10, color: PixelPalette.workWhite, name: name, alignment: .left)
        addShopLabel(effect, x: 50, y: y + 22, size: 8, color: PixelPalette.lightTeal, name: name, alignment: .left)
        addShopLabel("고철 \(cost)", x: 308, y: y + 33, size: 9, color: credits >= cost ? PixelPalette.warningAmber : PixelPalette.midIron, name: name, alignment: .right)
    }

    private func addFacilityItem(_ facility: YardFacility, level: Int, y: Int) {
        let name = "buy_\(facility.rawValue)"
        let cost = YardEconomy.upgradeCost(facility, currentLevel: level)
        let button = PixelArt.panel(size: CGSize(width: 292, height: 66), name: name)
        button.position = CGPoint(x: 34, y: y)
        button.zPosition = 2
        button.name = name
        shopLayer.addChild(button)
        addShopHitArea(name: name, position: CGPoint(x: 34, y: y), size: CGSize(width: 292, height: 66))
        addShopLabel("\(facility.nameKo)  LV.\(level)", x: 50, y: y + 45, size: 10, color: PixelPalette.workWhite, name: name, alignment: .left)
        addShopLabel("현재 +\(YardEconomy.facilityOutput(facility, level: level))/초  →  +\(YardEconomy.facilityOutput(facility, level: level + 1))/초", x: 50, y: y + 22, size: 8, color: PixelPalette.lightTeal, name: name, alignment: .left)
        addShopLabel("강화 \(cost)", x: 308, y: y + 33, size: 9, color: credits >= cost ? PixelPalette.warningAmber : PixelPalette.midIron, name: name, alignment: .right)
    }

    private func addRecordCard(_ enemy: VerticalSliceContent.Enemy, index: Int) {
        let discovered = discoveredEnemyIDs.contains(enemy.id)
        let column = index % 3
        let row = index / 3
        let x = 34 + column * 98
        let y = 445 - row * 96
        let card = PixelArt.panel(size: CGSize(width: 88, height: 82), name: "record_\(enemy.id)")
        card.position = CGPoint(x: x, y: y)
        card.zPosition = 2
        shopLayer.addChild(card)
        if discovered {
            let art = PixelArt.asset(enemy.spriteId, scale: enemy.id == "can_bug" ? 1.1 : 0.62)
            art.position = CGPoint(x: x + 44, y: y + 48)
            art.zPosition = 4
            shopLayer.addChild(art)
        } else {
            let unknown = SKLabelNode(fontNamed: "Menlo-Bold")
            configureLabel(unknown, size: 24, color: PixelPalette.midIron, alignment: .center)
            unknown.text = "?"
            unknown.position = CGPoint(x: x + 44, y: y + 49)
            unknown.zPosition = 4
            shopLayer.addChild(unknown)
        }
        addShopLabel(discovered ? enemy.nameKo : "미발견", x: x + 44, y: y + 14, size: 7, color: discovered ? PixelPalette.workWhite : PixelPalette.midIron)
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

    private func addShopHitArea(name: String, position: CGPoint, size: CGSize) {
        let hitArea = SKSpriteNode(color: .clear, size: size)
        hitArea.anchorPoint = .zero
        hitArea.position = position
        hitArea.zPosition = 3
        hitArea.name = name
        shopLayer.addChild(hitArea)
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
        let status = shopStatusLabel.text ?? "강화 완료"
        switch item {
        case .crew: openCrew(status: status)
        case .cutter, .drone, .magnet: openShop(status: status)
        }
    }

    private func buyFacility(_ facility: YardFacility) {
        let level: Int
        switch facility {
        case .press: level = pressLevel
        case .sorter: level = sorterLevel
        case .warehouse: level = warehouseLevel
        }
        let cost = YardEconomy.upgradeCost(facility, currentLevel: level)
        guard credits >= cost else {
            shopStatusLabel.text = "고철이 부족합니다 • 직접 해체하거나 회수 대기 수익을 받으세요"
            shopStatusLabel.fontColor = PixelPalette.sparkOrange
            return
        }
        credits -= cost
        switch facility {
        case .press: pressLevel += 1
        case .sorter: sorterLevel += 1
        case .warehouse: warehouseLevel += 1
        }
        refreshLoadout()
        updateHUD()
        persist()
        openFacilities(status: "\(facility.nameKo) 강화 완료 • 자동 수익이 증가했습니다")
    }

    private func collectYardIncome() {
        guard yardIncomeBank > 0 else {
            shopStatusLabel.text = "아직 회수할 고철이 없습니다"
            shopStatusLabel.fontColor = PixelPalette.midIron
            return
        }
        let collected = yardIncomeBank
        credits += collected
        yardIncomeBank = 0
        updateHUD()
        persist()
        openFacilities(status: "시설 수익 \(collected) 고철을 회수했습니다")
    }

    private func closeShop() {
        shopLayer.isHidden = true
        shopLayer.removeAllChildren()
    }

    private func refreshLoadout() {
        loadoutLabel.text = "직접 +\(manualDamage) • 자동 +\(passiveIncomeRate)/초 • 회수 대기 \(yardIncomeBank)"
        (controlsLayer.childNode(withName: "//shop_open_subtitle") as? SKLabelNode)?.text = "직접 +\(manualDamage)"
        (controlsLayer.childNode(withName: "//crew_open_subtitle") as? SKLabelNode)?.text = "보라 LV.\(crewLevel)"
        (controlsLayer.childNode(withName: "//facility_open_subtitle") as? SKLabelNode)?.text = "+\(passiveIncomeRate)/초"
        (controlsLayer.childNode(withName: "//records_open_subtitle") as? SKLabelNode)?.text = "\(discoveredEnemyIDs.count)/\(content.enemies.count)"
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

    private func spawnShelterDelivery(from position: CGPoint, amount: Int) {
        let component = PixelArt.sprite(blocks: [
            .init(x: 0, y: 4, width: 18, height: 10, color: PixelPalette.darkIron),
            .init(x: 3, y: 7, width: 12, height: 10, color: PixelPalette.lightIron),
            .init(x: 7, y: 10, width: 4, height: 4, color: PixelPalette.warningAmber),
            .init(x: 0, y: 0, width: 4, height: 4, color: PixelPalette.sparkOrange),
            .init(x: 14, y: 0, width: 4, height: 4, color: PixelPalette.sparkOrange)
        ], name: "shelter_delivery")
        component.position = position
        component.zPosition = 76
        effectsLayer.addChild(component)

        let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(label, size: 9, color: PixelPalette.warningAmber, alignment: .center)
        label.text = "반응로 부품 +" + String(amount)
        label.position = CGPoint(x: 9, y: 26)
        label.zPosition = 2
        component.addChild(label)

        let route = [
            CGPoint(x: position.x - 8, y: position.y + 30),
            CGPoint(x: 182, y: 464),
            CGPoint(x: 122, y: 516),
            CGPoint(x: 72, y: 528)
        ]
        var actions: [SKAction] = route.flatMap { [.move(to: $0, duration: 0), .wait(forDuration: 0.08)] }
        actions.append(.run { [weak self] in self?.deliverShelterComponents(amount) })
        actions.append(.removeFromParent())
        component.run(.sequence(actions))
    }

    private func deliverShelterComponents(_ amount: Int) {
        let previousMilestone = ShelterRecovery.milestone(for: shelterRepairParts)
        shelterRepairParts += max(0, amount)
        storyChapter = max(storyChapter, ShelterRecovery.chapter(for: shelterRepairParts))
        let currentMilestone = ShelterRecovery.milestone(for: shelterRepairParts)
        refreshShelterRecoveryVisuals()
        refreshStoryGoal()
        updateHUD()
        persist()
        if currentMilestone > previousMilestone {
            playRecoveryMilestone(currentMilestone)
        }
    }

    private func playRecoveryMilestone(_ milestone: Int) {
        let bannerPanel = PixelArt.panel(size: CGSize(width: 240, height: 56), name: "recovery_milestone")
        bannerPanel.position = CGPoint(x: 60, y: 540)
        bannerPanel.zPosition = 86
        effectsLayer.addChild(bannerPanel)
        let banner = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        configureLabel(banner, size: 11, color: PixelPalette.warningAmber, alignment: .center)
        banner.text = "복구 완료 • " + ShelterRecovery.milestoneTitle(milestone)
        banner.position = CGPoint(x: 120, y: 28)
        banner.zPosition = 2
        bannerPanel.addChild(banner)
        bannerPanel.run(.sequence([
            .moveBy(x: 0, y: 6, duration: 0), .wait(forDuration: 0.8),
            .fadeOut(withDuration: 0.12), .removeFromParent()
        ]))

        for index in 0..<8 {
            let light = SKSpriteNode(
                color: index.isMultiple(of: 2) ? PixelPalette.warningAmber : PixelPalette.recoveryGreen,
                size: CGSize(width: 8, height: 4)
            )
            light.position = CGPoint(x: 26 + index * 16, y: 552 + (index % 2) * 8)
            light.zPosition = 74
            effectsLayer.addChild(light)
            light.run(.sequence([
                .fadeAlpha(to: 0.25, duration: 0), .wait(forDuration: 0.10 + Double(index) * 0.03),
                .fadeAlpha(to: 1, duration: 0), .wait(forDuration: 0.45),
                .fadeOut(withDuration: 0.10), .removeFromParent()
            ]))
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
        currencyLabel.text = "고철 \(credits)  •  +\(passiveIncomeRate)/초"
        locationLabel.text = "피난처 7호 • 복구 부품 \(shelterRepairParts) • 회수 \(yardIncomeBank)"
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
            "직접 \(manualDamage) / 협동 가동"
        ], accent: PixelPalette.lightTeal)
        let remaining = activeEnemies.filter { $0.hp > 0 }
        let goal = ShelterRecovery.goal(deliveredParts: shelterRepairParts, highestStage: max(save.highestStage, content.stages[stageIndex].number))
        addRail(name: "ipad_wave_rail", title: "WAVE / 적 무리", x: rightX, width: available, lines: [
            "현재 \(remaining.count)체",
            remaining.first.map { "표적  \($0.spec.nameKo)" } ?? "다음 무리 탐색",
            goal.title,
            "복구  \(goal.current)/\(goal.required)"
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
        save.pressLevel = pressLevel
        save.sorterLevel = sorterLevel
        save.warehouseLevel = warehouseLevel
        save.yardIncomeBank = yardIncomeBank
        save.manualTapCount = manualTapCount
        save.discoveredEnemyIDs = discoveredEnemyIDs.sorted()
        save.storyChapter = storyChapter
        save.shelterRepairParts = shelterRepairParts
        save.prologueSeen = prologueSeen
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

import SpriteKit

@MainActor
final class PixelSeasonScene: SKScene, AdaptivePixelScene {
    static let logicalSize = PixelViewport.laneSize
    static let rewardHitSize = CGSize(width: 122, height: 48)
    static let tierPageSize = 5

    var onClose: (() -> Void)?
    var onSave: ((GameSave) -> Void)?
    var onAccessibilitySummary: ((String) -> Void)?

    private var save: GameSave
    private let catalog: SeasonCatalog
    private let nowProvider: () -> Date
    private var season: SeasonGameplayCoordinator
    private var premiumUnlocked: Bool
    private var tierPage = 0
    private var status = "해금된 보상은 직접 수령해야 합니다"
    private var viewport = PixelViewport.phoneFallback

    private let backdrop = SKSpriteNode(color: PixelPalette.ink, size: logicalSize)
    private let laneRoot = SKNode()
    private let headerRoot = SKNode()
    private let footerRoot = SKNode()
    private let railRoot = SKNode()

    init(
        save: GameSave,
        catalog: SeasonCatalog = SeasonContentLoader.loadCatalog(),
        premiumUnlocked: Bool = false,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.save = save
        self.catalog = catalog
        self.premiumUnlocked = premiumUnlocked
        self.nowProvider = nowProvider
        season = SeasonGameplayCoordinator(
            save: save,
            catalog: catalog,
            date: nowProvider(),
            clockSuspect: save.idleOperations.clockSuspect,
            premiumUnlocked: premiumUnlocked
        )
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
        synchronizeAndSaveIfNeeded()
        rebuild()
        applyViewport(PixelViewport(view: view))
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

    func updatePremiumUnlocked(_ unlocked: Bool) {
        premiumUnlocked = unlocked
        season.updatePremiumUnlocked(unlocked)
        save.seasonProgress = season.progress
        rebuild()
        applyViewport(viewport)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        let names = Set(nodes(at: point).compactMap(\.name))
        if names.contains("season_close") {
            onClose?()
            return
        }
        if names.contains("season_page_previous") {
            tierPage = max(0, tierPage - 1)
            rebuild()
            applyViewport(viewport)
            return
        }
        if names.contains("season_page_next") {
            let tierCount = (try? season.snapshot(
                at: nowProvider(),
                clockSuspect: save.idleOperations.clockSuspect
            ))?.definition.rewardTiers.count ?? 0
            let maximum = max(0, (tierCount - 1) / Self.tierPageSize)
            tierPage = min(maximum, tierPage + 1)
            rebuild()
            applyViewport(viewport)
            return
        }
        for name in names {
            if let level = claimLevel(from: name, prefix: "season_claim_free_") {
                _ = claimReward(level: level, track: .free)
                return
            }
            if let level = claimLevel(from: name, prefix: "season_claim_premium_") {
                _ = claimReward(level: level, track: .premium)
                return
            }
        }
    }

    func showRewardPage(containing level: Int) {
        guard level > 0 else { return }
        tierPage = (level - 1) / Self.tierPageSize
        rebuild()
        applyViewport(viewport)
    }

    @discardableResult
    func claimReward(level: Int, track: SeasonRewardTrack) -> Bool {
        season.write(to: &save)
        do {
            let reward = try SeasonSaveRewardService.claim(
                level: level,
                track: track,
                catalog: catalog,
                premiumUnlocked: premiumUnlocked,
                save: &save
            )
            season = SeasonGameplayCoordinator(
                save: save,
                catalog: catalog,
                date: nowProvider(),
                clockSuspect: save.idleOperations.clockSuspect,
                premiumUnlocked: premiumUnlocked
            )
            status = "수령 완료 • " + SeasonSaveRewardService.description(for: reward)
            onSave?(save)
            rebuild()
            applyViewport(viewport)
            return true
        } catch SeasonEngineError.tierLocked {
            status = "아직 XP가 부족한 단계입니다"
        } catch SeasonEngineError.premiumRequired {
            status = "프리미엄 패스 권한이 필요합니다"
        } catch SeasonEngineError.alreadyClaimed {
            status = "이미 수령한 보상입니다"
        } catch {
            status = "보상을 확인할 수 없습니다"
        }
        rebuild()
        applyViewport(viewport)
        return false
    }

    var accessibilitySummary: String {
        guard let snapshot = try? season.snapshot(
            at: nowProvider(),
            clockSuspect: save.idleOperations.clockSuspect
        ) else { return "시즌 정보를 확인할 수 없습니다" }
        let daily = snapshot.dailyMissions.map { missionText($0) }.joined(separator: ". ")
        let warning = save.idleOperations.clockSuspect ? ". 기기 시간 확인 필요, 시즌 전환 보류" : ""
        return "시즌 \(snapshot.definition.titleKo). XP \(season.progress.totalXP). 주간 \(snapshot.weeklyXP)/\(snapshot.definition.weeklyXPCap). 오늘 임무. \(daily)\(warning)"
    }

    private func synchronizeAndSaveIfNeeded() {
        let beforeProgress = save.seasonProgress
        let beforeOperations = save.idleOperations
        IdleOperationsEngine.observe(now: nowProvider(), state: &save.idleOperations)
        season.synchronize(at: nowProvider(), clockSuspect: save.idleOperations.clockSuspect)
        season.write(to: &save)
        guard beforeProgress != save.seasonProgress || beforeOperations != save.idleOperations else { return }
        save.schemaVersion = GameSave.currentSchemaVersion
        save.revision += 1
        save.updatedAt = nowProvider()
        onSave?(save)
    }

    private func rebuild() {
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
        buildPanel()
        rebuildTabletRails()
        onAccessibilitySummary?(accessibilitySummary)
    }

    private func buildPanel() {
        guard let snapshot = try? season.snapshot(
            at: nowProvider(),
            clockSuspect: save.idleOperations.clockSuspect
        ) else {
            addLabel("시즌 데이터를 불러올 수 없습니다", x: 180, y: 400, size: 11, color: PixelPalette.sparkOrange, alignment: .center, parent: laneRoot)
            return
        }

        let panel = PixelArt.panel(size: CGSize(width: 336, height: 704), name: "season_panel")
        panel.position = CGPoint(x: 12, y: 48)
        laneRoot.addChild(panel)
        addSignalReceiver()
        addLabel("SEASON • 구조 신호", x: 68, y: 730, size: 15, color: PixelPalette.warningAmber, alignment: .left, parent: headerRoot, name: "season_title")
        addLabel(snapshot.definition.titleKo, x: 68, y: 706, size: 10, color: PixelPalette.workWhite, alignment: .left, parent: headerRoot, name: "season_name")
        addLabel(remainingText(snapshot), x: 318, y: 730, size: 8, color: phaseColor(snapshot.phase), alignment: .right, parent: headerRoot, name: "season_remaining")

        let xpText = "시즌 XP \(season.progress.totalXP)  •  이번 주 \(snapshot.weeklyXP)/\(snapshot.definition.weeklyXPCap)"
        addLabel(xpText, x: 34, y: 674, size: 9, color: PixelPalette.lightTeal, alignment: .left, parent: laneRoot, name: "season_xp")
        addProgressBar(current: snapshot.weeklyXP, maximum: snapshot.definition.weeklyXPCap)

        let clockText = save.idleOperations.clockSuspect
            ? "! 기기 시간이 역행해 시즌 전환을 보류했습니다"
            : "UTC 기준 • 본편 진행과 별도로 쌓입니다"
        addLabel(clockText, x: 34, y: 642, size: 7, color: save.idleOperations.clockSuspect ? PixelPalette.sparkOrange : PixelPalette.midIron, alignment: .left, parent: laneRoot, name: "season_clock_status")

        addLabel("오늘의 임무 3개", x: 34, y: 616, size: 9, color: PixelPalette.warningAmber, alignment: .left, parent: laneRoot, name: "season_mission_header")
        for (index, mission) in snapshot.dailyMissions.enumerated() {
            addMissionRow(mission, y: 592 - index * 22)
        }
        let weeklyComplete = snapshot.weeklyMissions.filter { season.progress.completedMissionIDs.contains($0.instanceID) }.count
        addLabel(
            "누적 주간 임무 \(snapshot.weeklyMissions.count)개 • 완료 \(weeklyComplete)/\(snapshot.weeklyMissions.count)",
            x: 34, y: 522, size: 8, color: PixelPalette.lightTeal, alignment: .left, parent: laneRoot, name: "season_weekly_summary"
        )

        let firstLevel = tierPage * Self.tierPageSize + 1
        let lastLevel = min(snapshot.definition.rewardTiers.count, firstLevel + Self.tierPageSize - 1)
        addLabel("보상 단계 \(firstLevel)-\(lastLevel) / 40", x: 34, y: 496, size: 9, color: PixelPalette.warningAmber, alignment: .left, parent: laneRoot, name: "season_tier_page")
        addLabel(premiumUnlocked ? "프리미엄 연결됨" : "프리미엄 미보유", x: 318, y: 496, size: 7, color: premiumUnlocked ? PixelPalette.recoveryGreen : PixelPalette.midIron, alignment: .right, parent: laneRoot, name: "season_premium_state")

        let tiers = snapshot.definition.rewardTiers.filter { firstLevel...lastLevel ~= $0.level }
        for (index, tier) in tiers.enumerated() {
            addRewardRow(tier, y: 438 - index * 54)
        }
        addPageControls(maximumPage: max(0, (snapshot.definition.rewardTiers.count - 1) / Self.tierPageSize))

        let archived = season.progress.codexRecords.last
        let archiveText = archived.map { "시즌 도감 • \($0.titleKo) • 최고 \($0.highestTier)단계" }
            ?? "시즌 종료 기록은 도감에 영구 보존됩니다"
        addLabel(archiveText, x: 180, y: 142, size: 7, color: PixelPalette.lightIron, alignment: .center, parent: laneRoot, name: "season_archive")
        addLabel(status, x: 180, y: 120, size: 7, color: PixelPalette.recoveryGreen, alignment: .center, parent: laneRoot, name: "season_status")

        let close = PixelArt.panel(size: CGSize(width: 216, height: 48), name: "season_close")
        close.position = CGPoint(x: 72, y: 58)
        close.name = "season_close"
        footerRoot.addChild(close)
        addHitArea(name: "season_close", position: CGPoint(x: 72, y: 58), size: CGSize(width: 216, height: 48), parent: footerRoot)
        addLabel("〈  전투로 돌아가기", x: 180, y: 82, size: 10, color: PixelPalette.workWhite, alignment: .center, parent: footerRoot, name: "season_close")
    }

    private func addSignalReceiver() {
        let receiver = PixelArt.sprite(blocks: [
            .init(x: 14, y: 0, width: 4, height: 26, color: PixelPalette.lightIron),
            .init(x: 4, y: 4, width: 24, height: 4, color: PixelPalette.darkIron),
            .init(x: 8, y: 9, width: 16, height: 8, color: PixelPalette.darkTeal),
            .init(x: 12, y: 12, width: 8, height: 5, color: PixelPalette.lightTeal),
            .init(x: 20, y: 21, width: 5, height: 3, color: PixelPalette.warningAmber),
            .init(x: 25, y: 25, width: 4, height: 3, color: PixelPalette.warningAmber),
            .init(x: 29, y: 29, width: 3, height: 3, color: PixelPalette.warningAmber)
        ], name: "season_signal_receiver")
        receiver.position = CGPoint(x: 28, y: 700)
        receiver.zPosition = 8
        headerRoot.addChild(receiver)
    }

    private func addProgressBar(current: Int, maximum: Int) {
        let back = SKSpriteNode(color: PixelPalette.ink, size: CGSize(width: 292, height: 8))
        back.anchorPoint = .zero
        back.position = CGPoint(x: 34, y: 654)
        laneRoot.addChild(back)
        let fill = SKSpriteNode(color: PixelPalette.warningAmber, size: CGSize(width: floor(288 * CGFloat(min(maximum, current)) / CGFloat(max(1, maximum))), height: 4))
        fill.anchorPoint = .zero
        fill.position = CGPoint(x: 36, y: 656)
        fill.name = "season_weekly_xp_fill"
        laneRoot.addChild(fill)
    }

    private func addMissionRow(_ mission: SeasonMissionInstance, y: Int) {
        let progress = season.progress.missionProgress[mission.instanceID, default: 0]
        let complete = progress >= mission.definition.target
        addLabel(complete ? "✓" : "□", x: 36, y: y, size: 8, color: complete ? PixelPalette.recoveryGreen : PixelPalette.lightIron, alignment: .left, parent: laneRoot)
        addLabel(mission.definition.titleKo, x: 54, y: y, size: 8, color: PixelPalette.workWhite, alignment: .left, parent: laneRoot, name: "season_daily_\(mission.definition.id)")
        addLabel("\(progress)/\(mission.definition.target)  +\(mission.definition.xp) XP", x: 316, y: y, size: 7, color: complete ? PixelPalette.recoveryGreen : PixelPalette.lightTeal, alignment: .right, parent: laneRoot)
    }

    private func addRewardRow(_ tier: SeasonDefinition.RewardTier, y: Int) {
        addLabel("\(tier.level)", x: 36, y: y + 24, size: 9, color: PixelPalette.warningAmber, alignment: .left, parent: laneRoot, name: "season_tier_\(tier.level)")
        addRewardCell(tier.free, level: tier.level, track: .free, x: 62, y: y)
        addRewardCell(tier.premium, level: tier.level, track: .premium, x: 190, y: y)
    }

    private func addRewardCell(
        _ reward: SeasonDefinition.Reward,
        level: Int,
        track: SeasonRewardTrack,
        x: Int,
        y: Int
    ) {
        let prefix: String
        let trackName: String
        switch track {
        case .free:
            prefix = "season_claim_free_"
            trackName = "무료"
        case .premium:
            prefix = "season_claim_premium_"
            trackName = "PASS"
        }
        let name = prefix + String(level)
        let cell = PixelArt.panel(size: Self.rewardHitSize, name: name)
        cell.position = CGPoint(x: x, y: y)
        cell.name = name
        laneRoot.addChild(cell)
        addHitArea(name: name, position: CGPoint(x: x, y: y), size: Self.rewardHitSize, parent: laneRoot)
        addLabel(trackName + " • " + compactReward(reward), x: x + 8, y: y + 31, size: 7, color: PixelPalette.workWhite, alignment: .left, parent: laneRoot, name: name)
        addLabel(rewardState(level: level, track: track), x: x + 114, y: y + 14, size: 7, color: rewardStateColor(level: level, track: track), alignment: .right, parent: laneRoot, name: name)
    }

    private func addPageControls(maximumPage: Int) {
        addHitArea(name: "season_page_previous", position: CGPoint(x: 28, y: 160), size: CGSize(width: 104, height: 44), parent: laneRoot)
        addHitArea(name: "season_page_next", position: CGPoint(x: 228, y: 160), size: CGSize(width: 104, height: 44), parent: laneRoot)
        addLabel("〈 이전 5단계", x: 34, y: 182, size: 8, color: tierPage > 0 ? PixelPalette.warningAmber : PixelPalette.midIron, alignment: .left, parent: laneRoot, name: "season_page_previous")
        addLabel("다음 5단계 〉", x: 326, y: 182, size: 8, color: tierPage < maximumPage ? PixelPalette.warningAmber : PixelPalette.midIron, alignment: .right, parent: laneRoot, name: "season_page_next")
        addLabel("\(tierPage + 1)/\(maximumPage + 1)", x: 180, y: 182, size: 8, color: PixelPalette.lightTeal, alignment: .center, parent: laneRoot, name: "season_page_index")
    }

    private func rewardState(level: Int, track: SeasonRewardTrack) -> String {
        guard let progress = save.seasonProgress else { return "잠금" }
        let trackValue: String
        switch track {
        case .free: trackValue = "free"
        case .premium: trackValue = "premium"
        }
        let key = "\(progress.activeSeasonID):\(trackValue):\(level)"
        if progress.claimedRewardKeys.contains(key) { return "수령 완료" }
        guard let definition = catalog.definition(id: progress.activeSeasonID),
              let tier = definition.rewardTiers.first(where: { $0.level == level }),
              progress.totalXP >= tier.xpRequired
        else { return "XP 잠금" }
        if case .premium = track, !premiumUnlocked { return "권한 필요" }
        return "수령 〉"
    }

    private func rewardStateColor(level: Int, track: SeasonRewardTrack) -> SKColor {
        let state = rewardState(level: level, track: track)
        if state == "수령 〉" { return PixelPalette.warningAmber }
        if state == "수령 완료" { return PixelPalette.recoveryGreen }
        return PixelPalette.midIron
    }

    private func compactReward(_ reward: SeasonDefinition.Reward) -> String {
        switch reward.kind {
        case .currency where reward.itemID == "credits": return "고철 \(reward.amount)"
        case .material where reward.itemID == "parts": return "부품 \(reward.amount)"
        case .material where reward.itemID == "circuit": return "회로 \(reward.amount)"
        case .material where reward.itemID == "alloy": return "합금 \(reward.amount)"
        case .material where reward.itemID == "stellar_core": return "별 코어 \(reward.amount)"
        case .story: return "이야기 기록"
        case .cosmetic: return "외형"
        case .convenience: return "편의 슬롯"
        default: return reward.itemID
        }
    }

    private func remainingText(_ snapshot: SeasonSnapshot) -> String {
        switch snapshot.phase {
        case .active:
            let remaining = max(0, snapshot.definition.endsAt.timeIntervalSince(nowProvider()))
            let days = Int(remaining / (24 * 60 * 60))
            let hours = Int(remaining / (60 * 60)) % 24
            return "남은 기간 \(days)일 \(hours)시간"
        case .upcoming: return "시작 대기"
        case .ended: return "종료 • 도감 보존"
        case .transitionHeld: return "시간 확인 • 전환 보류"
        }
    }

    private func phaseColor(_ phase: SeasonSnapshot.Phase) -> SKColor {
        switch phase {
        case .active: PixelPalette.recoveryGreen
        case .upcoming: PixelPalette.lightTeal
        case .ended: PixelPalette.lightIron
        case .transitionHeld: PixelPalette.sparkOrange
        }
    }

    private func rebuildTabletRails() {
        railRoot.removeAllChildren()
        guard viewport.usesTabletRails,
              let snapshot = try? season.snapshot(at: nowProvider(), clockSuspect: save.idleOperations.clockSuspect)
        else { return }
        let leftX = viewport.laneFrame.minX - 150
        let rightX = viewport.laneFrame.maxX + 16
        addRail(
            name: "season_mission_rail",
            title: "MISSION / 오늘",
            lines: snapshot.dailyMissions.map { metricName($0.definition.metric) + "  " + progressText($0) },
            x: leftX,
            accent: PixelPalette.lightTeal
        )
        let records = season.progress.codexRecords.suffix(3).map { $0.titleKo + "  T\($0.highestTier)" }
        addRail(
            name: "season_archive_rail",
            title: "ARCHIVE / 도감",
            lines: records.isEmpty ? ["종료 시즌 없음", "XP와 최고 단계 보존"] : Array(records),
            x: rightX,
            accent: PixelPalette.warningAmber
        )
    }

    private func addRail(name: String, title: String, lines: [String], x: CGFloat, accent: SKColor) {
        let panel = PixelArt.panel(size: CGSize(width: 134, height: 210), name: name)
        panel.position = CGPoint(x: floor(x), y: floor(viewport.safeFrame.midY - 105))
        railRoot.addChild(panel)
        addLabel(title, x: Int(x + 10), y: Int(viewport.safeFrame.midY + 72), size: 8, color: accent, alignment: .left, parent: railRoot, name: name)
        for (index, line) in lines.prefix(4).enumerated() {
            addLabel(line, x: Int(x + 10), y: Int(viewport.safeFrame.midY + 32 - CGFloat(index * 38)), size: 7, color: PixelPalette.workWhite, alignment: .left, parent: railRoot, name: name)
        }
    }

    private func missionText(_ mission: SeasonMissionInstance) -> String {
        mission.definition.titleKo + " " + progressText(mission)
    }

    private func progressText(_ mission: SeasonMissionInstance) -> String {
        "\(season.progress.missionProgress[mission.instanceID, default: 0])/\(mission.definition.target)"
    }

    private func metricName(_ metric: SeasonMetric) -> String {
        switch metric {
        case .dismantleEnemy: "괴수 해체"
        case .salvagePart: "부품 회수"
        case .manualSalvage: "직접 해체"
        case .crewAttack: "직원 공격"
        case .clearStage: "스테이지"
        case .facilityJob: "시설 작업"
        case .defeatBoss: "보스 격파"
        case .expeditionComplete: "원정 귀환"
        }
    }

    private func claimLevel(from name: String, prefix: String) -> Int? {
        guard name.hasPrefix(prefix) else { return nil }
        return Int(name.dropFirst(prefix.count))
    }

    private func addHitArea(name: String, position: CGPoint, size: CGSize, parent: SKNode) {
        let hit = SKSpriteNode(color: .clear, size: size)
        hit.anchorPoint = .zero
        hit.position = position
        hit.zPosition = 6
        hit.name = name
        parent.addChild(hit)
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
        name: String? = nil
    ) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.horizontalAlignmentMode = alignment
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: x, y: y)
        label.zPosition = 7
        label.name = name
        parent.addChild(label)
        return label
    }
}

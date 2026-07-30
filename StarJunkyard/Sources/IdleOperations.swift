import Foundation
import UserNotifications

enum IdleOperationKind: String, Codable, CaseIterable, Sendable {
    case research
    case craft
    case expedition

    var nameKo: String {
        switch self {
        case .research: "연구"
        case .craft: "제작"
        case .expedition: "원정"
        }
    }
}

struct IdleOperationReward: Codable, Equatable, Sendable {
    let credits: Int
    let parts: Int
    let circuits: Int
    let alloy: Int
    let researchID: String?
}

struct TimedIdleOperation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: IdleOperationKind
    let recipeID: String
    let title: String
    let startedAt: Date
    var completesAt: Date
    let reward: IdleOperationReward
}

struct IdleOperationsState: Codable, Equatable, Sendable {
    var workbenchSlots: Int
    var expeditionSlots: Int
    var active: [TimedIdleOperation]
    var completedResearchIDs: [String]
    var circuits: Int
    var alloy: Int
    var lastObservedAt: Date
    var clockSuspect: Bool

    static func newGame(now: Date = Date()) -> IdleOperationsState {
        IdleOperationsState(
            workbenchSlots: 2,
            expeditionSlots: 1,
            active: [],
            completedResearchIDs: [],
            circuits: 0,
            alloy: 0,
            lastObservedAt: now,
            clockSuspect: false
        )
    }
}

struct DailyInstantFinishState: Codable, Equatable, Sendable {
    var utcDayKey: String?
    var consumedOperationIDs: [String]

    static let empty = DailyInstantFinishState(utcDayKey: nil, consumedOperationIDs: [])

    mutating func refresh(for date: Date) {
        let key = Self.dayKey(for: date)
        guard utcDayKey != key else { return }
        utcDayKey = key
        consumedOperationIDs = []
    }

    func remainingUses(on date: Date, entitled: Bool) -> Int {
        guard entitled else { return 0 }
        guard utcDayKey == Self.dayKey(for: date) else { return 1 }
        return consumedOperationIDs.isEmpty ? 1 : 0
    }

    static func dayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

enum IdleOperationError: Error, Equatable {
    case slotFull
    case alreadyRunning
    case notComplete
    case freeFinishUnavailable
    case clockSuspect
    case dailyTicketUnavailable
    case dailyTicketAlreadyUsed
}

enum IdleOperationsRules {
    static let freeFinishWindow: TimeInterval = 3 * 60
    static let notificationPermissionThreshold: TimeInterval = 10 * 60
    static let rollbackTolerance: TimeInterval = 5 * 60

    static func template(for kind: IdleOperationKind) -> (recipeID: String, title: String, duration: TimeInterval, reward: IdleOperationReward) {
        switch kind {
        case .research:
            (
                "reuse_protocol_1",
                "재사용 프로토콜 I",
                5 * 60,
                IdleOperationReward(credits: 0, parts: 0, circuits: 0, alloy: 0, researchID: "reuse_protocol_1")
            )
        case .craft:
            (
                "alloy_batch_1",
                "재생 합금 묶음",
                15 * 60,
                IdleOperationReward(credits: 0, parts: 0, circuits: 0, alloy: 1, researchID: nil)
            )
        case .expedition:
            (
                "back_alley_sweep",
                "끝골목 잔해 수색",
                30 * 60,
                IdleOperationReward(credits: 120, parts: 42, circuits: 3, alloy: 0, researchID: nil)
            )
        }
    }

    static func remainingSeconds(_ operation: TimedIdleOperation, now: Date) -> Int {
        max(0, Int(ceil(operation.completesAt.timeIntervalSince(now))))
    }

    static func canFinishFree(_ operation: TimedIdleOperation, now: Date) -> Bool {
        let remaining = operation.completesAt.timeIntervalSince(now)
        return remaining > 0 && remaining <= freeFinishWindow
    }

    static func duration(for kind: IdleOperationKind, craftSpeedMultiplier: Double = 1) -> TimeInterval {
        let base = template(for: kind).duration
        guard kind == .craft else { return base }
        return base / max(1, craftSpeedMultiplier)
    }
}

enum IdleOperationsEngine {
    static func observe(now: Date, state: inout IdleOperationsState) {
        if now.timeIntervalSince(state.lastObservedAt) < -IdleOperationsRules.rollbackTolerance {
            state.clockSuspect = true
            return
        }
        if now >= state.lastObservedAt {
            state.lastObservedAt = now
            state.clockSuspect = false
        }
    }

    @discardableResult
    static func start(
        _ kind: IdleOperationKind,
        now: Date,
        identifier: String = UUID().uuidString,
        craftSpeedMultiplier: Double = 1,
        state: inout IdleOperationsState
    ) throws -> TimedIdleOperation {
        observe(now: now, state: &state)
        guard !state.clockSuspect else { throw IdleOperationError.clockSuspect }
        if kind != .craft, state.active.contains(where: { $0.kind == kind }) {
            throw IdleOperationError.alreadyRunning
        }
        let usedSlots: Int
        let slotLimit: Int
        switch kind {
        case .research, .craft:
            usedSlots = state.active.filter { $0.kind == .research || $0.kind == .craft }.count
            slotLimit = max(0, state.workbenchSlots)
        case .expedition:
            usedSlots = state.active.filter { $0.kind == .expedition }.count
            slotLimit = max(0, state.expeditionSlots)
        }
        guard usedSlots < slotLimit else { throw IdleOperationError.slotFull }
        let template = IdleOperationsRules.template(for: kind)
        let operation = TimedIdleOperation(
            id: identifier,
            kind: kind,
            recipeID: template.recipeID,
            title: template.title,
            startedAt: now,
            completesAt: now.addingTimeInterval(
                IdleOperationsRules.duration(for: kind, craftSpeedMultiplier: craftSpeedMultiplier)
            ),
            reward: template.reward
        )
        state.active.append(operation)
        return operation
    }

    static func finishFree(id: String, now: Date, state: inout IdleOperationsState) throws {
        observe(now: now, state: &state)
        guard !state.clockSuspect else { throw IdleOperationError.clockSuspect }
        guard let index = state.active.firstIndex(where: { $0.id == id }),
              IdleOperationsRules.canFinishFree(state.active[index], now: now)
        else { throw IdleOperationError.freeFinishUnavailable }
        state.active[index].completesAt = now
    }

    static func finishWithDailyTicket(
        id: String,
        now: Date,
        entitled: Bool,
        ticket: inout DailyInstantFinishState,
        state: inout IdleOperationsState
    ) throws {
        observe(now: now, state: &state)
        guard !state.clockSuspect else { throw IdleOperationError.clockSuspect }
        guard entitled else { throw IdleOperationError.dailyTicketUnavailable }
        guard let index = state.active.firstIndex(where: { $0.id == id }),
              state.active[index].completesAt > now
        else { throw IdleOperationError.notComplete }
        ticket.refresh(for: now)
        guard ticket.consumedOperationIDs.isEmpty else { throw IdleOperationError.dailyTicketAlreadyUsed }
        ticket.consumedOperationIDs = [id]
        state.active[index].completesAt = now
    }

    @discardableResult
    static func claim(id: String, now: Date, state: inout IdleOperationsState) throws -> IdleOperationReward {
        observe(now: now, state: &state)
        guard !state.clockSuspect else { throw IdleOperationError.clockSuspect }
        guard let index = state.active.firstIndex(where: { $0.id == id }),
              state.active[index].completesAt <= now
        else { throw IdleOperationError.notComplete }
        let operation = state.active.remove(at: index)
        state.circuits += operation.reward.circuits
        state.alloy += operation.reward.alloy
        if let researchID = operation.reward.researchID,
           !state.completedResearchIDs.contains(researchID) {
            state.completedResearchIDs.append(researchID)
            state.completedResearchIDs.sort()
        }
        return operation.reward
    }
}

protocol IdleOperationNotificationScheduling: AnyObject, Sendable {
    func operationStarted(_ operation: TimedIdleOperation)
}

final class IOSIdleOperationNotificationScheduler: IdleOperationNotificationScheduling, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func operationStarted(_ operation: TimedIdleOperation) {
        let duration = operation.completesAt.timeIntervalSince(operation.startedAt)
        guard duration >= IdleOperationsRules.notificationPermissionThreshold else { return }
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.schedule(operation)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { self.schedule(operation) }
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private func schedule(_ operation: TimedIdleOperation) {
        let content = UNMutableNotificationContent()
        content.title = "작업 완료 • " + operation.kind.nameKo
        content.body = operation.title + " 보상을 회수할 수 있습니다."
        content.sound = .default
        let interval = max(1, operation.completesAt.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: "idle-operation-" + operation.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        center.add(request)
    }
}

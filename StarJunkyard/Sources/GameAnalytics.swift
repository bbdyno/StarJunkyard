import Foundation

enum AnalyticsConsent: String, Sendable {
    case unknown
    case denied
    case granted
}

enum GameAnalyticsEventName: String, CaseIterable, Sendable {
    case appLaunched = "app_launched"
    case saveSelected = "save_selected"
    case combatStarted = "combat_started"
    case enemyDismantled = "enemy_dismantled"
    case shelterMilestoneReached = "shelter_milestone_reached"
    case storyStepViewed = "story_step_viewed"
    case settingChanged = "setting_changed"
    case purchaseFlowStarted = "purchase_flow_started"
    case purchaseCompleted = "purchase_completed"
}

enum GameAnalyticsParameterKey: String, Hashable, Sendable {
    case saveKind = "save_kind"
    case stage
    case enemyID = "enemy_id"
    case enemyClass = "enemy_class"
    case milestone
    case storyStep = "story_step"
    case setting
    case enabled
    case productID = "product_id"
}

enum GameAnalyticsValue: Equatable, Sendable {
    case integer(Int)
    case boolean(Bool)
    case identifier(String)
}

struct GameAnalyticsEvent: Equatable, Sendable {
    let name: GameAnalyticsEventName
    let parameters: [GameAnalyticsParameterKey: GameAnalyticsValue]

    init(
        _ name: GameAnalyticsEventName,
        parameters: [GameAnalyticsParameterKey: GameAnalyticsValue] = [:]
    ) {
        self.name = name
        self.parameters = parameters
    }
}

protocol GameAnalytics: Sendable {
    func record(_ event: GameAnalyticsEvent)
}

struct NoOpGameAnalytics: GameAnalytics {
    func record(_ event: GameAnalyticsEvent) {}
}

final class LocalGameAnalyticsRecorder: GameAnalytics, @unchecked Sendable {
    private let capacity: Int
    private let lock = NSLock()
    private var events: [GameAnalyticsEvent] = []

    init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    func record(_ event: GameAnalyticsEvent) {
        lock.withLock {
            events.append(event)
            if events.count > capacity {
                events.removeFirst(events.count - capacity)
            }
        }
    }

    func snapshot() -> [GameAnalyticsEvent] {
        lock.withLock { events }
    }
}

final class AnalyticsConsentStore: @unchecked Sendable {
    static let storageKey = "starjunkyard.analytics-consent.v1"

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = AnalyticsConsentStore.storageKey) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> AnalyticsConsent {
        guard let rawValue = defaults.string(forKey: storageKey) else { return .unknown }
        return AnalyticsConsent(rawValue: rawValue) ?? .unknown
    }

    func save(_ consent: AnalyticsConsent) {
        defaults.set(consent.rawValue, forKey: storageKey)
    }
}

final class ConsentGatedGameAnalytics: GameAnalytics, @unchecked Sendable {
    private let consentStore: AnalyticsConsentStore
    private let destination: any GameAnalytics

    init(consentStore: AnalyticsConsentStore, destination: any GameAnalytics) {
        self.consentStore = consentStore
        self.destination = destination
    }

    func record(_ event: GameAnalyticsEvent) {
        guard consentStore.load() == .granted else { return }
        destination.record(event)
    }
}

extension GameAnalyticsEvent {
    static let appLaunched = GameAnalyticsEvent(.appLaunched)

    static func combatStarted(stage: Int) -> GameAnalyticsEvent {
        GameAnalyticsEvent(.combatStarted, parameters: [.stage: .integer(stage)])
    }

    static func enemyDismantled(id: String, enemyClass: String, stage: Int) -> GameAnalyticsEvent {
        GameAnalyticsEvent(
            .enemyDismantled,
            parameters: [
                .enemyID: .identifier(id),
                .enemyClass: .identifier(enemyClass),
                .stage: .integer(stage)
            ]
        )
    }

    static func shelterMilestone(_ milestone: Int) -> GameAnalyticsEvent {
        GameAnalyticsEvent(.shelterMilestoneReached, parameters: [.milestone: .integer(milestone)])
    }
}

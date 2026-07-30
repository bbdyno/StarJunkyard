import Foundation

struct GameSettings: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var musicEnabled: Bool
    var soundEffectsEnabled: Bool
    var hapticsEnabled: Bool
    var reduceMotion: Bool
    var reduceScreenShake: Bool
    var singleTapActions: Bool

    static let `default` = GameSettings(
        schemaVersion: currentSchemaVersion,
        musicEnabled: true,
        soundEffectsEnabled: true,
        hapticsEnabled: true,
        reduceMotion: false,
        reduceScreenShake: false,
        singleTapActions: false
    )

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case musicEnabled
        case soundEffectsEnabled
        case hapticsEnabled
        case reduceMotion
        case reduceScreenShake
        case singleTapActions
    }

    init(
        schemaVersion: Int = currentSchemaVersion,
        musicEnabled: Bool = true,
        soundEffectsEnabled: Bool = true,
        hapticsEnabled: Bool = true,
        reduceMotion: Bool = false,
        reduceScreenShake: Bool = false,
        singleTapActions: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.musicEnabled = musicEnabled
        self.soundEffectsEnabled = soundEffectsEnabled
        self.hapticsEnabled = hapticsEnabled
        self.reduceMotion = reduceMotion
        self.reduceScreenShake = reduceScreenShake
        self.singleTapActions = singleTapActions
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = Self.currentSchemaVersion
        musicEnabled = try values.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? true
        soundEffectsEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundEffectsEnabled) ?? true
        hapticsEnabled = try values.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        reduceMotion = try values.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        reduceScreenShake = try values.decodeIfPresent(Bool.self, forKey: .reduceScreenShake) ?? false
        singleTapActions = try values.decodeIfPresent(Bool.self, forKey: .singleTapActions) ?? false
    }
}

enum GameMotionPolicy {
    static func allowsDecorativeMotion(settings: GameSettings) -> Bool {
        !settings.reduceMotion
    }

    static func allowsScreenShake(settings: GameSettings) -> Bool {
        !settings.reduceScreenShake
    }

    static func transitionDuration(_ duration: TimeInterval, settings: GameSettings) -> TimeInterval {
        settings.reduceMotion ? 0 : duration
    }
}

protocol GameSettingsProviding: Sendable {
    func load() -> GameSettings
}

final class GameSettingsStore: GameSettingsProviding, @unchecked Sendable {
    static let storageKey = "starjunkyard.game-settings.v1"

    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, storageKey: String = GameSettingsStore.storageKey) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> GameSettings {
        lock.withLock {
            decodeStoredSettings()
        }
    }

    @discardableResult
    func save(_ settings: GameSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(settings) else { return false }
        lock.withLock {
            defaults.set(data, forKey: storageKey)
        }
        return true
    }

    @discardableResult
    func update(_ change: (inout GameSettings) -> Void) -> GameSettings {
        lock.withLock {
            var settings = decodeStoredSettings()
            change(&settings)
            settings.schemaVersion = GameSettings.currentSchemaVersion
            if let data = try? JSONEncoder().encode(settings) {
                defaults.set(data, forKey: storageKey)
            }
            return settings
        }
    }

    func reset() {
        lock.withLock {
            defaults.removeObject(forKey: storageKey)
        }
    }

    private func decodeStoredSettings() -> GameSettings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(GameSettings.self, from: data)
        else { return .default }
        return decoded
    }
}

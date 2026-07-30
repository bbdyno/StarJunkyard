import AVFoundation
import UIKit

enum GameFeedbackEvent: Sendable {
    case manualSalvage
    case enemyDismantled
    case recoveryMilestone
}

enum GameFeedbackPolicy {
    static func allowsSound(for event: GameFeedbackEvent, settings: GameSettings) -> Bool {
        settings.soundEffectsEnabled
    }

    static func allowsHaptic(for event: GameFeedbackEvent, settings: GameSettings) -> Bool {
        settings.hapticsEnabled
    }
}

@MainActor
protocol GameFeedbackPlaying: AnyObject {
    func perform(_ event: GameFeedbackEvent)
}

@MainActor
final class IOSGameFeedbackService: GameFeedbackPlaying {
    private let settings: any GameSettingsProviding
    private let audio = ToneAudioService()

    init(settings: any GameSettingsProviding) {
        self.settings = settings
    }

    func perform(_ event: GameFeedbackEvent) {
        let currentSettings = settings.load()
        if GameFeedbackPolicy.allowsSound(for: event, settings: currentSettings) {
            audio.play(event)
        }
        if GameFeedbackPolicy.allowsHaptic(for: event, settings: currentSettings) {
            playHaptic(event)
        }
    }

    private func playHaptic(_ event: GameFeedbackEvent) {
        switch event {
        case .manualSalvage:
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        case .enemyDismantled:
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 0.75)
        case .recoveryMilestone:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
    }
}

@MainActor
private final class ToneAudioService {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isConfigured = false

    func play(_ event: GameFeedbackEvent) {
        guard configureIfNeeded() else { return }
        let descriptor: (frequency: Double, duration: Double, volume: Float)
        switch event {
        case .manualSalvage: descriptor = (440, 0.035, 0.08)
        case .enemyDismantled: descriptor = (180, 0.075, 0.12)
        case .recoveryMilestone: descriptor = (660, 0.16, 0.10)
        }
        guard let buffer = makeBuffer(
            frequency: descriptor.frequency,
            duration: descriptor.duration,
            volume: descriptor.volume
        ) else { return }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured { return engine.isRunning || startEngine() }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            isConfigured = true
            return true
        } catch {
            return false
        }
    }

    private func startEngine() -> Bool {
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private func makeBuffer(frequency: Double, duration: Double, volume: Float) -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let progress = Double(frame) / Double(max(1, Int(frameCount) - 1))
            let envelope = Float(1 - progress)
            samples[frame] = sin(Float(2 * Double.pi * frequency * Double(frame) / sampleRate)) * volume * envelope
        }
        return buffer
    }
}

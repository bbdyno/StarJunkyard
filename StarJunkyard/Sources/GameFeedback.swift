import AVFoundation
import UIKit

enum GameFeedbackEvent: Sendable, Equatable {
    case settingChanged
    case manualSalvage
    case enemyDismantled
    case recoveryMilestone
    case bossPhaseBreak
    case bossDismantled
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
    private let music = PixelAmbientMusicService()

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

    func syncMusic() {
        music.setEnabled(settings.load().musicEnabled)
    }

    private func playHaptic(_ event: GameFeedbackEvent) {
        switch event {
        case .settingChanged:
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
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
        case .bossPhaseBreak:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred(intensity: 0.9)
        case .bossDismantled:
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
        case .settingChanged: descriptor = (520, 0.045, 0.07)
        case .manualSalvage: descriptor = (440, 0.035, 0.08)
        case .enemyDismantled: descriptor = (180, 0.075, 0.12)
        case .recoveryMilestone: descriptor = (660, 0.16, 0.10)
        case .bossPhaseBreak: descriptor = (120, 0.11, 0.14)
        case .bossDismantled: descriptor = (780, 0.22, 0.12)
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

@MainActor
private final class PixelAmbientMusicService {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var configured = false

    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            player.stop()
            return
        }
        guard configureIfNeeded(), !player.isPlaying, let buffer = makeLoopBuffer() else { return }
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.play()
    }

    private func configureIfNeeded() -> Bool {
        if configured {
            if engine.isRunning { return true }
            do {
                try engine.start()
                return true
            } catch {
                return false
            }
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.18
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            configured = true
            return true
        } catch {
            return false
        }
    }

    private func makeLoopBuffer() -> AVAudioPCMBuffer? {
        let sampleRate = 22_050.0
        let duration = 4.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        let notes = [110.0, 146.83, 164.81, 146.83, 123.47, 164.81, 196.0, 164.81]
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let note = notes[min(notes.count - 1, Int(time / 0.5))]
            let pulse = sin(2 * Double.pi * note * time) >= 0 ? 1.0 : -1.0
            let bed = sin(2 * Double.pi * 55 * time)
            samples[frame] = Float((pulse * 0.018) + (bed * 0.012))
        }
        return buffer
    }
}

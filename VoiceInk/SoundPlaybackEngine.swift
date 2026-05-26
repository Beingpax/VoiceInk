import Foundation
@preconcurrency import AVFoundation
import os

final class SoundPlaybackEngine: @unchecked Sendable {
    private enum Sound {
        case start
        case stop
        case esc
    }

    private let queue = DispatchQueue(label: "com.prakashjoshipax.voiceink.soundPlayback", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SoundPlaybackEngine")

    private var startSound: AVAudioPlayer?
    private var stopSound: AVAudioPlayer?
    private var escSound: AVAudioPlayer?
    private var customStartSound: AVAudioPlayer?
    private var customStopSound: AVAudioPlayer?

    func setup(
        defaultStartURL: URL?,
        defaultStopURL: URL?,
        defaultEscURL: URL?,
        customStartURL: URL?,
        customStopURL: URL?
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            self.startSound = self.makePlayer(from: defaultStartURL, volume: 0.4)
            self.stopSound = self.makePlayer(from: defaultStopURL, volume: 0.4)
            self.escSound = self.makePlayer(from: defaultEscURL, volume: 0.3)
            self.reloadCustomSoundsOnQueue(startURL: customStartURL, stopURL: customStopURL)
        }
    }

    func reloadCustomSounds(startURL: URL?, stopURL: URL?) {
        queue.async { [weak self] in
            self?.reloadCustomSoundsOnQueue(startURL: startURL, stopURL: stopURL)
        }
    }

    func playStartSound() {
        play(.start)
    }

    func playStopSound() {
        play(.stop)
    }

    func playEscSound() {
        play(.esc)
    }

    private func reloadCustomSoundsOnQueue(startURL: URL?, stopURL: URL?) {
        if customStartSound?.isPlaying == true {
            customStartSound?.stop()
        }
        if customStopSound?.isPlaying == true {
            customStopSound?.stop()
        }

        customStartSound = makePlayer(from: startURL, volume: 0.4)
        customStopSound = makePlayer(from: stopURL, volume: 0.4)
    }

    private func play(_ sound: Sound) {
        queue.async { [weak self] in
            guard let self else { return }

            let player: AVAudioPlayer?
            switch sound {
            case .start:
                player = self.customStartSound ?? self.startSound
            case .stop:
                player = self.customStopSound ?? self.stopSound
            case .esc:
                player = self.escSound
            }

            player?.play()
        }
    }

    private func makePlayer(from url: URL?, volume: Float) -> AVAudioPlayer? {
        guard let url else { return nil }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            return player
        } catch {
            logger.error("Failed to load sound: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

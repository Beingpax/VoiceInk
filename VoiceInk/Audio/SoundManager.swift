import Foundation
import AVFoundation
import SwiftUI

@MainActor
class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private var startSound: AVAudioPlayer?
    private var stopSound: AVAudioPlayer?
    private var escSound: AVAudioPlayer?
    private var customStartSound: AVAudioPlayer?
    private var customStopSound: AVAudioPlayer?

    @AppStorage("isSoundFeedbackEnabled") private var isSoundFeedbackEnabled = true

    private init() {
        Task(priority: .background) {
            await setupSounds()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadCustomSounds),
            name: NSNotification.Name("CustomSoundsChanged"),
            object: nil
        )
    }

    func setupSounds() async {
        if let startSoundURL = Bundle.main.url(forResource: "recstart", withExtension: "mp3"),
           let stopSoundURL = Bundle.main.url(forResource: "recstop", withExtension: "mp3"),
           let escSoundURL = Bundle.main.url(forResource: "esc", withExtension: "wav") {
            try? await loadSounds(start: startSoundURL, stop: stopSoundURL, esc: escSoundURL)
        }

        await reloadCustomSoundsAsync()
    }

    @objc private func reloadCustomSounds() {
        Task {
            await reloadCustomSoundsAsync()
        }
    }

    private func loadAndPreparePlayer(from url: URL?) -> AVAudioPlayer? {
        guard let url = url else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.4
        player?.prepareToPlay()
        return player
    }

    private func reloadCustomSoundsAsync() async {
        if customStartSound?.isPlaying == true {
            customStartSound?.stop()
        }
        if customStopSound?.isPlaying == true {
            customStopSound?.stop()
        }

        customStartSound = loadAndPreparePlayer(from: CustomSoundManager.shared.getCustomSoundURL(for: .start))
        customStopSound = loadAndPreparePlayer(from: CustomSoundManager.shared.getCustomSoundURL(for: .stop))
    }

    private func loadSounds(start startURL: URL, stop stopURL: URL, esc escURL: URL) async throws {
        do {
            startSound = try AVAudioPlayer(contentsOf: startURL)
            stopSound = try AVAudioPlayer(contentsOf: stopURL)
            escSound = try AVAudioPlayer(contentsOf: escURL)

            await MainActor.run {
                startSound?.prepareToPlay()
                stopSound?.prepareToPlay()
                escSound?.prepareToPlay()
            }

            startSound?.volume = 0.4
            stopSound?.volume = 0.4
            escSound?.volume = 0.3
        } catch {
            throw error
        }
    }

    func playStartSound() {
        guard isSoundFeedbackEnabled else { return }

        if let custom = customStartSound {
            custom.play()
        } else {
            startSound?.volume = 0.4
            startSound?.play()
        }
    }

    func playStopSound() {
        guard isSoundFeedbackEnabled else { return }

        if let custom = customStopSound {
            custom.play()
        } else {
            stopSound?.volume = 0.4
            stopSound?.play()
        }
    }
    
    func playEscSound() {
        guard isSoundFeedbackEnabled else { return }
        escSound?.volume = 0.3
        escSound?.play()
    }
    
    var isEnabled: Bool {
        get { isSoundFeedbackEnabled }
        set {
            objectWillChange.send()
            isSoundFeedbackEnabled = newValue
        }
    }
} 

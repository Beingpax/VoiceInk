import Foundation
import SwiftUI

@MainActor
class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private let playbackEngine = SoundPlaybackEngine()
    @AppStorage("isSoundFeedbackEnabled") private var isSoundFeedbackEnabled = true

    private init() {
        setupSounds()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadCustomSounds),
            name: NSNotification.Name("CustomSoundsChanged"),
            object: nil
        )
    }

    private func setupSounds() {
        playbackEngine.setup(
            defaultStartURL: Bundle.main.url(forResource: "recstart", withExtension: "mp3"),
            defaultStopURL: Bundle.main.url(forResource: "recstop", withExtension: "mp3"),
            defaultEscURL: Bundle.main.url(forResource: "esc", withExtension: "wav"),
            customStartURL: CustomSoundManager.shared.getCustomSoundURL(for: .start),
            customStopURL: CustomSoundManager.shared.getCustomSoundURL(for: .stop)
        )
    }

    @objc private func reloadCustomSounds() {
        playbackEngine.reloadCustomSounds(
            startURL: CustomSoundManager.shared.getCustomSoundURL(for: .start),
            stopURL: CustomSoundManager.shared.getCustomSoundURL(for: .stop)
        )
    }

    func playStartSound() {
        guard isSoundFeedbackEnabled else { return }
        playbackEngine.playStartSound()
    }

    func playStopSound() {
        guard isSoundFeedbackEnabled else { return }
        playbackEngine.playStopSound()
    }
    
    func playEscSound() {
        guard isSoundFeedbackEnabled else { return }
        playbackEngine.playEscSound()
    }
    
    var isEnabled: Bool {
        get { isSoundFeedbackEnabled }
        set {
            objectWillChange.send()
            isSoundFeedbackEnabled = newValue
        }
    }
} 

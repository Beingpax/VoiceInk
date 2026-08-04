import AVFoundation
import Combine
import Foundation

final class AudioPlayerManager: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var waveformSamples: [Float] = []
    @Published var isLoadingWaveform = false
    @Published var playbackRate: Float = {
        let saved = UserDefaults.standard.float(forKey: "audioPlaybackRate")
        return saved > 0 ? saved : 1.0
    }() {
        didSet { UserDefaults.standard.set(playbackRate, forKey: "audioPlaybackRate") }
    }

    func loadAudio(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.enableRate = true
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            isLoadingWaveform = true

            Task {
                let samples = await WaveformGenerator.generateWaveformSamples(from: url)
                await MainActor.run {
                    self.waveformSamples = samples
                    self.isLoadingWaveform = false
                }
            }
        } catch {
            print("Error loading audio: \(error.localizedDescription)")
        }
    }

    func play() {
        audioPlayer?.rate = playbackRate
        audioPlayer?.play()
        isPlaying = true
        startTimer()
    }

    func cyclePlaybackRate() {
        switch playbackRate {
        case 1.0: playbackRate = 1.5
        case 1.5: playbackRate = 2.0
        default: playbackRate = 1.0
        }
        audioPlayer?.rate = playbackRate
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentTime = self.audioPlayer?.currentTime ?? 0
            if self.currentTime >= self.duration {
                self.pause()
                self.seek(to: 0)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func cleanup() {
        stopTimer()
        audioPlayer?.stop()
        audioPlayer = nil
    }

    deinit {
        cleanup()
    }
}

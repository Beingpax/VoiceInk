@preconcurrency import AVFoundation
import Combine

@MainActor
class AudioPlayerService: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var error: Error?
    
    // MARK: - Private Properties
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    // MARK: - Callbacks
    var didFinishPlaying: (() -> Void)?
    
    // MARK: - Initialization
    override init() {
        super.init()
        // Audio session setup is not needed on macOS
        // AVAudioSession is iOS-only
    }
    
    // MARK: - Public Methods
    func loadAudio(from data: Data) async throws {
        isBuffering = true
        
        do {
            // Stop any existing playback
            stop()
            
            // Create new audio player
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            // Update duration
            duration = audioPlayer?.duration ?? 0
            
            // Enable rate adjustment
            audioPlayer?.enableRate = true
            
            isBuffering = false
        } catch {
            isBuffering = false
            self.error = error
            throw error
        }
    }
    
    func loadAudio(from url: URL) async throws {
        isBuffering = true
        
        do {
            // Stop any existing playback
            stop()
            
            // Create new audio player
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            // Update duration
            duration = audioPlayer?.duration ?? 0
            
            // Enable rate adjustment
            audioPlayer?.enableRate = true
            
            isBuffering = false
        } catch {
            isBuffering = false
            self.error = error
            throw error
        }
    }
    
    func play() {
        guard let player = audioPlayer else { return }
        
        player.play()
        isPlaying = true
        startTimer()
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0
        isPlaying = false
        stopTimer()
    }
    
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
    }
    
    func setVolume(_ volume: Float) {
        audioPlayer?.volume = max(0, min(1, volume))
    }
    
    func setPlaybackRate(_ rate: Float) {
        guard let player = audioPlayer else { return }
        
        player.rate = max(0.5, min(2.0, rate))
    }
    
    // MARK: - Timer Management
    private func startTimer() {
        stopTimer()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else { return }
                
                self.currentTime = player.currentTime
                
                // Check if playback has finished
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Cleanup
    @MainActor deinit {
        timer?.invalidate()
        audioPlayer?.stop()
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioPlayerService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopTimer()
            self.didFinishPlaying?()
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.error = error
            self.isPlaying = false
            self.stopTimer()
        }
    }
}

// MARK: - Audio Format Support
extension AudioPlayerService {
    static var supportedFormats: [String] {
        return ["mp3", "wav", "aac", "m4a", "flac", "aiff", "caf"]
    }
    
    static func isFormatSupported(_ format: String) -> Bool {
        return supportedFormats.contains(format.lowercased())
    }
}

// MARK: - Audio Analysis
extension AudioPlayerService {
    func getAudioInfo() -> AudioInfo? {
        guard let player = audioPlayer else { return nil }
        
        return AudioInfo(
            duration: player.duration,
            currentTime: player.currentTime,
            volume: player.volume,
            rate: player.rate,
            numberOfChannels: player.numberOfChannels,
            isPlaying: player.isPlaying
        )
    }
}

struct AudioInfo {
    let duration: TimeInterval
    let currentTime: TimeInterval
    let volume: Float
    let rate: Float
    let numberOfChannels: Int
    let isPlaying: Bool
    
    var formattedDuration: String {
        formatTime(duration)
    }
    
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

import Foundation
import AVFoundation
import CoreAudio

/// Test harness for audio system testing without requiring real hardware
@available(macOS 14.0, *)
final class AudioTestHarness {
    
    // MARK: - Simulated Audio Devices
    
    struct SimulatedDevice {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let isInput: Bool
        let sampleRate: Double
        
        static func createTestDevice(
            name: String = "Test Microphone",
            uid: String = UUID().uuidString
        ) -> SimulatedDevice {
            // Use a high ID to avoid conflicts with real devices
            let deviceID = AudioDeviceID(arc4random_uniform(10000) + 20000)
            return SimulatedDevice(
                id: deviceID,
                uid: uid,
                name: name,
                isInput: true,
                sampleRate: 16000.0
            )
        }
    }
    
    // MARK: - Audio Buffer Generation
    
    /// Generate silent audio buffer
    static func generateSilence(
        duration: TimeInterval,
        sampleRate: Double = 16000.0,
        channels: Int = 1
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        )!
        
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        // Zero out the buffer (silence)
        if let channelData = buffer.int16ChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                memset(channelData[channel], 0, Int(frameCount) * MemoryLayout<Int16>.size)
            }
        }
        
        return buffer
    }
    
    /// Generate white noise audio buffer
    static func generateWhiteNoise(
        duration: TimeInterval,
        sampleRate: Double = 16000.0,
        amplitude: Float = 0.1
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        if let channelData = buffer.floatChannelData {
            for i in 0..<Int(frameCount) {
                channelData[0][i] = Float.random(in: -amplitude...amplitude)
            }
        }
        
        return buffer
    }
    
    /// Generate sine wave audio buffer
    static func generateSineWave(
        frequency: Double = 440.0,
        duration: TimeInterval,
        sampleRate: Double = 16000.0,
        amplitude: Float = 0.5
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        if let channelData = buffer.floatChannelData {
            for i in 0..<Int(frameCount) {
                let time = Double(i) / sampleRate
                let value = amplitude * Float(sin(2.0 * .pi * frequency * time))
                channelData[0][i] = value
            }
        }
        
        return buffer
    }
    
    /// Generate speech-like audio (combination of frequencies)
    static func generateSpeechLike(
        duration: TimeInterval,
        sampleRate: Double = 16000.0
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        // Mix multiple frequencies typical of human speech
        let fundamentalFreq = 120.0 // Hz
        let formants = [800.0, 1200.0, 2500.0] // Typical formant frequencies
        
        if let channelData = buffer.floatChannelData {
            for i in 0..<Int(frameCount) {
                let time = Double(i) / sampleRate
                var sample: Float = 0.0
                
                // Add fundamental
                sample += 0.3 * Float(sin(2.0 * .pi * fundamentalFreq * time))
                
                // Add formants
                for formant in formants {
                    sample += 0.1 * Float(sin(2.0 * .pi * formant * time))
                }
                
                // Add some noise for realism
                sample += 0.05 * Float.random(in: -1...1)
                
                // Normalize
                channelData[0][i] = sample / Float(formants.count + 2)
            }
        }
        
        return buffer
    }
    
    // MARK: - Audio File Creation
    
    /// Create a test audio file
    static func createTestAudioFile(
        at url: URL,
        type: AudioType = .silence,
        duration: TimeInterval = 1.0,
        sampleRate: Double = 16000.0
    ) throws {
        let buffer: AVAudioPCMBuffer
        
        switch type {
        case .silence:
            buffer = generateSilence(duration: duration, sampleRate: sampleRate)
        case .whiteNoise:
            buffer = generateWhiteNoise(duration: duration, sampleRate: sampleRate)
        case .sineWave(let frequency):
            buffer = generateSineWave(frequency: frequency, duration: duration, sampleRate: sampleRate)
        case .speechLike:
            buffer = generateSpeechLike(duration: duration, sampleRate: sampleRate)
        }
        
        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: buffer.format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )
        
        try audioFile.write(from: buffer)
    }
    
    enum AudioType {
        case silence
        case whiteNoise
        case sineWave(frequency: Double)
        case speechLike
    }
    
    // MARK: - Audio Level Simulation
    
    /// Simulate audio levels for testing
    struct AudioLevelSimulator {
        private var currentLevel: Float = 0.0
        private var targetLevel: Float = 0.0
        private var smoothingFactor: Float = 0.3
        
        mutating func setTarget(_ level: Float) {
            targetLevel = max(0.0, min(1.0, level))
        }
        
        mutating func getNextLevel() -> Float {
            currentLevel += (targetLevel - currentLevel) * smoothingFactor
            return currentLevel
        }
        
        mutating func simulate(pattern: LevelPattern, duration: TimeInterval) -> [Float] {
            let sampleCount = Int(duration * 10) // 10 samples per second
            var levels: [Float] = []
            
            for i in 0..<sampleCount {
                let progress = Double(i) / Double(sampleCount)
                
                switch pattern {
                case .constant(let level):
                    setTarget(level)
                case .ramp(let start, let end):
                    setTarget(start + Float(progress) * (end - start))
                case .pulse(let high, let low, let period):
                    let phase = (progress * period).truncatingRemainder(dividingBy: 1.0)
                    setTarget(phase < 0.5 ? high : low)
                case .random(let min, let max):
                    setTarget(Float.random(in: min...max))
                }
                
                levels.append(getNextLevel())
            }
            
            return levels
        }
    }
    
    enum LevelPattern {
        case constant(Float)
        case ramp(start: Float, end: Float)
        case pulse(high: Float, low: Float, period: Double)
        case random(min: Float, max: Float)
    }
    
    // MARK: - Audio Format Testing
    
    /// Test various audio format conversions
    static func testFormatConversion(
        sourceFormat: AVAudioCommonFormat,
        targetFormat: AVAudioCommonFormat,
        sampleRate: Double = 16000.0
    ) throws -> Bool {
        let sourceAudioFormat = AVAudioFormat(
            commonFormat: sourceFormat,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let targetAudioFormat = AVAudioFormat(
            commonFormat: targetFormat,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let converter = AVAudioConverter(from: sourceAudioFormat, to: targetAudioFormat)
        return converter != nil
    }
    
    // MARK: - Device State Simulation
    
    class DeviceStateSimulator {
        enum DeviceEvent {
            case connected
            case disconnected
            case selectedAsDefault
            case formatChanged
        }
        
        private var eventHandlers: [(DeviceEvent) -> Void] = []
        
        func onEvent(_ handler: @escaping (DeviceEvent) -> Void) {
            eventHandlers.append(handler)
        }
        
        func simulate(_ event: DeviceEvent) {
            for handler in eventHandlers {
                handler(event)
            }
        }
    }
    
    // MARK: - Audio Metrics
    
    /// Calculate RMS (Root Mean Square) of audio buffer
    static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0.0
        
        for i in 0..<frameLength {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        
        return sqrt(sum / Float(frameLength))
    }
    
    /// Calculate peak level of audio buffer
    static func calculatePeak(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        
        let frameLength = Int(buffer.frameLength)
        var peak: Float = 0.0
        
        for i in 0..<frameLength {
            let sample = abs(channelData[0][i])
            peak = max(peak, sample)
        }
        
        return peak
    }
    
    /// Detect if audio buffer contains speech-like content
    static func detectSpeech(buffer: AVAudioPCMBuffer, threshold: Float = 0.01) -> Bool {
        let rms = calculateRMS(buffer: buffer)
        return rms > threshold
    }
}

// MARK: - Audio Engine Mock

@available(macOS 14.0, *)
class MockAudioEngine {
    var isRunning = false
    private var mockInput: AVAudioPCMBuffer?
    
    func start() throws {
        isRunning = true
    }
    
    func stop() {
        isRunning = false
    }
    
    func setMockInput(_ buffer: AVAudioPCMBuffer) {
        mockInput = buffer
    }
    
    func simulateInput() -> AVAudioPCMBuffer? {
        return mockInput
    }
}

import Foundation
@preconcurrency import AVFoundation
import CoreAudio
import os

@MainActor
class AudioEngineRecorder: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioEngineRecorder")

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    nonisolated(unsafe) private var audioFile: AVAudioFile?
    nonisolated(unsafe) private var recordingFormat: AVAudioFormat?
    nonisolated(unsafe) private var converter: AVAudioConverter?

    private var isRecording = false
    private var recordingURL: URL?

    @Published var currentAveragePower: Float = 0.0
    @Published var currentPeakPower: Float = 0.0

    private let tapBufferSize: AVAudioFrameCount = 4096
    private let tapBusNumber: AVAudioNodeBus = 0

    private let audioProcessingQueue = DispatchQueue(label: "com.prakashjoshipax.VoiceInk.audioProcessing", qos: .userInitiated)
    private let fileWriteLock = NSLock()

    // Callback to notify parent class of runtime recording errors
    var onRecordingError: ((Error) -> Void)?

    init() {
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    private func startEngineWithRetry(_ engine: AVAudioEngine, maxAttempts: Int = 3) throws {
        var lastError: Error?
        let baseDelay: TimeInterval = 0.1 // 100ms

        for attempt in 0..<maxAttempts {
            do {
                try engine.start()
                if attempt > 0 {
                    logger.notice("🎙️ Audio engine started successfully on attempt \(attempt + 1)")
                }
                return
            } catch {
                lastError = error
                logger.warning("🎙️ Failed to start audio engine (attempt \(attempt + 1)/\(maxAttempts)): \(error.localizedDescription)")

                if attempt < maxAttempts - 1 {
                    let delay = baseDelay * Double(attempt + 1) // Linear: 100ms, 200ms, 300ms...
                    Thread.sleep(forTimeInterval: delay)
                }
            }
        }

        throw lastError ?? AudioEngineRecorderError.failedToStartEngine(NSError(domain: "AudioEngineRecorder", code: -1))
    }

    @objc private func handleConfigurationChange(notification: Notification) {
        Task { @MainActor in
            guard isRecording else { return }
            logger.notice("🎙️ AVAudioEngine configuration change detected (e.g. sample rate change). Restarting engine...")
            do {
                try restartRecordingPreservingFile()
            } catch {
                logger.error("🎙️ Failed to recover from configuration change: \(error.localizedDescription)")
                stopRecording()
            }
        }
    }

    func startRecording(toOutputFile url: URL) throws {
        stopRecording()

        let engine = AVAudioEngine()
        audioEngine = engine

        // Get input format before prepare(), but don't store the node reference yet
        let inputFormat = engine.inputNode.outputFormat(forBus: tapBusNumber)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            logger.error("🎙️ Invalid input format: sample rate or channel count is zero")
            throw AudioEngineRecorderError.invalidInputFormat
        }

        guard let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        ) else {
            logger.error("🎙️ Failed to create desired recording format")
            throw AudioEngineRecorderError.invalidRecordingFormat
        }

        recordingURL = url

        let createdAudioFile: AVAudioFile
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            createdAudioFile = try AVAudioFile(
                forWriting: url,
                settings: desiredFormat.settings,
                commonFormat: desiredFormat.commonFormat,
                interleaved: desiredFormat.isInterleaved
            )
        } catch {
            logger.error("🎙️ Failed to create audio file: \(error.localizedDescription)")
            throw AudioEngineRecorderError.failedToCreateFile(error)
        }

        guard let audioConverter = AVAudioConverter(from: inputFormat, to: desiredFormat) else {
            logger.error("🎙️ Failed to create audio format converter")
            throw AudioEngineRecorderError.failedToCreateConverter
        }

        fileWriteLock.lock()
        recordingFormat = desiredFormat
        audioFile = createdAudioFile
        converter = audioConverter
        fileWriteLock.unlock()

        // Prepare the engine before accessing nodes
        engine.prepare()

        // Re-access inputNode after prepare() as recommended by Apple
        let input = engine.inputNode
        inputNode = input

        input.installTap(onBus: tapBusNumber, bufferSize: tapBufferSize, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }

            self.audioProcessingQueue.async {
                self.processAudioBuffer(buffer)
            }
        }

        do {
            try startEngineWithRetry(engine)
            isRecording = true
        } catch {
            logger.error("🎙️ Failed to start audio engine after retries: \(error.localizedDescription)")
            input.removeTap(onBus: tapBusNumber)
            throw AudioEngineRecorderError.failedToStartEngine(error)
        }
    }

    private func restartRecordingPreservingFile() throws {
        if let input = inputNode {
            input.removeTap(onBus: tapBusNumber)
        }
        audioEngine?.stop()

        // Drain queue to prevent old-format buffers racing with new converter
        audioProcessingQueue.sync { }

        let engine = AVAudioEngine()
        audioEngine = engine

        // Get input format before prepare(), but don't store the node reference yet
        let inputFormat = engine.inputNode.outputFormat(forBus: tapBusNumber)
        logger.notice("🎙️ Restarting with new input format - Sample Rate: \(inputFormat.sampleRate)")

        guard inputFormat.sampleRate > 0 else {
            throw AudioEngineRecorderError.invalidInputFormat
        }

        guard let format = recordingFormat else {
            throw AudioEngineRecorderError.invalidRecordingFormat
        }

        guard let newConverter = AVAudioConverter(from: inputFormat, to: format) else {
            throw AudioEngineRecorderError.failedToCreateConverter
        }

        fileWriteLock.lock()
        converter = newConverter
        fileWriteLock.unlock()

        // Prepare the engine before accessing nodes
        engine.prepare()

        // Re-access inputNode after prepare() as recommended by Apple
        let input = engine.inputNode
        inputNode = input

        input.installTap(onBus: tapBusNumber, bufferSize: tapBufferSize, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            self.audioProcessingQueue.async {
                self.processAudioBuffer(buffer)
            }
        }

        try startEngineWithRetry(engine)
        logger.notice("🎙️ Audio engine successfully restarted after configuration change")
    }

    func stopRecording() {
        guard isRecording else {
            return
        }

        if let input = inputNode {
            input.removeTap(onBus: tapBusNumber)
        }

        audioEngine?.stop()

        // Wait for pending buffers to finish processing before clearing resources
        audioProcessingQueue.sync { }

        fileWriteLock.lock()
        audioFile = nil
        converter = nil
        recordingFormat = nil
        fileWriteLock.unlock()

        audioEngine = nil
        inputNode = nil
        recordingURL = nil
        isRecording = false

        currentAveragePower = 0.0
        currentPeakPower = 0.0
    }

    nonisolated private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        updateMeters(from: buffer)
        writeBufferToFile(buffer)
    }

    nonisolated private func writeBufferToFile(_ buffer: AVAudioPCMBuffer) {
        fileWriteLock.lock()
        defer { fileWriteLock.unlock() }

        guard let audioFile = audioFile,
              let converter = converter,
              let format = recordingFormat else {
            return
        }

        let inputSampleRate = buffer.format.sampleRate
        let outputSampleRate = format.sampleRate
        let ratio = outputSampleRate / inputSampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputCapacity) else {
            logger.error("🎙️ Failed to create converted buffer")
            Task { @MainActor in
                self.onRecordingError?(AudioEngineRecorderError.bufferConversionFailed)
            }
            return
        }

        var error: NSError?
        var hasProvidedBuffer = false

        converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            if hasProvidedBuffer {
                outStatus.pointee = .noDataNow
                return nil
            } else {
                hasProvidedBuffer = true
                outStatus.pointee = .haveData
                return buffer
            }
        }

        if let error = error {
            logger.error("🎙️ Audio conversion error: \(error.localizedDescription)")
            Task { @MainActor in
                self.onRecordingError?(AudioEngineRecorderError.audioConversionError(error))
            }
            return
        }

        do {
            try audioFile.write(from: convertedBuffer)
        } catch {
            logger.error("🎙️ Failed to write buffer to file: \(error.localizedDescription)")
            Task { @MainActor in
                self.onRecordingError?(AudioEngineRecorderError.fileWriteFailed(error))
            }
        }
    }

    nonisolated private func updateMeters(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard channelCount > 0, frameLength > 0 else { return }

        let channel = channelData[0]
        var sum: Float = 0.0
        var peak: Float = 0.0

        for frame in 0..<frameLength {
            let sample = channel[frame]
            let absSample = abs(sample)

            if absSample > peak {
                peak = absSample
            }

            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))

        let averagePowerDb = 20.0 * log10(max(rms, 0.000001))
        let peakPowerDb = 20.0 * log10(max(peak, 0.000001))

        Task { @MainActor in
            self.currentAveragePower = averagePowerDb
            self.currentPeakPower = peakPowerDb
        }
    }

    var isCurrentlyRecording: Bool {
        return isRecording
    }

    var currentRecordingURL: URL? {
        return recordingURL
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Error Types

enum AudioEngineRecorderError: LocalizedError {
    case invalidInputFormat
    case invalidRecordingFormat
    case failedToCreateFile(Error)
    case failedToCreateConverter
    case failedToStartEngine(Error)
    case bufferConversionFailed
    case audioConversionError(Error)
    case fileWriteFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat:
            return "Invalid audio input format from device"
        case .invalidRecordingFormat:
            return "Failed to create recording format"
        case .failedToCreateFile(let error):
            return "Failed to create audio file: \(error.localizedDescription)"
        case .failedToCreateConverter:
            return "Failed to create audio format converter"
        case .failedToStartEngine(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .bufferConversionFailed:
            return "Failed to create buffer for audio conversion"
        case .audioConversionError(let error):
            return "Audio format conversion failed: \(error.localizedDescription)"
        case .fileWriteFailed(let error):
            return "Failed to write audio data to file: \(error.localizedDescription)"
        }
    }
}
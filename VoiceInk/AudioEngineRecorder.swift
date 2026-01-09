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

    @Published var currentAveragePower: Float = -160.0
    @Published var currentPeakPower: Float = -160.0

    private let tapBufferSize: AVAudioFrameCount = 4096
    private let tapBusNumber: AVAudioNodeBus = 0

    private let audioProcessingQueue = DispatchQueue(label: "com.prakashjoshipax.VoiceInk.audioProcessing", qos: .userInitiated)
    private let fileWriteLock = NSLock()

    private var configurationChangeObserver: NSObjectProtocol?
    private var isRecovering = false

    var onRecordingError: ((Error) -> Void)?

    func startRecording(toOutputFile url: URL) throws {
        stopRecording()

        let engine = AVAudioEngine()
        audioEngine = engine

        let input = engine.inputNode
        inputNode = input

        let inputFormat = input.outputFormat(forBus: tapBusNumber)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            logger.error("Invalid input format: sample rate or channel count is zero")
            throw AudioEngineRecorderError.invalidInputFormat
        }

        guard let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        ) else {
            logger.error("Failed to create desired recording format")
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
            logger.error("Failed to create audio file: \(error.localizedDescription)")
            throw AudioEngineRecorderError.failedToCreateFile(error)
        }

        guard let audioConverter = AVAudioConverter(from: inputFormat, to: desiredFormat) else {
            logger.error("Failed to create audio format converter")
            throw AudioEngineRecorderError.failedToCreateConverter
        }

        fileWriteLock.lock()
        recordingFormat = desiredFormat
        audioFile = createdAudioFile
        converter = audioConverter
        fileWriteLock.unlock()

        input.installTap(onBus: tapBusNumber, bufferSize: tapBufferSize, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }

            self.audioProcessingQueue.async {
                self.processAudioBuffer(buffer)
            }
        }

        engine.prepare()

        do {
            if !engine.isRunning {
                try engine.start()
            }
            isRecording = true
            setupConfigurationChangeObserver()
            logger.info("Recording started with input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            input.removeTap(onBus: tapBusNumber)
            throw AudioEngineRecorderError.failedToStartEngine(error)
        }
    }

    private func setupConfigurationChangeObserver() {
        removeConfigurationChangeObserver()

        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleConfigurationChange()
            }
        }
    }

    private func removeConfigurationChangeObserver() {
        if let observer = configurationChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationChangeObserver = nil
        }
    }

    private func handleConfigurationChange() {
        logger.warning("Audio engine configuration changed (device switch or Bluetooth profile change)")
        guard isRecording, !isRecovering else { return }

        isRecovering = true
        Task {
            defer { isRecovering = false }
            do {
                try await recoverFromConfigurationChange()
                logger.info("Successfully recovered from audio configuration change")
            } catch {
                logger.error("Failed to recover from configuration change: \(error.localizedDescription)")
                onRecordingError?(error)
            }
        }
    }

    /// Recreates audio engine while keeping audio file open for seamless recording continuation
    private func recoverFromConfigurationChange() async throws {
        removeConfigurationChangeObserver()
        inputNode?.removeTap(onBus: tapBusNumber)
        audioEngine?.stop()
        audioProcessingQueue.sync { }

        // Allow audio system to stabilize, especially for Bluetooth devices (non-blocking)
        try await Task.sleep(nanoseconds: 100_000_000)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: tapBusNumber)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            logger.error("Invalid input format after config change: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) ch")
            throw AudioEngineRecorderError.invalidInputFormat
        }

        fileWriteLock.lock()
        guard let format = recordingFormat else {
            fileWriteLock.unlock()
            throw AudioEngineRecorderError.invalidRecordingFormat
        }

        guard let newConverter = AVAudioConverter(from: inputFormat, to: format) else {
            fileWriteLock.unlock()
            throw AudioEngineRecorderError.failedToCreateConverter
        }
        converter = newConverter
        fileWriteLock.unlock()

        input.installTap(onBus: tapBusNumber, bufferSize: tapBufferSize, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            self.audioProcessingQueue.async {
                self.processAudioBuffer(buffer)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: tapBusNumber)
            throw AudioEngineRecorderError.failedToStartEngine(error)
        }

        audioEngine = engine
        inputNode = input
        setupConfigurationChangeObserver()

        logger.info("Engine recreated with format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) ch")
    }

    func stopRecording() {
        guard isRecording else { return }

        removeConfigurationChangeObserver()

        inputNode?.removeTap(onBus: tapBusNumber)
        audioEngine?.stop()
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
        isRecovering = false

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
              let format = recordingFormat else { return }

        guard buffer.frameLength > 0 else {
            logTapError(message: "Empty buffer received")
            return
        }

        let inputSampleRate = buffer.format.sampleRate
        let outputSampleRate = format.sampleRate
        let ratio = outputSampleRate / inputSampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputCapacity) else {
            logTapError(message: "Failed to create converted buffer")
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
            logTapError(message: "Audio conversion failed: \(error.localizedDescription)")
            return
        }

        do {
            try audioFile.write(from: convertedBuffer)
        } catch {
            logTapError(message: "File write failed: \(error.localizedDescription)")
        }
    }

    nonisolated private func logTapError(message: String) {
        logger.error("\(message)")
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

    var isCurrentlyRecording: Bool { isRecording }
    var currentRecordingURL: URL? { recordingURL }
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
    case configurationChanged

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
        case .configurationChanged:
            return "Audio device configuration changed during recording"
        }
    }
}
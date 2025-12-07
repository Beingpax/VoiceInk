import Foundation
import AVFoundation
import CoreAudio
import os

// MARK: - AudioEngineRecorder Delegate Protocol

protocol AudioEngineRecorderDelegate: AnyObject {
    func audioEngineRecorderDidFinishRecording(_ recorder: AudioEngineRecorder, successfully flag: Bool)
    func audioEngineRecorderEncodeErrorDidOccur(_ recorder: AudioEngineRecorder, error: Error?)
}

// MARK: - AudioEngineRecorder Errors

enum AudioEngineRecorderError: LocalizedError {
    case invalidFormat
    case failedToSetDevice(status: OSStatus)
    case audioUnitNotAvailable
    case engineNotPrepared
    case failedToCreateOutputFile
    case failedToCreateConverter
    case alreadyRecording

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid audio format configuration"
        case .failedToSetDevice(let status):
            return "Failed to set audio input device: \(status)"
        case .audioUnitNotAvailable:
            return "Audio unit not available"
        case .engineNotPrepared:
            return "Audio engine not prepared - call prepare() first"
        case .failedToCreateOutputFile:
            return "Failed to create output audio file"
        case .failedToCreateConverter:
            return "Failed to create audio format converter"
        case .alreadyRecording:
            return "Already recording - stop current recording first"
        }
    }
}

// MARK: - AudioEngineRecorder

@MainActor
class AudioEngineRecorder: NSObject {

    // MARK: - Properties

    private let audioEngine: AVAudioEngine
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioEngineRecorder")

    private var nativeFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat!

    private var audioConverter: AVAudioConverter?
    private var converterInputBuffer: AVAudioPCMBuffer?
    private var converterOutputBuffer: AVAudioPCMBuffer?

    private var outputFile: AVAudioFile?
    private var recordingURL: URL?

    private var averagePowerForChannel0: Float = -160.0
    private var peakPowerForChannel0: Float = -160.0
    var isMeteringEnabled = true

    private(set) var isRecording = false

    private var selectedDeviceID: AudioDeviceID?

    weak var delegate: AudioEngineRecorderDelegate?

    var url: URL? {
        return recordingURL
    }

    // MARK: - Initialization

    init(audioEngine: AVAudioEngine) {
        self.audioEngine = audioEngine
        super.init()

        // Create target format (16kHz mono Linear PCM - required for Whisper)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: true
        ) else {
            fatalError("Failed to create target audio format")
        }
        self.targetFormat = targetFormat
    }

    // MARK: - Preparation

    func prepare(deviceID: AudioDeviceID? = nil) throws {
        if let deviceID = deviceID {
            selectedDeviceID = deviceID
            try setInputDevice(deviceID)
        }

        let inputNode = audioEngine.inputNode
        nativeFormat = inputNode.inputFormat(forBus: 0)

        guard let nativeFormat = nativeFormat else {
            throw AudioEngineRecorderError.invalidFormat
        }

        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            throw AudioEngineRecorderError.failedToCreateConverter
        }
        audioConverter = converter

        let maxBufferSize: AVAudioFrameCount = 4096
        converterInputBuffer = AVAudioPCMBuffer(
            pcmFormat: nativeFormat,
            frameCapacity: maxBufferSize
        )

        let outputCapacity = AVAudioFrameCount(
            Double(maxBufferSize) * targetFormat.sampleRate / nativeFormat.sampleRate
        ) + 1024

        converterOutputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        )

        audioEngine.prepare()
    }

    // MARK: - Device Selection

    private func setInputDevice(_ deviceID: AudioDeviceID) throws {
        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            throw AudioEngineRecorderError.audioUnitNotAvailable
        }

        var deviceIDCopy = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDCopy,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            throw AudioEngineRecorderError.failedToSetDevice(status: status)
        }
    }

    // MARK: - Recording Control

    func startRecording(toOutputFile url: URL) throws {
        guard !isRecording else {
            throw AudioEngineRecorderError.alreadyRecording
        }

        guard audioConverter != nil else {
            throw AudioEngineRecorderError.engineNotPrepared
        }

        recordingURL = url

        do {
            outputFile = try AVAudioFile(
                forWriting: url,
                settings: targetFormat.settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
        } catch {
            throw AudioEngineRecorderError.failedToCreateOutputFile
        }

        let inputNode = audioEngine.inputNode
        guard let nativeFormat = nativeFormat else {
            throw AudioEngineRecorderError.invalidFormat
        }

        let bufferSize: AVAudioFrameCount = 1024

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nativeFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            if let convertedBuffer = self.convertBuffer(buffer) {
                do {
                    try self.outputFile?.write(from: convertedBuffer)
                } catch {
                    self.logger.error("Buffer write failed: \(error.localizedDescription)")
                    Task { @MainActor in
                        self.delegate?.audioEngineRecorderEncodeErrorDidOccur(self, error: error)
                    }
                }
            }

            if self.isMeteringEnabled {
                self.updateMetering(from: buffer)
            }
        }

        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        isRecording = false

        outputFile = nil
        delegate?.audioEngineRecorderDidFinishRecording(self, successfully: true)

        averagePowerForChannel0 = -160.0
        peakPowerForChannel0 = -160.0
    }

    // MARK: - Format Conversion

    private func convertBuffer(_ inputBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = audioConverter,
              let nativeFormat = nativeFormat else {
            return nil
        }

        let inputFrameCount = inputBuffer.frameLength
        let ratio = targetFormat.sampleRate / nativeFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(ceil(Double(inputFrameCount) * ratio))

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else {
            return nil
        }

        var error: NSError?
        var inputBufferProvided = false

        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            if inputBufferProvided {
                outStatus.pointee = .noDataNow
                return nil
            }

            inputBufferProvided = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let error = error {
            logger.error("Audio conversion failed: \(error.localizedDescription)")
            return nil
        }

        if status == .error {
            return nil
        }

        return outputBuffer
    }

    // MARK: - Metering (AVAudioRecorder API Compatibility)

    private func updateMetering(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard frameLength > 0 else { return }

        var sum: Float = 0
        var peak: Float = 0

        for frame in 0..<frameLength {
            var sample: Float = 0
            for channel in 0..<channelCount {
                sample += channelData[channel][frame]
            }
            sample /= Float(channelCount)

            let absSample = abs(sample)
            sum += absSample * absSample
            peak = max(peak, absSample)
        }

        let rms = sqrt(sum / Float(frameLength))

        let avgDb = rms > 0.000001 ? 20 * log10(rms) : -160.0
        let peakDb = peak > 0.000001 ? 20 * log10(peak) : -160.0

        let smoothingFactor: Float = 0.3
        averagePowerForChannel0 = (smoothingFactor * avgDb) + ((1.0 - smoothingFactor) * averagePowerForChannel0)
        peakPowerForChannel0 = max(peakDb, peakPowerForChannel0 * 0.95)
    }

    func updateMeters() {
    }

    func averagePower(forChannel channel: Int) -> Float {
        return averagePowerForChannel0
    }

    func peakPower(forChannel channel: Int) -> Float {
        return peakPowerForChannel0
    }

    // MARK: - Cleanup

    deinit {
        if isRecording {
            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            outputFile = nil
        }
    }
}

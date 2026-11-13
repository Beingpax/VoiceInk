import AVFoundation
import Foundation
import LLMkit
import os

/// Transcodes arbitrary audio into 16 kHz mono AAC (m4a) so long recordings fit Zoom Scribe Fast mode's request limit.
enum ZoomScribeAudioEncoder {
    static let sampleRate: Double = 16_000
    static let bitRate = 32_000
    private static let inputFrameCapacity: AVAudioFrameCount = 65_536
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ZoomScribe")

    static func transcodeToAAC(_ audioData: Data, inputExtension: String) throws -> Data {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "zoom-scribe-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let extensionName = inputExtension.isEmpty ? "audio" : inputExtension
        let inputURL = directory.appendingPathComponent("input").appendingPathExtension(extensionName)
        let outputURL = directory.appendingPathComponent("output").appendingPathExtension("m4a")

        do {
            try audioData.write(to: inputURL)
            try convert(inputURL: inputURL, outputURL: outputURL)
            return try Data(contentsOf: outputURL)
        } catch {
            logger.error(
                "Zoom Scribe transcode failed: \(error.localizedDescription, privacy: .public) (input extension: \(extensionName, privacy: .public), bytes: \(audioData.count, privacy: .public))"
            )
            throw LLMKitError.encodingError
        }
    }

    private static func convert(inputURL: URL, outputURL: URL) throws {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let inputFormat = inputFile.processingFormat
        let outputCapacity = AVAudioFrameCount(Double(inputFrameCapacity) * sampleRate / inputFormat.sampleRate) + 4_096

        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
            let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputFrameCapacity),
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity)
        else {
            logger.error(
                "Zoom Scribe transcode could not create converter or buffers (input format: \(inputFormat.description, privacy: .public))"
            )
            throw LLMKitError.encodingError
        }

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: bitRate,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        var conversionError: NSError?
        while true {
            try inputFile.read(into: inputBuffer)
            if inputBuffer.frameLength == 0 { break }

            var suppliedInput = false
            outputBuffer.frameLength = 0
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
                if suppliedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            guard status != .error, conversionError == nil else {
                logger.error(
                    "Zoom Scribe conversion failed (status: \(String(describing: status), privacy: .public), error: \(conversionError?.localizedDescription ?? "none", privacy: .public))"
                )
                throw LLMKitError.encodingError
            }
            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }
        }

        // Flush the resampler/encoder tail.
        outputBuffer.frameLength = 0
        _ = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            inputStatus.pointee = .endOfStream
            return nil
        }
        guard conversionError == nil else {
            logger.error(
                "Zoom Scribe tail flush failed (error: \(conversionError?.localizedDescription ?? "none", privacy: .public))"
            )
            throw LLMKitError.encodingError
        }
        if outputBuffer.frameLength > 0 {
            try outputFile.write(from: outputBuffer)
        }
    }
}

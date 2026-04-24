import Foundation
import AVFoundation

enum AudioExtractorError: Error {
    case unsupportedFormat
    case extractionFailed(String)
}

struct AudioExtractor {
    // Decodes any AVAudioFile-readable source (m4a, mp3, wav, mp4/mov with audio, etc.)
    // into a 16 kHz mono 16-bit PCM WAV. In-memory conversion is in Float32 mono —
    // AVAudioFile handles the Float32 → Int16 encoding when writing to disk.
    static func extractAudio(from sourceURL: URL, to destinationURL: URL) async throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let srcFile: AVAudioFile
        do {
            srcFile = try AVAudioFile(forReading: sourceURL)
        } catch {
            throw AudioExtractorError.unsupportedFormat
        }
        let srcFormat = srcFile.processingFormat

        // On-disk format: 16 kHz mono 16-bit little-endian PCM (WAV)
        let outSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        // In-memory processing format for buffers passed to AVAudioFile.write:
        // Float32 mono at 16 kHz, non-interleaved. AVAudioFile re-encodes to Int16 on disk.
        guard let procFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000,
                                             channels: 1,
                                             interleaved: false) else {
            throw AudioExtractorError.extractionFailed("Could not build processing format")
        }

        let outFile: AVAudioFile
        do {
            outFile = try AVAudioFile(
                forWriting: destinationURL,
                settings: outSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw AudioExtractorError.extractionFailed("Could not open output file: \(error.localizedDescription)")
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: procFormat) else {
            throw AudioExtractorError.extractionFailed("Could not build converter from \(srcFormat) to \(procFormat)")
        }

        let readCapacity: AVAudioFrameCount = 16_384
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: readCapacity) else {
            throw AudioExtractorError.extractionFailed("Could not allocate source buffer")
        }

        while srcFile.framePosition < srcFile.length {
            do {
                try srcFile.read(into: srcBuffer)
            } catch {
                throw AudioExtractorError.extractionFailed("Read failed: \(error.localizedDescription)")
            }
            if srcBuffer.frameLength == 0 { break }

            let ratio = procFormat.sampleRate / srcFormat.sampleRate
            let outCapacity = AVAudioFrameCount(Double(srcBuffer.frameLength) * ratio) + 1_024
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: procFormat, frameCapacity: outCapacity) else {
                throw AudioExtractorError.extractionFailed("Could not allocate output buffer")
            }

            var convError: NSError?
            var providedInput = false
            let status = converter.convert(to: outBuffer, error: &convError) { _, inputStatus in
                if providedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                providedInput = true
                inputStatus.pointee = .haveData
                return srcBuffer
            }

            if let convError {
                throw AudioExtractorError.extractionFailed("Converter error: \(convError.localizedDescription)")
            }
            if status == .error {
                throw AudioExtractorError.extractionFailed("Converter returned error status")
            }

            if outBuffer.frameLength > 0 {
                do {
                    try outFile.write(from: outBuffer)
                } catch {
                    throw AudioExtractorError.extractionFailed("Write failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

import Foundation
import AVFoundation
import os

class AudioProcessor {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioProcessor")
    
    struct AudioFormat {
        static let targetSampleRate: Double = 16000.0
        static let targetChannels: UInt32 = 1
        static let targetBitDepth: UInt32 = 16
    }
    
    enum AudioProcessingError: LocalizedError {
        case invalidAudioFile
        case conversionFailed
        case exportFailed
        case unsupportedFormat
        case sampleExtractionFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidAudioFile:
                return String(localized: "The audio file is invalid or corrupted")
            case .conversionFailed:
                return String(localized: "Failed to convert the audio format")
            case .exportFailed:
                return String(localized: "Failed to export the processed audio")
            case .unsupportedFormat:
                return String(localized: "The audio format is not supported")
            case .sampleExtractionFailed:
                return String(localized: "Failed to extract audio samples")
            }
        }
    }
    
    func processAudioToSamples(_ url: URL) async throws -> [Float] {
        do {
            return try readUsingAudioFile(url)
        } catch {
            // AVAudioFile can choke on some container/codec combinations that
            // the media stack can otherwise play (e.g. avfaudio error -50 on
            // certain mp4/m4a meeting recordings, issue #799). AVAssetReader
            // is a more resilient fallback for media containers and delivers
            // target LPCM directly, avoiding manual seeking and conversion.
            logger.warning("AVAudioFile pipeline failed for \(url.lastPathComponent, privacy: .public): \(error, privacy: .public). Falling back to AVAssetReader.")
            return try await readUsingAssetReader(url)
        }
    }

    private func readUsingAudioFile(_ url: URL) throws -> [Float] {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            throw AudioProcessingError.invalidAudioFile
        }

        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let channels = format.channelCount
        let totalFrames = audioFile.length
        
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioFormat.targetSampleRate,
            channels: AudioFormat.targetChannels,
            interleaved: false
        )
        
        guard let outputFormat = outputFormat else {
            throw AudioProcessingError.unsupportedFormat
        }
        
        let chunkSize: AVAudioFrameCount = 50_000_000
        var allSamples: [Float] = []
        var currentFrame: AVAudioFramePosition = 0
        
        while currentFrame < totalFrames {
            let remainingFrames = totalFrames - currentFrame
            let framesToRead = min(chunkSize, AVAudioFrameCount(remainingFrames))
            
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
                throw AudioProcessingError.conversionFailed
            }
            
            audioFile.framePosition = currentFrame
            try audioFile.read(into: inputBuffer, frameCount: framesToRead)
            
            if sampleRate == AudioFormat.targetSampleRate && channels == AudioFormat.targetChannels {
                let chunkSamples = convertToWhisperFormat(inputBuffer)
                allSamples.append(contentsOf: chunkSamples)
            } else {
                guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
                    throw AudioProcessingError.conversionFailed
                }
                
                let ratio = AudioFormat.targetSampleRate / sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
                
                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
                    throw AudioProcessingError.conversionFailed
                }
                
                var error: NSError?
                let status = converter.convert(
                    to: outputBuffer,
                    error: &error,
                    withInputFrom: { inNumPackets, outStatus in
                        outStatus.pointee = .haveData
                        return inputBuffer
                    }
                )
                
                if let error = error {
                    throw AudioProcessingError.conversionFailed
                }
                
                if status == .error {
                    throw AudioProcessingError.conversionFailed
                }
                
                let chunkSamples = convertToWhisperFormat(outputBuffer)
                allSamples.append(contentsOf: chunkSamples)
            }
            
            currentFrame += AVAudioFramePosition(framesToRead)
        }
        
        return allSamples
    }

    private func readUsingAssetReader(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        // Match the legacy behavior of processing one stream by using the
        // primary audio track rather than attempting to mix multiple tracks.
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioProcessingError.invalidAudioFile
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioFormat.targetSampleRate,
            AVNumberOfChannelsKey: AudioFormat.targetChannels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw AudioProcessingError.conversionFailed
        }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? AudioProcessingError.sampleExtractionFailed
        }

        var samples: [Float] = []
        do {
            while let sampleBuffer = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                try validateAssetReaderOutputFormat(sampleBuffer)

                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
                let byteCount = CMBlockBufferGetDataLength(blockBuffer)
                guard byteCount >= MemoryLayout<Float>.size else { continue }

                var chunk = [Float](repeating: 0, count: byteCount / MemoryLayout<Float>.size)
                let status = chunk.withUnsafeMutableBytes { destination in
                    CMBlockBufferCopyDataBytes(
                        blockBuffer,
                        atOffset: 0,
                        dataLength: destination.count,
                        destination: destination.baseAddress!
                    )
                }
                guard status == kCMBlockBufferNoErr else {
                    throw AudioProcessingError.sampleExtractionFailed
                }
                samples.append(contentsOf: chunk)
            }
        } catch {
            reader.cancelReading()
            throw error
        }

        if reader.status == .failed {
            throw reader.error ?? AudioProcessingError.sampleExtractionFailed
        }
        if reader.status == .cancelled {
            throw CancellationError()
        }
        guard !samples.isEmpty else {
            throw AudioProcessingError.sampleExtractionFailed
        }

        // Keep the fallback output in the same normalized Float range expected
        // by the WAV export path.
        let maxSample = samples.map(abs).max() ?? 1
        if maxSample > 0 {
            samples = samples.map { $0 / maxSample }
        }
        return samples
    }

    private func validateAssetReaderOutputFormat(_ sampleBuffer: CMSampleBuffer) throws {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            throw AudioProcessingError.sampleExtractionFailed
        }

        let format = streamDescription.pointee
        let isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isBigEndian = (format.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0
        let isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        guard
            format.mFormatID == kAudioFormatLinearPCM,
            format.mSampleRate == AudioFormat.targetSampleRate,
            format.mChannelsPerFrame == AudioFormat.targetChannels,
            format.mBitsPerChannel == 32,
            isFloat,
            !isBigEndian,
            !isNonInterleaved
        else {
            throw AudioProcessingError.conversionFailed
        }
    }

    private func convertToWhisperFormat(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var samples = Array(repeating: Float(0), count: frameLength)
        
        if channelCount == 1 {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            for frame in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channelData[channel][frame]
                }
                samples[frame] = sum / Float(channelCount)
            }
        }
        
        let maxSample = samples.map(abs).max() ?? 1
        if maxSample > 0 {
            samples = samples.map { $0 / maxSample }
        }
        
        return samples
    }
    func saveSamplesAsWav(samples: [Float], to url: URL) throws {
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: AudioFormat.targetSampleRate,
            channels: AudioFormat.targetChannels,
            interleaved: true
        )

        guard let outputFormat = outputFormat else {
            throw AudioProcessingError.unsupportedFormat
        }

        let buffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        )
        
        guard let buffer = buffer else {
            throw AudioProcessingError.conversionFailed
        }
        
        // Convert float samples to int16
        let int16Samples = samples.map { max(-1.0, min(1.0, $0)) * Float(Int16.max) }.map { Int16($0) }

        // Copy samples to buffer
        int16Samples.withUnsafeBufferPointer { int16Buffer in
            let int16Pointer = int16Buffer.baseAddress!
            buffer.int16ChannelData![0].update(from: int16Pointer, count: int16Samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        // Create audio file
        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        try audioFile.write(from: buffer)
    }
} 

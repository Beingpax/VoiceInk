import Foundation
import CoreML
import AVFoundation
import FluidAudio
import os.log

class FluidAudioTranscriptionService: TranscriptionService {
    private var asrManager: AsrManager?
    private var vadManager: VadManager?
    private var activeVersion: AsrModelVersion?
    private var cachedModels: AsrModels?
    private var loadingTask: (version: AsrModelVersion, task: Task<AsrModels, Error>)?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FluidAudioTranscriptionService")

    private func version(for model: any TranscriptionModel) -> AsrModelVersion {
        FluidAudioModelManager.asrVersion(for: model.name)
    }

    static func languageHint(from selectedLanguage: String?, model: any TranscriptionModel) -> Language? {
        guard model.provider == .fluidAudio else {
            return nil
        }
        return FluidAudioModelManager.languageHint(from: selectedLanguage, for: model.name)
    }

    private func ensureModelsLoaded(for version: AsrModelVersion) async throws {
        if asrManager != nil, activeVersion == version {
            return
        }

        // Clean up existing manager but preserve cachedModels for reuse
        await asrManager?.cleanup()
        asrManager = nil
        vadManager = nil
        activeVersion = nil

        let models = try await getOrLoadModels(for: version)

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.asrManager = manager
        self.activeVersion = version
    }

    // Returns cached models or loads from disk; deduplicates concurrent loads
    func getOrLoadModels(for version: AsrModelVersion) async throws -> AsrModels {
        if let cached = cachedModels, cached.version == version {
            return cached
        }

        // Deduplicate concurrent loads for the same version
        if let (existingVersion, existingTask) = loadingTask, existingVersion == version {
            return try await existingTask.value
        }

        let task = Task {
            try await AsrModels.downloadAndLoad(
                configuration: nil,
                version: version
            )
        }
        loadingTask = (version, task)

        do {
            let models = try await task.value
            self.cachedModels = models
            // Only clear if we're still the current loading task
            if loadingTask?.version == version {
                self.loadingTask = nil
            }
            return models
        } catch {
            // Only clear if we're still the current loading task
            if loadingTask?.version == version {
                self.loadingTask = nil
            }
            throw error
        }
    }

    func loadModel(for model: FluidAudioModel) async throws {
        try await ensureModelsLoaded(for: version(for: model))
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let targetVersion = version(for: model)
        try await ensureModelsLoaded(for: targetVersion)

        guard let asrManager = asrManager else {
            throw ASRError.notInitialized
        }

        let languageHint = Self.languageHint(
            from: UserDefaults.standard.string(forKey: "SelectedLanguage"),
            model: model
        )
        let audioSamples = try readAudioSamples(from: audioURL)

        let durationSeconds = Double(audioSamples.count) / 16000.0
        let isVADEnabled = UserDefaults.standard.bool(forKey: "IsVADEnabled")
        let isWhisperModeEnabled = UserDefaults.standard.bool(forKey: "IsWhisperModeEnabled")

        var speechAudio = audioSamples
        if durationSeconds >= 20.0, isVADEnabled {
            let vadConfig = VadConfig(defaultThreshold: isWhisperModeEnabled ? 0.45 : 0.7)
            if vadManager == nil {
                do {
                    vadManager = try await VadManager(config: vadConfig)
                } catch {
                    logger.notice("VAD init failed; falling back to full audio: \(error.localizedDescription, privacy: .public)")
                    vadManager = nil
                }
            }

            if let vadManager {
                do {
                    let segments = try await vadManager.segmentSpeechAudio(audioSamples)
                    speechAudio = segments.isEmpty ? audioSamples : segments.flatMap { $0 }
                } catch {
                    logger.notice("VAD segmentation failed; using full audio: \(error.localizedDescription, privacy: .public)")
                    speechAudio = audioSamples
                }
            }
        }

        // Pad with 1s of silence to capture final punctuation at sequence boundary
        let trailingSilenceSamples = 16_000
        let maxSingleChunkSamples = 240_000
        if speechAudio.count + trailingSilenceSamples <= maxSingleChunkSamples {
            speechAudio += [Float](repeating: 0, count: trailingSilenceSamples)
        }

        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            speechAudio,
            decoderState: &decoderState,
            language: languageHint
        )

        return TextNormalizer.shared.normalizeSentence(result.text)
    }

    private func readAudioSamples(from url: URL) throws -> [Float] {
        do {
            let data = try Data(contentsOf: url)
            let dataOffset = findWAVDataChunkOffset(in: data)
            guard dataOffset > 0, data.count > dataOffset else {
                throw ASRError.invalidAudioData
            }

            let floats = stride(from: dataOffset, to: data.count, by: 2).map {
                return data[$0..<$0 + 2].withUnsafeBytes {
                    let short = Int16(littleEndian: $0.load(as: Int16.self))
                    return max(-1.0, min(Float(short) / 32767.0, 1.0))
                }
            }

            return floats
        } catch {
            throw ASRError.invalidAudioData
        }
    }

    /// Parse WAV file to find the actual PCM data chunk offset.
    /// WAV files may have extra chunks (LIST, fact, bext, etc.) before the "data" chunk.
    private func findWAVDataChunkOffset(in data: Data) -> Int {
        // Minimum WAV: RIFF(4) + size(4) + WAVE(4) + fmt (8+16) + data(8) = 44
        guard data.count >= 44 else { return -1 }

        // Verify RIFF header
        let riff = String(data: data[0..<4], encoding: .ascii)
        let wave = String(data: data[8..<12], encoding: .ascii)
        guard riff == "RIFF", wave == "WAVE" else { return -1 }

        // Walk chunks starting at offset 12
        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = String(data: data[offset..<offset+4], encoding: .ascii) ?? ""
            let chunkSize = data[offset+4..<offset+8].withUnsafeBytes {
                UInt32(littleEndian: $0.load(as: UInt32.self))
            }

            if chunkID == "data" {
                return offset + 8 // PCM data starts after chunk header
            }

            // Move to next chunk (chunks are word-aligned)
            let advance = 8 + Int(chunkSize)
            let aligned = advance + (advance % 2) // pad to even boundary
            offset += aligned
        }

        // Fallback to standard 44-byte offset if parsing fails
        return 44
    }

    // Releases ASR/VAD resources but preserves cached models for reuse
    func cleanup() async {
        if let manager = asrManager {
            await manager.cleanup()
        }
        asrManager = nil
        vadManager = nil
        activeVersion = nil
    }

}

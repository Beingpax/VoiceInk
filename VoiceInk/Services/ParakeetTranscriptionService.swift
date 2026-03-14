import Foundation
import CoreML
import AVFoundation
import FluidAudio
import os.log

class ParakeetTranscriptionService: TranscriptionService {
    private var asrManager: AsrManager?
    private var vadManager: VadManager?
    private var activeVersion: AsrModelVersion?
    private var cachedModels: AsrModels?
    /// Deduplicates concurrent calls to ensureModelsLoaded (model loading + AsrManager init).
    private var initTask: (version: AsrModelVersion, task: Task<Void, Error>)?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink.parakeet", category: "ParakeetTranscriptionService")

    private func version(for model: any TranscriptionModel) -> AsrModelVersion {
        model.name.lowercased().contains("v2") ? .v2 : .v3
    }

    private func ensureModelsLoaded(for version: AsrModelVersion) async throws {
        // Fast path: already initialized for this version
        if asrManager != nil, activeVersion == version {
            return
        }

        // If initialization is already in progress for this version, wait for it
        if let (v, task) = initTask, v == version {
            try await task.value
            // Re-check after waiting — the other caller may have succeeded
            if asrManager != nil, activeVersion == version {
                return
            }
        }

        // Double-check after possible suspension
        if asrManager != nil, activeVersion == version {
            return
        }

        // Clean up existing manager but preserve cachedModels for reuse
        asrManager?.cleanup()
        asrManager = nil
        vadManager = nil
        activeVersion = nil

        // Single task covers model loading AND AsrManager initialization.
        // Use Task.detached so the init is NOT cancelled when the caller's
        // Task context is cancelled (e.g. SwiftUI view teardown).
        let task = Task.detached { [weak self] () -> Void in
            guard let self else { throw ASRError.notInitialized }

            let models: AsrModels
            if let cached = self.cachedModels, cached.version == version {
                models = cached
            } else {
                models = try await AsrModels.loadFromCache(
                    configuration: nil,
                    version: version
                )
                self.cachedModels = models
            }

            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            self.asrManager = manager
            self.activeVersion = version
        }
        initTask = (version, task)

        do {
            try await task.value
            if initTask?.version == version { initTask = nil }
        } catch {
            if initTask?.version == version { initTask = nil }
            throw error
        }
    }

    /// Returns cached models or loads from disk. Used by streaming provider.
    func getOrLoadModels(for version: AsrModelVersion) async throws -> AsrModels {
        if let cached = cachedModels, cached.version == version {
            return cached
        }
        let models = try await AsrModels.loadFromCache(
            configuration: nil,
            version: version
        )
        cachedModels = models
        return models
    }

    func loadModel(for model: ParakeetModel) async throws {
        try await ensureModelsLoaded(for: version(for: model))
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        // Read audio samples synchronously before entering the detached task
        let audioSamples = try readAudioSamples(from: audioURL)
        let targetVersion = version(for: model)
        let isVADEnabled = UserDefaults.standard.bool(forKey: "IsVADEnabled")

        // Run all FluidAudio work in a detached task so it is NOT cancelled
        // when the caller's Task context is torn down (e.g. SwiftUI view lifecycle).
        let detachedResult = Task.detached { [weak self] () -> String in
            guard let self else { throw ASRError.notInitialized }

            // Retry once on CancellationError — FluidAudio can throw this during
            // concurrent model init or when internal resources are momentarily busy.
            do {
                try await self.ensureModelsLoaded(for: targetVersion)
            } catch is CancellationError {
                self.logger.notice("Model initialization threw CancellationError, resetting and retrying...")
                self.asrManager?.cleanup()
                self.asrManager = nil
                self.activeVersion = nil
                self.cachedModels = nil
                self.initTask = nil
                try await self.ensureModelsLoaded(for: targetVersion)
            }

            guard let asrManager = self.asrManager else {
                throw ASRError.notInitialized
            }

            let durationSeconds = Double(audioSamples.count) / 16000.0

            var speechAudio = audioSamples
            if durationSeconds >= 20.0, isVADEnabled {
                let vadConfig = VadConfig(defaultThreshold: 0.7)
                if self.vadManager == nil {
                    do {
                        self.vadManager = try await VadManager(config: vadConfig)
                    } catch {
                        self.logger.notice("VAD init failed; falling back to full audio: \(error.localizedDescription, privacy: .public)")
                        self.vadManager = nil
                    }
                }

                if let vadManager = self.vadManager {
                    do {
                        let segments = try await vadManager.segmentSpeechAudio(audioSamples)
                        speechAudio = segments.isEmpty ? audioSamples : segments.flatMap { $0 }
                    } catch {
                        self.logger.notice("VAD segmentation failed; using full audio: \(error.localizedDescription, privacy: .public)")
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

            let result = try await asrManager.transcribe(speechAudio)
            return result.text
        }

        return try await detachedResult.value
    }

    private func readAudioSamples(from url: URL) throws -> [Float] {
        do {
            let data = try Data(contentsOf: url)
            guard data.count > 44 else {
                throw ASRError.invalidAudioData
            }

            let floats = stride(from: 44, to: data.count, by: 2).map {
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

    // Releases ASR/VAD resources but preserves cached models for reuse
    func cleanup() {
        asrManager?.cleanup()
        asrManager = nil
        vadManager = nil
        activeVersion = nil
    }

}

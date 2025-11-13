import Foundation
import CoreML
import AVFoundation
import SwiftData
import FluidAudio
import os.log

class ParakeetTranscriptionService: TranscriptionService {
    private var asrManager: AsrManager?
    private var vadManager: VadManager?
    private var activeVersion: AsrModelVersion?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink.parakeet", category: "ParakeetTranscriptionService")

    private func version(for model: any TranscriptionModel) -> AsrModelVersion {
        model.name.lowercased().contains("v2") ? .v2 : .v3
    }

    private func ensureModelsLoaded(for version: AsrModelVersion) async throws {
        if let manager = asrManager, activeVersion == version {
            return
        }

        cleanup()

        let manager = AsrManager(config: .default)
        let models = try await AsrModels.loadFromCache(
            configuration: nil,
            version: version
        )
        try await manager.initialize(models: models)
        self.asrManager = manager
        self.activeVersion = version
    }

    func loadModel(for model: ParakeetModel) async throws {
        try await ensureModelsLoaded(for: version(for: model))
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, modelContext: ModelContext?) async throws -> String {
        let targetVersion = version(for: model)
        try await ensureModelsLoaded(for: targetVersion)

        guard let asrManager = asrManager else {
            throw ASRError.notInitialized
        }

        let audioSamples = try readAudioSamples(from: audioURL)

        let durationSeconds = Double(audioSamples.count) / 16000.0
        let isVADEnabled = UserDefaults.standard.object(forKey: "IsVADEnabled") as? Bool ?? true

        var speechAudio = audioSamples
        if durationSeconds >= 20.0, isVADEnabled {
            let vadConfig = VadConfig(defaultThreshold: 0.7)
            if vadManager == nil {
                do {
                    vadManager = try await VadManager(config: vadConfig)
                } catch {
                    logger.notice("VAD init failed; falling back to full audio: \(error.localizedDescription)")
                    vadManager = nil
                }
            }

            if let vadManager {
                do {
                    let segments = try await vadManager.segmentSpeechAudio(audioSamples)
                    speechAudio = segments.isEmpty ? audioSamples : segments.flatMap { $0 }
                } catch {
                    logger.notice("VAD segmentation failed; using full audio: \(error.localizedDescription)")
                    speechAudio = audioSamples
                }
            }
        }

        let result = try await asrManager.transcribe(speechAudio)

        return result.text
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

    func cleanup() {
        asrManager?.cleanup()
        asrManager = nil
        vadManager = nil
        activeVersion = nil
    }
}

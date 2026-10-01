import FluidAudio
import Foundation
import os.log

class FluidAudioTranscriptionService: TranscriptionService {
    private var asrManager: AsrManager?
    private var unifiedAsrManager: UnifiedAsrManager?
    private var nemotronAsrManager: StreamingNemotronMultilingualAsrManager?
    private var vadManager: VadManager?
    private var activeVersion: AsrModelVersion?
    private var activeNemotronModelName: String?
    private var cachedModels: AsrModels?
    private var loadingTask: (version: AsrModelVersion, task: Task<AsrModels, Error>)?
    private let audioConverter = AudioConverter()
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

    private func cleanupLoadedManagers() async {
        _ = try? await TranscriptionDiagnostics.measure("manager-cleanup", logger: logger) {
            await unifiedAsrManager?.cleanup()
            await nemotronAsrManager?.cleanup()
            await asrManager?.cleanup()
        }

        unifiedAsrManager = nil
        nemotronAsrManager = nil
        asrManager = nil
        vadManager = nil
        activeVersion = nil
        activeNemotronModelName = nil
    }

    private func ensureModelsLoaded(for version: AsrModelVersion) async throws {
        if asrManager != nil, activeVersion == version {
            TranscriptionDiagnostics.recording?.add("manager", "reused")
            return
        }

        // Clean up existing manager but preserve cachedModels for reuse
        await cleanupLoadedManagers()

        let models = try await getOrLoadModels(for: version)

        let manager = AsrManager(config: .default)
        try await TranscriptionDiagnostics.measure("parakeet-manager-load", logger: logger) {
            try await manager.loadModels(models)
        }
        self.asrManager = manager
        self.activeVersion = version
    }

    private func ensureUnifiedModelsLoaded() async throws {
        if unifiedAsrManager != nil {
            return
        }

        await cleanupLoadedManagers()

        let manager = UnifiedAsrManager(encoderPrecision: FluidAudioModelManager.parakeetUnifiedPrecision)
        try await TranscriptionDiagnostics.measure(
            "unified-model-load", logger: logger,
            details: "encoderPrecision=\(FluidAudioModelManager.parakeetUnifiedPrecision) configuration=SDK-default"
        ) {
            try await manager.loadModels(from: FluidAudioModelManager.parakeetUnifiedCacheDirectory())
        }
        self.unifiedAsrManager = manager
    }

    private func ensureNemotronModelsLoaded(named modelName: String) async throws {
        if nemotronAsrManager != nil, activeNemotronModelName == modelName {
            return
        }

        await cleanupLoadedManagers()

        let manager = StreamingNemotronMultilingualAsrManager()
        try await TranscriptionDiagnostics.measure(
            "nemotron-model-load", logger: logger, details: "model=\(modelName) configuration=SDK-default"
        ) {
            try await manager.loadModels(from: FluidAudioModelManager.nemotronCacheDirectory(for: modelName))
        }
        self.nemotronAsrManager = manager
        self.activeNemotronModelName = modelName
    }

    // Returns cached models or loads from disk; deduplicates concurrent loads
    func getOrLoadModels(for version: AsrModelVersion) async throws -> AsrModels {
        if let cached = cachedModels, cached.version == version {
            TranscriptionDiagnostics.recording?.add("models", "reused")
            return cached
        }

        // Deduplicate concurrent loads for the same version
        if let (existingVersion, existingTask) = loadingTask, existingVersion == version {
            TranscriptionDiagnostics.recording?.add("models", "shared-load")
            return try await TranscriptionDiagnostics.measure("waiting-for-model-load", logger: logger) {
                try await existingTask.value
            }
        }

        let logger = self.logger
        let task = Task {
            try await TranscriptionDiagnostics.measure(
                "parakeet-model-load", logger: logger,
                details: "version=\(version) encoderPrecision=int8 computeUnits=cpuAndNeuralEngine preprocessor=cpuOnly"
            ) {
                let cacheDirectory = AsrModels.defaultCacheDirectory(for: version)
                guard AsrModels.modelsExist(at: cacheDirectory, version: version) else {
                    throw AsrModelsError.loadingFailed(
                        "Parakeet model files are incomplete. Download the model from AI Models."
                    )
                }
                return try await AsrModels.load(
                    from: cacheDirectory,
                    configuration: nil,
                    version: version,
                    encoderPrecision: .int8
                )
            }
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
        if FluidAudioModelManager.isNemotronModel(named: model.name) {
            // Realtime Nemotron uses a dedicated streaming manager; batch loads lazily in transcribe().
            return
        }

        if FluidAudioModelManager.isParakeetUnifiedModel(named: model.name) {
            try await ensureUnifiedModelsLoaded()
            return
        }

        try await ensureModelsLoaded(for: version(for: model))
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws
        -> String
    {
        if TranscriptionDiagnostics.recording != nil {
            return try await transcribeBatch(audioURL: audioURL, model: model, context: context)
        }
        let recording = TranscriptionDiagnostics.Recording()
        TranscriptionDiagnostics.configuration(model: model, context: context, realtime: false, id: recording.id)
        return try await TranscriptionDiagnostics.transcribe(audioURL: audioURL, model: model, recording: recording) {
            try await transcribeBatch(audioURL: audioURL, model: model, context: context)
        }
    }

    private func transcribeBatch(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext)
        async throws -> String
    {
        try await TranscriptionDiagnostics.measure("batch-transcription", logger: logger) {
            try await transcribeAudio(audioURL: audioURL, model: model, context: context)
        }
    }

    private func transcribeAudio(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext)
        async throws -> String
    {
        if FluidAudioModelManager.isParakeetUnifiedModel(named: model.name) {
            try await ensureUnifiedModelsLoaded()
            guard let unifiedAsrManager else {
                throw ASRError.notInitialized
            }

            let speechAudio = try await preparedSpeechAudio(from: audioURL)
            guard !speechAudio.isEmpty else { return "" }
            let text = try await TranscriptionDiagnostics.measure(
                "unified-prediction", logger: logger, details: "samples=\(speechAudio.count)"
            ) {
                try await unifiedAsrManager.transcribe(speechAudio)
            }
            return text
        }

        if FluidAudioModelManager.isNemotronModel(named: model.name) {
            try await ensureNemotronModelsLoaded(named: model.name)
            guard let nemotronAsrManager else {
                throw ASRError.notInitialized
            }

            let compatibleLanguage = TranscriptionLanguageSupport.validLanguageOrFallback(
                context.language,
                for: model
            )
            let languageHint = FluidAudioModelManager.nemotronLanguageHint(from: compatibleLanguage)
            await nemotronAsrManager.setLanguage(languageHint)
            await nemotronAsrManager.reset()

            var speechAudio = try await preparedSpeechAudio(from: audioURL)
            guard !speechAudio.isEmpty else { return "" }
            let trailingSilenceSamples = 16_000
            let maxSingleChunkSamples = 240_000
            if speechAudio.count + trailingSilenceSamples <= maxSingleChunkSamples {
                speechAudio += [Float](repeating: 0, count: trailingSilenceSamples)
            }

            _ = try await TranscriptionDiagnostics.measure(
                "nemotron-prediction", logger: logger, details: "samples=\(speechAudio.count)"
            ) {
                try await nemotronAsrManager.process(samples: speechAudio)
            }
            let text = try await TranscriptionDiagnostics.measure("nemotron-finish", logger: logger) {
                try await nemotronAsrManager.finish()
            }
            return text
        }

        let targetVersion = version(for: model)
        try await ensureModelsLoaded(for: targetVersion)

        guard let asrManager = asrManager else {
            throw ASRError.notInitialized
        }

        let languageHint = Self.languageHint(
            from: context.language,
            model: model
        )
        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result: ASRResult
        if UserDefaults.standard.bool(forKey: "IsVADEnabled") {
            let speechAudio = try await preparedSpeechAudio(from: audioURL)
            guard !speechAudio.isEmpty else { return "" }
            result = try await TranscriptionDiagnostics.measure(
                "parakeet-prediction", logger: logger, details: "samples=\(speechAudio.count)"
            ) {
                try await asrManager.transcribe(speechAudio, decoderState: &decoderState, language: languageHint)
            }
        } else {
            result = try await TranscriptionDiagnostics.measure("parakeet-file-prediction", logger: logger) {
                try await asrManager.transcribe(audioURL, decoderState: &decoderState, language: languageHint)
            }
        }

        return result.text
    }

    private func loadAudioSamples(from audioURL: URL) throws -> [Float] {
        try audioConverter.resampleAudioFile(audioURL)
    }

    private func preparedSpeechAudio(from audioURL: URL) async throws -> [Float] {
        let samples = try await TranscriptionDiagnostics.measure("audio-preparation", logger: logger) {
            try loadAudioSamples(from: audioURL)
        }
        TranscriptionDiagnostics.recording?.add("inputSamples16kHz", String(samples.count))
        return try await preparedSpeechAudio(in: samples)
    }

    func preparedSpeechAudio(in samples: [Float]) async throws -> [Float] {
        guard let segments = try await detectedSpeechAudio(in: samples) else {
            return samples
        }

        var speechAudio = segments.flatMap { $0 }
        TranscriptionDiagnostics.recording?.add("vadInputSamples", String(samples.count))
        TranscriptionDiagnostics.recording?.add("vadSegments", String(segments.count))
        TranscriptionDiagnostics.recording?.add("vadSpeechSamples", String(speechAudio.count))
        guard !speechAudio.isEmpty else { return [] }
        let minimumSamples = ASRConstants.minimumRequiredSamples(forSampleRate: ASRConstants.sampleRate)
        if speechAudio.count < minimumSamples {
            speechAudio += [Float](repeating: 0, count: minimumSamples - speechAudio.count)
        }
        return speechAudio
    }

    // Streaming callers retain each segment's original position for word timestamps.
    func detectedSpeechSegments(in samples: [Float]) async throws -> [VadSegment]? {
        guard UserDefaults.standard.bool(forKey: "IsVADEnabled") else {
            return nil
        }

        do {
            try Task.checkCancellation()
            let manager = try await getOrLoadVadManager()
            let segments = try await TranscriptionDiagnostics.measure("streaming-vad", logger: logger) {
                try await manager.segmentSpeech(samples)
            }
            try Task.checkCancellation()
            return segments
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.notice("VAD failed; using full audio: \(TranscriptionDiagnostics.errorDetails(error, includeUnderlying: false), privacy: .public)")
            return nil
        }
    }

    private func getOrLoadVadManager() async throws -> VadManager {
        if let vadManager { return vadManager }
        let manager = try await TranscriptionDiagnostics.measure("vad-model-load", logger: logger) {
            try await VadManager(config: VadConfig(defaultThreshold: 0.7))
        }
        vadManager = manager
        return manager
    }

    // Nil means VAD is disabled or unavailable; callers preserve the original audio.
    private func detectedSpeechAudio(in samples: [Float]) async throws -> [[Float]]? {
        guard UserDefaults.standard.bool(forKey: "IsVADEnabled") else {
            return nil
        }

        do {
            try Task.checkCancellation()
            let manager = try await getOrLoadVadManager()
            let segments = try await TranscriptionDiagnostics.measure("vad-speech-detection", logger: logger) {
                try await manager.segmentSpeechAudio(samples)
            }
            try Task.checkCancellation()
            return segments
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.notice("VAD failed; using full audio: \(TranscriptionDiagnostics.errorDetails(error, includeUnderlying: false), privacy: .public)")
            return nil
        }
    }

    // Releases ASR/VAD resources but preserves cached models for reuse
    func cleanup() async {
        await cleanupLoadedManagers()
    }

}

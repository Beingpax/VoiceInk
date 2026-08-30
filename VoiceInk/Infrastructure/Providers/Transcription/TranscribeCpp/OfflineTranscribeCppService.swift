import FluidAudio
import Dispatch
import Foundation
import TranscribeCpp
import os

/// Shared offline runtime for catalog-backed transcribe.cpp model families.
final class OfflineTranscribeCppService: TranscriptionService, @unchecked Sendable {
    private struct LoadedState {
        let modelName: String
        let model: Model
    }

    private struct LoadingState {
        let id: UUID
        let modelName: String
        let task: Task<Model, Error>
    }

    private enum LoadResolution {
        case loaded(Model)
        case loading(LoadingState)
    }

    private static let backendInitializationLock = NSLock()
    private static let modelInitializationLock = NSLock()
    private static var backendsInitialized = false

    private let stateLock = NSLock()
    private var loadedState: LoadedState?
    private var loadingState: LoadingState?
    private var activeTranscriptionCount = 0
    private var notificationObservers: [NSObjectProtocol] = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private let audioConverter = AudioConverter()
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "OfflineTranscribeCppService"
    )

    init() {
        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(forName: .didChangeModel, object: nil, queue: nil) { [weak self] notification in
                guard let modelName = notification.userInfo?["modelName"] as? String else { return }
                self?.unloadModel(unlessSelectedModelIs: modelName)
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .transcribeCppModelDeleted, object: nil, queue: nil) { [weak self] notification in
                guard let modelName = notification.userInfo?["modelName"] as? String else {
                    self?.unloadModel()
                    return
                }
                self?.unloadModel(named: modelName)
            }
        )

        let pressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        pressureSource.setEventHandler { [weak self] in
            self?.unloadModel()
        }
        pressureSource.resume()
        memoryPressureSource = pressureSource
    }

    deinit {
        memoryPressureSource?.cancel()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        unloadModel()
    }

    private var backend: Backend {
        #if arch(arm64)
        return .metal
        #else
        return .cpu
        #endif
    }

    func loadModel(for model: TranscribeCppModel) async throws {
        let artifact = try resolveArtifact(for: model)
        _ = try await getOrLoadModel(for: model, artifact: artifact)
    }

    func transcribe(
        audioURL: URL,
        model: any TranscriptionModel,
        context: TranscriptionRequestContext
    ) async throws -> String {
        guard let transcribeCppModel = model as? TranscribeCppModel else {
            throw NSError(
                domain: "OfflineTranscribeCppService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported transcription model"]
            )
        }
        let artifact = try resolveArtifact(for: transcribeCppModel)

        let nativeModel = try await getOrLoadModel(for: transcribeCppModel, artifact: artifact)
        retainModel(nativeModel, named: transcribeCppModel.name)
        defer { releaseModel(named: transcribeCppModel.name) }

        let samples = try audioConverter.resampleAudioFile(audioURL)
        let language = selectedLanguage(context.language, for: transcribeCppModel)
        let options = RunOptions(
            timestamps: .none,
            itn: artifact.enablesInverseTextNormalization ? .on : .default,
            language: language,
            keepSpecialTags: false
        )
        let maximumChunkSeconds = effectiveMaximumChunkSeconds(
            configuredMaximum: artifact.maximumChunkSeconds,
            capabilitiesMaximumMilliseconds: nativeModel.capabilities.maxAudioMs
        )
        let chunks = samples.energyAwareChunks(
            maximumCount: maximumChunkSeconds * 16_000,
            boundarySearchCount: artifact.boundarySearchSeconds * 16_000,
            energyWindowCount: artifact.boundaryEnergyWindowSamples
        )

        let startedAt = ContinuousClock.now
        var chunkTranscripts: [(text: String, language: String?)] = []
        chunkTranscripts.reserveCapacity(chunks.count)

        for chunk in chunks {
            try Task.checkCancellation()
            let session = try nativeModel.session()
            let transcript = try await session.run(chunk, options: options)
            let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                chunkTranscripts.append((text: text, language: transcript.language ?? language))
            }
        }

        logger.notice(
            "\(transcribeCppModel.displayName, privacy: .public) completed in \(startedAt.duration(to: .now).formatted(.units(allowed: [.seconds], width: .narrow)), privacy: .public) for \(samples.count, privacy: .public) samples"
        )
        return joinedText(from: chunkTranscripts)
    }

    func cleanup() {
        unloadModel()
    }

    func unloadModel() {
        unloadModel { _ in true }
    }

    private func getOrLoadModel(
        for model: TranscribeCppModel,
        artifact: TranscribeCppModelArtifact
    ) async throws -> Model {
        let resolvedState: LoadResolution = stateLock.withLock {
            if let loadedState, loadedState.modelName == model.name {
                return .loaded(loadedState.model)
            }
            if let loadingState, loadingState.modelName == model.name {
                return .loading(loadingState)
            }

            loadingState?.task.cancel()
            loadingState = nil
            loadedState = nil

            let loadID = UUID()
            let backend = backend
            let task = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                guard let modelURL = artifact.installedModelFileURL else {
                    throw CocoaError(.fileNoSuchFile)
                }

                try Self.initializeBackendsIfNeeded()
                guard Transcribe.backendAvailable(backend) else {
                    throw TranscribeError.backend("The requested transcribe.cpp backend is unavailable")
                }

                // Serialize non-cancellable native construction to prevent overlapping model loads.
                return try Self.modelInitializationLock.withLock {
                    try Task.checkCancellation()
                    let loadedModel = try Model(
                        path: modelURL.path,
                        options: ModelOptions(backend: backend)
                    )
                    try Task.checkCancellation()
                    return loadedModel
                }
            }
            let state = LoadingState(id: loadID, modelName: model.name, task: task)
            loadingState = state
            return .loading(state)
        }

        if case .loaded(let loadedModel) = resolvedState {
            return loadedModel
        }

        guard case .loading(let loading) = resolvedState else {
            throw CocoaError(.fileReadUnknown)
        }

        let startedAt = ContinuousClock.now
        do {
            let loadedModel = try await loading.task.value
            if let architectureHint = artifact.architectureHint {
                guard loadedModel.arch.localizedCaseInsensitiveContains(architectureHint) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }

            let loadIsCurrent = stateLock.withLock {
                if
                    let currentState = loadedState,
                    currentState.modelName == model.name,
                    currentState.model === loadedModel
                {
                    return true
                }
                guard loadingState?.id == loading.id else { return false }
                loadedState = LoadedState(modelName: model.name, model: loadedModel)
                loadingState = nil
                return true
            }
            guard loadIsCurrent else { throw CancellationError() }

            logger.notice(
                "\(model.displayName, privacy: .public) loaded with \(loadedModel.backend, privacy: .public) in \(startedAt.duration(to: .now).formatted(.units(allowed: [.seconds], width: .narrow)), privacy: .public)"
            )
            return loadedModel
        } catch {
            stateLock.withLock {
                if loadingState?.id == loading.id {
                    loadingState = nil
                }
            }
            throw error
        }
    }

    private func unloadModel(named modelName: String) {
        unloadModel { $0 == modelName }
    }

    private func unloadModel(unlessSelectedModelIs modelName: String) {
        unloadModel { $0 != modelName }
    }

    private func unloadModel(where shouldUnload: (String) -> Bool) {
        let didUnload = stateLock.withLock {
            guard let activeModelName = loadedState?.modelName ?? loadingState?.modelName,
                shouldUnload(activeModelName),
                activeTranscriptionCount == 0
            else {
                return false
            }
            loadingState?.task.cancel()
            loadingState = nil
            loadedState = nil
            return true
        }
        if didUnload {
            logger.notice("transcribe.cpp runtime unloaded")
        }
    }

    private func retainModel(_ model: Model, named modelName: String) {
        stateLock.withLock {
            // Restore an acquired model after a racing unload and cancel its replacement load.
            loadingState?.task.cancel()
            loadingState = nil
            loadedState = LoadedState(modelName: modelName, model: model)
            activeTranscriptionCount += 1
        }
    }

    private func releaseModel(named modelName: String) {
        let didUnload = stateLock.withLock {
            guard activeTranscriptionCount > 0 else { return false }
            activeTranscriptionCount -= 1
            guard activeTranscriptionCount == 0,
                loadedState?.modelName == modelName || loadingState?.modelName == modelName
            else {
                return false
            }
            loadingState?.task.cancel()
            loadingState = nil
            loadedState = nil
            return true
        }
        if didUnload {
            logger.notice("transcribe.cpp runtime unloaded")
        }
    }

    private func resolveArtifact(for model: TranscribeCppModel) throws -> TranscribeCppModelArtifact {
        guard let artifact = TranscribeCppModelCatalog.artifact(for: model.name) else {
            throw NSError(
                domain: "OfflineTranscribeCppService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported transcribe.cpp model"]
            )
        }
        return artifact
    }

    private func selectedLanguage(_ language: String?, for model: TranscribeCppModel) -> String? {
        let compatibleLanguage = TranscriptionLanguageSupport.validLanguageOrFallback(language, for: model)
        guard compatibleLanguage != "auto" else { return nil }
        return compatibleLanguage.split(separator: "-").first.map(String.init)?.lowercased()
    }

    private func effectiveMaximumChunkSeconds(
        configuredMaximum: Int,
        capabilitiesMaximumMilliseconds: Int64
    ) -> Int {
        guard capabilitiesMaximumMilliseconds > 0 else { return configuredMaximum }
        let capabilitiesMaximum = Swift.max(1, Int(capabilitiesMaximumMilliseconds / 1_000))
        return Swift.min(configuredMaximum, capabilitiesMaximum)
    }

    private func joinedText(from chunks: [(text: String, language: String?)]) -> String {
        chunks.enumerated().reduce(into: "") { result, entry in
            let (index, chunk) = entry
            if index > 0, languageUsesSpaces(chunk.language) {
                result.append(" ")
            }
            result.append(chunk.text)
        }
    }

    private func languageUsesSpaces(_ language: String?) -> Bool {
        guard let language else { return true }
        return language != "ja" && language != "yue" && language != "zh"
    }

    private static func initializeBackendsIfNeeded() throws {
        try backendInitializationLock.withLock {
            guard !backendsInitialized else { return }
            try Transcribe.initBackends()
            backendsInitialized = true
        }
    }
}

private extension Array where Element == Float {
    /// Splits long-form audio near low-energy boundaries without overlapping samples.
    func energyAwareChunks(
        maximumCount: Int,
        boundarySearchCount: Int,
        energyWindowCount: Int
    ) -> [[Float]] {
        guard maximumCount > 0, count > maximumCount else { return [self] }

        let safeBoundarySearch = Swift.max(1, Swift.min(boundarySearchCount, maximumCount))
        let safeEnergyWindow = Swift.max(1, energyWindowCount)
        var chunks: [[Float]] = []
        var start = 0

        while start < count {
            let maximumEnd = Swift.min(start + maximumCount, count)
            if maximumEnd == count {
                chunks.append(Array(self[start..<maximumEnd]))
                break
            }

            let searchStart = Swift.max(start, maximumEnd - safeBoundarySearch)
            let splitPoint = quietestWindowStart(
                from: searchStart,
                to: maximumEnd,
                windowCount: safeEnergyWindow
            )
            let safeSplitPoint = Swift.max(start + 1, Swift.min(splitPoint, count))
            chunks.append(Array(self[start..<safeSplitPoint]))
            start = safeSplitPoint
        }

        return chunks
    }

    private func quietestWindowStart(from start: Int, to end: Int, windowCount: Int) -> Int {
        guard end - start > windowCount else { return (start + end) / 2 }

        var quietestStart = start
        var lowestEnergy = Double.infinity
        let finalWindowStart = end - windowCount
        var candidateStarts = [Int](stride(from: start, through: finalWindowStart, by: windowCount))
        if candidateStarts.last != finalWindowStart {
            candidateStarts.append(finalWindowStart)
        }

        for windowStart in candidateStarts {
            var squaredSampleSum = 0.0
            for sample in self[windowStart..<(windowStart + windowCount)] {
                let value = Double(sample)
                squaredSampleSum += value * value
            }
            let meanSquaredEnergy = squaredSampleSum / Double(windowCount)
            if meanSquaredEnergy < lowestEnergy {
                lowestEnergy = meanSquaredEnergy
                quietestStart = windowStart
            }
        }

        return quietestStart
    }
}

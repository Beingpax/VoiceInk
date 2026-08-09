import FluidAudio
import Dispatch
import Foundation
import TranscribeCpp
import os

final class CohereTranscriptionService: TranscriptionService, @unchecked Sendable {
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
    private static var backendsInitialized = false

    private let stateLock = NSLock()
    private var loadedState: LoadedState?
    private var loadingState: LoadingState?
    private var notificationObservers: [NSObjectProtocol] = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private let audioConverter = AudioConverter()
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "CohereTranscriptionService"
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
        _ = try await getOrLoadModel(for: model)
    }

    func transcribe(
        audioURL: URL,
        model: any TranscriptionModel,
        context: TranscriptionRequestContext
    ) async throws -> String {
        guard let transcribeCppModel = model as? TranscribeCppModel else {
            throw NSError(
                domain: "CohereTranscriptionService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported transcription model"]
            )
        }
        let artifact = TranscribeCppModelCatalog.cohereTranscribe
        guard transcribeCppModel.name == artifact.modelName else {
            throw NSError(
                domain: "CohereTranscriptionService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported Cohere transcription model"]
            )
        }

        let nativeModel = try await getOrLoadModel(for: transcribeCppModel)
        defer { unloadModel(named: transcribeCppModel.name) }

        let samples = try audioConverter.resampleAudioFile(audioURL)
        let language = selectedLanguage(context.language, for: transcribeCppModel)
        let options = RunOptions(timestamps: .none, language: language)
        let chunks = samples.energyAwareChunks(
            maximumCount: artifact.maximumChunkSeconds * 16_000,
            boundarySearchCount: artifact.boundarySearchSeconds * 16_000,
            energyWindowCount: artifact.boundaryEnergyWindowSamples
        )

        let startedAt = ContinuousClock.now
        var texts: [String] = []
        texts.reserveCapacity(chunks.count)

        for chunk in chunks {
            try Task.checkCancellation()
            let session = try nativeModel.session()
            let transcript = try await session.run(chunk, options: options)
            let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                texts.append(text)
            }
        }

        logger.notice(
            "\(transcribeCppModel.displayName, privacy: .public) completed in \(startedAt.duration(to: .now).formatted(.units(allowed: [.seconds], width: .narrow)), privacy: .public) for \(samples.count, privacy: .public) samples"
        )
        return TextNormalizer.shared.normalizeSentence(texts.joined(separator: languageUsesSpaces(language) ? " " : ""))
    }

    func cleanup() {
        unloadModel()
    }

    func unloadModel() {
        let didUnload = stateLock.withLock {
            let hadRuntime = loadedState != nil || loadingState != nil
            loadingState?.task.cancel()
            loadingState = nil
            loadedState = nil
            return hadRuntime
        }
        if didUnload {
            logger.notice("transcribe.cpp runtime unloaded")
        }
    }

    private func getOrLoadModel(for model: TranscribeCppModel) async throws -> Model {
        let artifact = TranscribeCppModelCatalog.cohereTranscribe
        guard model.name == artifact.modelName else {
            throw NSError(
                domain: "CohereTranscriptionService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported Cohere transcription model"]
            )
        }

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
                guard let modelURL = artifact.installedModelFileURL else {
                    throw CocoaError(.fileNoSuchFile)
                }

                try Self.initializeBackendsIfNeeded()
                guard Transcribe.backendAvailable(backend) else {
                    throw TranscribeError.backend("The requested transcribe.cpp backend is unavailable")
                }

                return try Model(
                    path: modelURL.path,
                    options: ModelOptions(backend: backend)
                )
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
        let didUnload = stateLock.withLock {
            guard loadedState?.modelName == modelName || loadingState?.modelName == modelName else {
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

    private func unloadModel(unlessSelectedModelIs modelName: String) {
        let didUnload = stateLock.withLock {
            let hasDifferentLoadedModel = loadedState != nil && loadedState?.modelName != modelName
            let hasDifferentLoadingModel = loadingState != nil && loadingState?.modelName != modelName
            guard hasDifferentLoadedModel || hasDifferentLoadingModel else { return false }
            loadingState?.task.cancel()
            loadingState = nil
            loadedState = nil
            return true
        }
        if didUnload {
            logger.notice("transcribe.cpp runtime unloaded")
        }
    }

    private func selectedLanguage(_ language: String?, for model: TranscribeCppModel) -> String {
        let compatibleLanguage = TranscriptionLanguageSupport.validLanguageOrFallback(language, for: model)
        return compatibleLanguage.split(separator: "-").first.map(String.init)?.lowercased() ?? "en"
    }

    private func languageUsesSpaces(_ language: String) -> Bool {
        language != "ja" && language != "zh"
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
    /// Matches Cohere's reference long-form splitter. The final part of each
    /// possible 35-second chunk is a boundary-search region, not audio overlap.
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

        for windowStart in stride(from: start, to: finalWindowStart, by: windowCount) {
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

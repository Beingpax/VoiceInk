import Foundation
import FluidAudio
import AppKit
import os

struct FluidAudioDownloadStatus {
    let fractionCompleted: Double
    let message: String
    let isIndeterminate: Bool

    init(fractionCompleted: Double, message: String, isIndeterminate: Bool = false) {
        self.fractionCompleted = fractionCompleted
        self.message = message
        self.isIndeterminate = isIndeterminate
    }
}

@MainActor
class FluidAudioModelManager: ObservableObject {
    @Published private var downloadStatuses: [String: FluidAudioDownloadStatus] = [:]
    @Published private var modelStateRevision = 0
    private var activeDownloadIDs: [String: UUID] = [:]

    var onModelDeleted: ((String) -> Void)?
    var onModelsChanged: (() -> Void)?

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FluidAudioModelManager")

    // Add new Fluid Audio models here when support is added.
    private static let modelVersionMap: [String: AsrModelVersion] = [
        "parakeet-tdt-0.6b-v2": .v2,
        "parakeet-tdt-0.6b-v3": .v3,
    ]

    private enum FluidAudioModelKind {
        case parakeet(AsrModelVersion)
        case parakeetUnified
        case nemotron(NemotronVariant)
    }

    nonisolated static func asrVersion(for modelName: String) -> AsrModelVersion {
        modelVersionMap[modelName] ?? .v3
    }

    nonisolated static func isParakeetUnifiedModel(named modelName: String) -> Bool {
        modelName == "parakeet-unified-0.6b"
    }

    nonisolated static let parakeetUnifiedPrecision: UnifiedEncoderPrecision = .int8
    nonisolated private static var parakeetUnifiedStreamingVariant: String? {
        parakeetUnifiedPrecision == .fp16 ? "fp16" : nil
    }
    nonisolated private static var parakeetUnifiedOfflineVariant: String {
        parakeetUnifiedPrecision == .fp16 ? "offline-fp16" : "offline"
    }
    nonisolated private static let nemotronChunkMs = 560

    private enum NemotronVariant {
        case latin
        case multilingual

        init?(modelName: String) {
            switch modelName {
            case "nemotron-latin-0.6b":
                self = .latin
            case "nemotron-multilingual-0.6b":
                self = .multilingual
            default:
                return nil
            }
        }

        var downloadLanguageCode: String {
            switch self {
            case .latin:
                return "en"
            case .multilingual:
                return "auto"
            }
        }
    }

    nonisolated static func isNemotronModel(named modelName: String) -> Bool {
        NemotronVariant(modelName: modelName) != nil
    }

    nonisolated private static func modelKind(for modelName: String) -> FluidAudioModelKind {
        if let nemotronVariant = NemotronVariant(modelName: modelName) {
            return .nemotron(nemotronVariant)
        }

        if isParakeetUnifiedModel(named: modelName) {
            return .parakeetUnified
        }

        return .parakeet(asrVersion(for: modelName))
    }

    nonisolated static func nemotronLanguageHint(from languageCode: String?) -> String? {
        guard let languageCode else { return nil }

        let trimmed = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let dashed = trimmed.replacingOccurrences(of: "_", with: "-")
        return dashed.lowercased() == "auto" ? nil : dashed
    }

    nonisolated static func nemotronCacheDirectory(for modelName: String) -> URL {
        nemotronCacheDirectory(for: NemotronVariant(modelName: modelName) ?? .multilingual)
    }

    nonisolated private static func nemotronCacheDirectory(for variant: NemotronVariant) -> URL {
        let languageDirectory = StreamingNemotronMultilingualAsrManager.languageDirectory(
            for: variant.downloadLanguageCode
        )
        return fluidAudioModelsRootDirectory()
            .appendingPathComponent(Repo.nemotronMultilingual.folderName, isDirectory: true)
            .appendingPathComponent(languageDirectory, isDirectory: true)
            .appendingPathComponent("\(nemotronChunkMs)ms", isDirectory: true)
    }

    nonisolated static func languageHint(from languageCode: String?, for modelName: String) -> Language? {
        guard !isParakeetUnifiedModel(named: modelName),
              !isNemotronModel(named: modelName),
              asrVersion(for: modelName) == .v3,
              let languageCode,
              languageCode != "auto"
        else { return nil }

        return Language(rawValue: languageCode)
    }

    init() {}

    // MARK: - Query helpers

    func isFluidAudioModelDownloaded(named modelName: String) -> Bool {
        switch Self.modelKind(for: modelName) {
        case .nemotron(let variant):
            return Self.nemotronRequiredFilesExist(in: Self.nemotronCacheDirectory(for: variant))
        case .parakeetUnified:
            let directory = cacheDirectory(for: modelName)
            return Self.parakeetUnifiedRequiredFiles.allSatisfy {
                FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
            }
        case .parakeet(let version):
            return AsrModels.modelsExist(at: cacheDirectory(for: version), version: version)
        }
    }

    func isFluidAudioModelDownloaded(_ model: FluidAudioModel) -> Bool {
        isFluidAudioModelDownloaded(named: model.name)
    }

    func isFluidAudioModelDownloading(_ model: FluidAudioModel) -> Bool {
        downloadStatuses[model.name] != nil
    }

    func downloadStatus(for model: FluidAudioModel) -> FluidAudioDownloadStatus? {
        downloadStatuses[model.name]
    }

    // MARK: - Download

    func downloadFluidAudioModel(_ model: FluidAudioModel) async {
        if isFluidAudioModelDownloaded(model) || isFluidAudioModelDownloading(model) {
            return
        }

        let modelName = model.name
        let downloadID = UUID()
        activeDownloadIDs[modelName] = downloadID
        downloadStatuses[modelName] = FluidAudioDownloadStatus(
            fractionCompleted: 0.0,
            message: "Preparing FluidAudio download..."
        )
        defer {
            clearDownloadStatus(for: modelName, downloadID: downloadID)
            onModelsChanged?()
        }

        let progressHandler: DownloadUtils.ProgressHandler = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.updateDownloadProgress(progress, for: modelName, downloadID: downloadID)
            }
        }

        do {
            switch Self.modelKind(for: modelName) {
            case .parakeetUnified:
                try await DownloadUtils.downloadRepo(
                    .parakeetUnified,
                    to: Self.fluidAudioModelsRootDirectory(),
                    variant: Self.parakeetUnifiedStreamingVariant,
                    progressHandler: Self.stagedDownloadOnlyProgressHandler(
                        from: 0.0,
                        to: 0.5,
                        forwarding: progressHandler
                    )
                )
                let realtimeOptimization = Task.detached(priority: .utility) {
                    try await Self.optimizeParakeetUnifiedRealtimeModel()
                }

                try await DownloadUtils.downloadRepo(
                    .parakeetUnified,
                    to: Self.fluidAudioModelsRootDirectory(),
                    variant: Self.parakeetUnifiedOfflineVariant,
                    progressHandler: Self.stagedDownloadOnlyProgressHandler(
                        from: 0.5,
                        to: 1.0,
                        forwarding: progressHandler
                    )
                )
                downloadStatuses[modelName] = FluidAudioDownloadStatus(
                    fractionCompleted: 1.0,
                    message: String(localized: "Optimizing model for your device"),
                    isIndeterminate: true
                )
                try await Self.optimizeParakeetUnifiedBatchModel()
                try await realtimeOptimization.value
            case .nemotron(let variant):
                let modelDirectory = try await StreamingNemotronMultilingualAsrManager.downloadVariant(
                    languageCode: variant.downloadLanguageCode,
                    chunkMs: Self.nemotronChunkMs,
                    progressHandler: progressHandler
                )
                downloadStatuses[modelName] = FluidAudioDownloadStatus(
                    fractionCompleted: 1.0,
                    message: String(localized: "Optimizing model for your device"),
                    isIndeterminate: true
                )
                let manager = StreamingNemotronMultilingualAsrManager()
                do {
                    try await manager.loadModels(from: modelDirectory)
                } catch {
                    await manager.cleanup()
                    throw error
                }
                await manager.cleanup()
            case .parakeet(let version):
                _ = try await AsrModels.downloadAndLoad(
                    version: version,
                    progressHandler: progressHandler
                )
            }
            modelStateRevision += 1
        } catch {
            logger.error("❌ FluidAudio download failed for \(modelName, privacy: .public): \(error, privacy: .public)")
        }
    }

    nonisolated private static func optimizeParakeetUnifiedRealtimeModel() async throws {
        let streamingManager = StreamingUnifiedAsrManager(encoderPrecision: parakeetUnifiedPrecision)
        do {
            try await streamingManager.loadModels(from: parakeetUnifiedCacheDirectory())
        } catch {
            await streamingManager.cleanup()
            throw error
        }
        await streamingManager.cleanup()
    }

    nonisolated private static func optimizeParakeetUnifiedBatchModel() async throws {
        let batchManager = UnifiedAsrManager(encoderPrecision: parakeetUnifiedPrecision)
        do {
            try await batchManager.loadModels(from: parakeetUnifiedCacheDirectory())
        } catch {
            await batchManager.cleanup()
            throw error
        }
        await batchManager.cleanup()
    }

    // MARK: - Delete

    func deleteFluidAudioModel(_ model: FluidAudioModel) {
        let cacheDirectory = cacheDirectory(for: model)

        do {
            if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.removeItem(at: cacheDirectory)
            }
        } catch {
            // Silently ignore removal errors
        }

        // Notify TranscriptionModelManager to clear currentTranscriptionModel if it matches
        modelStateRevision += 1
        onModelDeleted?(model.name)
    }

    // MARK: - Finder

    func showFluidAudioModelInFinder(_ model: FluidAudioModel) {
        let cacheDirectory = cacheDirectory(for: model)

        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            NSWorkspace.shared.selectFile(cacheDirectory.path, inFileViewerRootedAtPath: "")
        }
    }

    // MARK: - Private helpers

    private func cacheDirectory(for model: FluidAudioModel) -> URL {
        cacheDirectory(for: model.name)
    }

    private func cacheDirectory(for modelName: String) -> URL {
        switch Self.modelKind(for: modelName) {
        case .nemotron(let variant):
            return Self.nemotronCacheDirectory(for: variant)
        case .parakeetUnified:
            return Self.parakeetUnifiedCacheDirectory()
        case .parakeet(let version):
            return cacheDirectory(for: version)
        }
    }

    private func cacheDirectory(for version: AsrModelVersion) -> URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    nonisolated private static var parakeetUnifiedRequiredFiles: Set<String> {
        ModelNames.ParakeetUnified.requiredModels(variant: parakeetUnifiedStreamingVariant)
            .union(ModelNames.ParakeetUnified.requiredModels(variant: parakeetUnifiedOfflineVariant))
    }

    nonisolated private static func nemotronRequiredFilesExist(in directory: URL) -> Bool {
        let requiredFiles = [
            ModelNames.NemotronMultilingualStreaming.metadata,
            ModelNames.NemotronMultilingualStreaming.tokenizer,
            ModelNames.NemotronMultilingualStreaming.preprocessorFile,
            ModelNames.NemotronMultilingualStreaming.encoderFile,
        ]

        let requiredFilesExist = requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        guard requiredFilesExist else { return false }

        let hasFusedDecoder = [
            "decoder_joint_argmax.mlmodelc",
            "decoder_joint_noencproj.mlmodelc",
            "decoder_joint.mlmodelc",
        ].contains { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
        let hasBareDecoderAndJoint =
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(ModelNames.NemotronMultilingualStreaming.decoderFile).path
            )
            && FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(ModelNames.NemotronMultilingualStreaming.jointFile).path
            )

        return hasFusedDecoder || hasBareDecoderAndJoint
    }

    nonisolated private static func parakeetUnifiedCacheDirectory() -> URL {
        fluidAudioModelsRootDirectory()
            .appendingPathComponent(Repo.parakeetUnified.folderName, isDirectory: true)
    }

    // Mirrors FluidAudio's Unified managers because they do not expose a public
    // cache directory helper. Keep this in sync with FluidAudio/Sources/FluidAudio/
    // ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift:124 and
    // ASR/Parakeet/Unified/UnifiedAsrManager.swift:142.
    nonisolated private static func fluidAudioModelsRootDirectory() -> URL {
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        }

        return fileManager.temporaryDirectory
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    nonisolated private static func stagedDownloadOnlyProgressHandler(
        from start: Double,
        to end: Double,
        forwarding progressHandler: DownloadUtils.ProgressHandler?
    ) -> DownloadUtils.ProgressHandler {
        { progress in
            let clampedProgress = min(max(progress.fractionCompleted * 2.0, 0.0), 1.0)
            let mappedProgress = start + ((end - start) * clampedProgress)
            progressHandler?(DownloadUtils.DownloadProgress(
                fractionCompleted: mappedProgress,
                phase: progress.phase
            ))
        }
    }

    private func clearDownloadStatus(for modelName: String, downloadID: UUID) {
        guard activeDownloadIDs[modelName] == downloadID else { return }
        activeDownloadIDs[modelName] = nil
        downloadStatuses[modelName] = nil
    }

    private func updateDownloadProgress(_ progress: DownloadUtils.DownloadProgress, for modelName: String, downloadID: UUID) {
        guard activeDownloadIDs[modelName] == downloadID else { return }

        downloadStatuses[modelName] = FluidAudioDownloadStatus(
            fractionCompleted: min(max(progress.fractionCompleted, 0.0), 1.0),
            message: FluidAudioModelManager.statusMessage(for: progress),
            isIndeterminate: Self.isIndeterminatePhase(progress.phase)
        )
    }

    private static func isIndeterminatePhase(_ phase: DownloadUtils.DownloadPhase) -> Bool {
        if case .compiling(let modelName) = phase {
            return modelName.isEmpty
        }

        return false
    }

    private static func statusMessage(for progress: DownloadUtils.DownloadProgress) -> String {
        switch progress.phase {
        case .listing:
            return String(localized: "Listing files from repository...")
        case .downloading(let completedFiles, let totalFiles):
            guard totalFiles > 0 else {
                return String(localized: "Checking cached models...")
            }
            return String(format: String(localized: "Downloading model files: %lld/%lld"), Int64(completedFiles), Int64(totalFiles))
        case .compiling(let modelName):
            guard !modelName.isEmpty else {
                return String(localized: "Finalizing models...")
            }
            return String(format: String(localized: "Compiling %@"), displayName(forModelComponent: modelName))
        }
    }

    private static func displayName(forModelComponent modelName: String) -> String {
        modelName.replacingOccurrences(of: ".mlmodelc", with: "")
    }
}

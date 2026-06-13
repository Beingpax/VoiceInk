import Foundation
import FluidAudio
import AppKit
import os

struct FluidAudioDownloadStatus {
    let fractionCompleted: Double
    let message: String
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

    nonisolated static func asrVersion(for modelName: String) -> AsrModelVersion {
        modelVersionMap[modelName] ?? .v3
    }

    nonisolated static func isParakeetUnifiedModel(named modelName: String) -> Bool {
        modelName == "parakeet-unified-0.6b"
    }

    nonisolated static let parakeetUnifiedPrecision: UnifiedEncoderPrecision = .int8

    nonisolated static func languageHint(from languageCode: String?, for modelName: String) -> Language? {
        guard !isParakeetUnifiedModel(named: modelName),
              asrVersion(for: modelName) == .v3,
              let languageCode,
              languageCode != "auto"
        else { return nil }

        return Language(rawValue: languageCode)
    }

    init() {}

    // MARK: - Query helpers

    func isFluidAudioModelDownloaded(named modelName: String) -> Bool {
        if Self.isParakeetUnifiedModel(named: modelName) {
            let directory = cacheDirectory(for: modelName)
            return Self.parakeetUnifiedRequiredFiles.allSatisfy {
                FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
            }
        }

        let version = FluidAudioModelManager.asrVersion(for: modelName)
        return AsrModels.modelsExist(at: cacheDirectory(for: version), version: version)
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
            if Self.isParakeetUnifiedModel(named: modelName) {
                let streamingManager = StreamingUnifiedAsrManager(encoderPrecision: Self.parakeetUnifiedPrecision)
                try await streamingManager.loadModels(progressHandler: Self.stagedProgressHandler(
                    from: 0.0,
                    to: 0.5,
                    forwarding: progressHandler
                ))
                await streamingManager.cleanup()

                let batchManager = UnifiedAsrManager(encoderPrecision: Self.parakeetUnifiedPrecision)
                try await batchManager.loadModels(progressHandler: Self.stagedProgressHandler(
                    from: 0.5,
                    to: 1.0,
                    forwarding: progressHandler
                ))
                await batchManager.cleanup()
            } else {
                _ = try await AsrModels.downloadAndLoad(
                    version: Self.asrVersion(for: modelName),
                    progressHandler: progressHandler
                )
            }
            modelStateRevision += 1
        } catch {
            logger.error("❌ FluidAudio download failed for \(modelName, privacy: .public): \(error, privacy: .public)")
        }
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
        if Self.isParakeetUnifiedModel(named: modelName) {
            return Self.parakeetUnifiedCacheDirectory()
        }

        return cacheDirectory(for: FluidAudioModelManager.asrVersion(for: modelName))
    }

    private func cacheDirectory(for version: AsrModelVersion) -> URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    nonisolated private static var parakeetUnifiedRequiredFiles: Set<String> {
        ModelNames.ParakeetUnified.requiredModels(variant: nil)
            .union(ModelNames.ParakeetUnified.requiredModels(variant: "offline"))
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

    nonisolated private static func stagedProgressHandler(
        from start: Double,
        to end: Double,
        forwarding progressHandler: DownloadUtils.ProgressHandler?
    ) -> DownloadUtils.ProgressHandler {
        { progress in
            let clampedProgress = min(max(progress.fractionCompleted, 0.0), 1.0)
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
            message: FluidAudioModelManager.statusMessage(for: progress)
        )
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

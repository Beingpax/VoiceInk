import Combine
import Foundation
import OSLog

enum VoiceInkRefineAvailability: Equatable {
    case available
    case unsupportedIntel
    case insufficientMemory
}

enum VoiceInkRefineError: LocalizedError {
    case unavailable
    case modelNotDownloaded

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localized: "VoiceInk Refine requires an Apple silicon Mac with at least 16 GB of memory.")
        case .modelNotDownloaded:
            return String(localized: "VoiceInk Refine is not downloaded.")
        }
    }
}

final class VoiceInkRefineService: ObservableObject {
    static let shared = VoiceInkRefineService(model: .v1)
    static let mini = VoiceInkRefineService(model: .mini)
    static let all = [shared, mini]

    static func service(for modelName: String?) -> VoiceInkRefineService {
        all.first { $0.modelName == modelName } ?? shared
    }

    static var installationChanges: AnyPublisher<Void, Never> {
        Publishers.MergeMany(all.map { service in
            service.$isDownloaded
                .removeDuplicates()
                .dropFirst()
                .map { _ in () }
                .eraseToAnyPublisher()
        }).eraseToAnyPublisher()
    }

    static var availableModelNames: [String] {
        all.filter(\.isAvailableInModes).map(\.modelName)
    }

    static func resolvedModelName(_ configured: String?) -> String {
        if let configured, VoiceInkRefineModel(rawValue: configured) != nil { return configured }
        return availableModelNames.first ?? VoiceInkRefineModel.v1.rawValue
    }

    static let providerName = "VoiceInk Refine"
    let model: VoiceInkRefineModel
    var modelName: String { model.rawValue }
    var downloadSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)
    }

    @Published private(set) var isDownloaded = false
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress = 0.0
    private(set) var downloadedBytes: Int64 = 0
    private(set) var totalDownloadBytes: Int64
    private(set) var isFinalizingDownload = false
    @Published private(set) var downloadError: String?

    let availability: VoiceInkRefineAvailability

    var isAvailableInModes: Bool {
        availability == .available && isDownloaded
    }

    var downloadedModelURL: URL? {
        isDownloaded ? snapshotURL : nil
    }

    var unavailableDescription: String? {
        switch availability {
        case .available:
            return nil
        case .unsupportedIntel:
            return String(localized: "Available on Apple silicon Macs with at least 16 GB of memory.")
        case .insufficientMemory:
            return String(localized: "Requires at least 16 GB of memory.")
        }
    }

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "VoiceInkRefineService"
    )
    private let modelRootDirectory: URL
    // One client serializes both variants and keeps only one model warm at a time.
    private static let sharedInferenceClient = VoiceInkRefineXPCClient()
    private var inferenceClient: VoiceInkRefineXPCClient { Self.sharedInferenceClient }
    private var downloadTask: Task<Void, Never>?

    private init(
        model: VoiceInkRefineModel,
        architectureIsAppleSilicon: Bool = SystemArchitecture.isAppleSilicon,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        self.model = model
        self.totalDownloadBytes = model.totalBytes
        if !architectureIsAppleSilicon {
            availability = .unsupportedIntel
        } else if physicalMemory < model.minimumMemoryBytes {
            availability = .insufficientMemory
        } else {
            availability = .available
        }

        let appSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        modelRootDirectory = appSupportDirectory
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
            .appendingPathComponent(model.directoryName)

        refreshDownloadedState()
    }

    @MainActor
    func startDownload() {
        guard availability == .available, !isDownloaded, downloadTask == nil else {
            return
        }

        downloadTask = Task { [weak self] in
            await self?.downloadModel()
        }
    }

    @MainActor
    func cancelDownload() {
        downloadTask?.cancel()
    }

    @MainActor
    func deleteModel() async {
        cancelDownload()
        await inferenceClient.shutdown()

        do {
            if FileManager.default.fileExists(atPath: modelRootDirectory.path) {
                try FileManager.default.removeItem(at: modelRootDirectory)
            }
            downloadProgress = 0
            downloadedBytes = 0
            isFinalizingDownload = false
            downloadError = nil
            refreshDownloadedState()
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        } catch {
            downloadError = error.localizedDescription
            logger.error("Failed to delete VoiceInk Refine: \(error.localizedDescription, privacy: .public)")
        }
    }

    func enhance(transcript: String, vocabulary: RecordingVocabulary) async throws -> String {
        guard availability == .available else {
            throw VoiceInkRefineError.unavailable
        }
        guard isDownloaded, let snapshotURL else {
            throw VoiceInkRefineError.modelNotDownloaded
        }

        return try await inferenceClient.enhance(
            transcript: transcript,
            modelDirectory: snapshotURL,
            systemPrompt: [model.systemPrompt, vocabulary.enhancementSection]
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
        )
    }

    func unloadPreparedModelIfNeeded() async {
        await inferenceClient.shutdownPreparedModelIfNeeded()
    }

    func keepPreparedModelWarmForRecording() async {
        await inferenceClient.keepPreparedModelWarmForRecording()
    }

    func prepareForRecording() async {
        guard availability == .available, isDownloaded, let snapshotURL else {
            return
        }

        do {
            try await inferenceClient.prepare(
                modelDirectory: snapshotURL,
                systemPrompt: model.systemPrompt
            )
        } catch is CancellationError {
        } catch {
            logger.error(
                "Background model preparation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    @MainActor
    private func downloadModel() async {
        downloadProgress = 0
        downloadedBytes = 0
        totalDownloadBytes = model.totalBytes
        isFinalizingDownload = false
        downloadError = nil
        isDownloading = true

        defer {
            isDownloading = false
            isFinalizingDownload = false
            downloadTask = nil
        }

        #if arch(arm64)
            let downloader = VoiceInkRefineModelDownloader(
                repositoryID: model.repositoryID,
                revision: model.pinnedRevision,
                modelRootDirectory: modelRootDirectory,
                files: model.files
            )
            let progressTask = Task { @MainActor [weak self, downloader] in
                while !Task.isCancelled {
                    self?.applyDownloadProgress(downloader.progress)
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            defer {
                progressTask.cancel()
            }

            do {
                let downloadOperation = Task.detached(priority: .utility) {
                    try await downloader.download()
                }
                defer {
                    downloadOperation.cancel()
                }

                try await withTaskCancellationHandler {
                    try await downloadOperation.value
                } onCancel: {
                    downloadOperation.cancel()
                }
                try Task.checkCancellation()
                applyDownloadProgress(downloader.progress)
                refreshDownloadedState()
                downloadProgress = isDownloaded ? 1 : 0
                NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            } catch is CancellationError {
                cleanupCancelledDownload()
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    cleanupCancelledDownload()
                } else {
                    downloadError = error.localizedDescription
                    logger.error("Failed to download VoiceInk Refine: \(error.localizedDescription, privacy: .public)")
                }
            }
        #else
            downloadError = VoiceInkRefineError.unavailable.localizedDescription
        #endif
    }

    private func cleanupCancelledDownload() {
        try? FileManager.default.removeItem(at: modelRootDirectory)
        downloadProgress = 0
        downloadedBytes = 0
        refreshDownloadedState()
        downloadError = nil
    }

    private var snapshotURL: URL? {
        #if arch(arm64)
            return VoiceInkRefineModelDownloader.snapshotDirectory(
                in: modelRootDirectory,
                repositoryID: model.repositoryID,
                revision: model.pinnedRevision
            )
        #else
            return nil
        #endif
    }

    private func refreshDownloadedState() {
        guard let snapshotURL else {
            isDownloaded = false
            return
        }

        isDownloaded = VoiceInkRefineModelDownloader.isSnapshotComplete(
            at: snapshotURL,
            files: model.files
        )
    }

    @MainActor
    private func applyDownloadProgress(
        _ progress: VoiceInkRefineDownloadProgress
    ) {
        downloadedBytes = progress.downloadedBytes
        totalDownloadBytes = progress.totalBytes
        isFinalizingDownload = progress.isFinalizing
        downloadProgress = progress.totalBytes > 0
            ? min(1, Double(progress.downloadedBytes) / Double(progress.totalBytes))
            : 0
    }
}

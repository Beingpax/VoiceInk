import Foundation
import FluidAudio
import AppKit
import os

@MainActor
class FluidAudioModelManager: ObservableObject {
    @Published var parakeetDownloadStates: [String: Bool] = [:]
    @Published var downloadProgress: [String: Double] = [:]

    var onModelDeleted: ((String) -> Void)?
    var onModelsChanged: (() -> Void)?

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FluidAudioModelManager")

    // Add new Fluid Audio models here when support is added.
    static let modelVersionMap: [String: AsrModelVersion] = [
        "parakeet-tdt-0.6b-v2": .v2,
        "parakeet-tdt-0.6b-v3": .v3,
    ]

    nonisolated static func asrVersion(for modelName: String) -> AsrModelVersion {
        modelVersionMap[modelName] ?? .v3
    }

    // MARK: - Chunk-size settings (Nemotron / Parakeet EOU)

    /// Allowed Nemotron chunk sizes (ms). Must be a member of NemotronChunkSize.
    static let allowedNemotronChunkMs: [Int] = [80, 160, 560, 1120]
    /// Allowed Parakeet EOU chunk sizes (ms). Must be a member of StreamingChunkSize.
    static let allowedParakeetEouChunkMs: [Int] = [160, 320, 1280]

    static let defaultNemotronChunkMs = 1120
    static let defaultParakeetEouChunkMs = 1280

    private static let nemotronChunkKey = "nemotron-chunk-size-ms"
    private static let parakeetEouChunkKey = "parakeet-eou-chunk-size-ms"

    var nemotronChunkSize: NemotronChunkSize {
        get {
            let stored = UserDefaults.standard.object(forKey: Self.nemotronChunkKey) as? Int
                ?? Self.defaultNemotronChunkMs
            return NemotronChunkSize(rawValue: stored) ?? .ms1120
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.nemotronChunkKey)
            onModelsChanged?()
        }
    }

    var parakeetEouChunkSize: StreamingChunkSize {
        get {
            let stored = UserDefaults.standard.object(forKey: Self.parakeetEouChunkKey) as? Int
                ?? Self.defaultParakeetEouChunkMs
            switch stored {
            case 160: return .ms160
            case 320: return .ms320
            default:  return .ms1280
            }
        }
        set {
            let ms: Int
            switch newValue {
            case .ms160:  ms = 160
            case .ms320:  ms = 320
            case .ms1280: ms = 1280
            }
            UserDefaults.standard.set(ms, forKey: Self.parakeetEouChunkKey)
            onModelsChanged?()
        }
    }

    init() {}

    // MARK: - Query helpers

    func isFluidAudioModelDownloaded(_ model: FluidAudioModel) -> Bool {
        UserDefaults.standard.bool(forKey: downloadedDefaultsKey(for: model))
    }

    /// Legacy name-based lookup. Kept for call sites that only have a model name.
    /// Resolves the PredefinedModels entry to pick up family + chunk size.
    func isFluidAudioModelDownloaded(named modelName: String) -> Bool {
        guard let model = PredefinedModels.models
            .compactMap({ $0 as? FluidAudioModel })
            .first(where: { $0.name == modelName }) else {
            return false
        }
        return isFluidAudioModelDownloaded(model)
    }

    func isFluidAudioModelDownloading(_ model: FluidAudioModel) -> Bool {
        parakeetDownloadStates[progressKey(for: model)] ?? false
    }

    func downloadProgress(for model: FluidAudioModel) -> Double? {
        downloadProgress[progressKey(for: model)]
    }

    // MARK: - Download

    func downloadFluidAudioModel(_ model: FluidAudioModel) async {
        if isFluidAudioModelDownloaded(model) { return }

        let modelName = model.name
        let key = progressKey(for: model)
        parakeetDownloadStates[key] = true
        downloadProgress[key] = 0.0

        let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { timer in
            Task { @MainActor in
                if let currentProgress = self.downloadProgress[key], currentProgress < 0.9 {
                    self.downloadProgress[key] = currentProgress + 0.005
                }
            }
        }

        let defaultsKey = downloadedDefaultsKey(for: model)

        do {
            switch model.family {
            case .parakeetTdt:
                let version = FluidAudioModelManager.asrVersion(for: modelName)
                _ = try await AsrModels.downloadAndLoad(version: version)
                _ = try await VadManager()

            case .nemotronStreaming:
                // StreamingNemotronAsrManager.loadModels(to:) downloads + loads if missing.
                let manager = StreamingNemotronAsrManager(
                    requestedChunkSize: nemotronChunkSize
                )
                try await manager.loadModels(to: nil, configuration: nil, progressHandler: nil)
                await manager.cleanup()

            case .parakeetEou:
                let manager = StreamingEouAsrManager(chunkSize: parakeetEouChunkSize)
                try await manager.loadModels(to: nil, configuration: nil, progressHandler: nil)
                await manager.cleanup()
            }

            UserDefaults.standard.set(true, forKey: defaultsKey)
            downloadProgress[key] = 1.0
        } catch {
            UserDefaults.standard.set(false, forKey: defaultsKey)
            logger.error("❌ FluidAudio download failed for \(modelName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        timer.invalidate()
        parakeetDownloadStates[key] = false
        downloadProgress[key] = nil

        onModelsChanged?()
    }

    // MARK: - Delete

    func deleteFluidAudioModel(_ model: FluidAudioModel) {
        let cacheDirectory = cacheDirectory(for: model)

        do {
            if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.removeItem(at: cacheDirectory)
            }
            UserDefaults.standard.set(false, forKey: downloadedDefaultsKey(for: model))
        } catch {
            // Silently ignore removal errors
        }

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

    /// Dict key for in-flight download state. Matches `downloadedDefaultsKey` scoping:
    /// - parakeetTdt: just the model name (one variant)
    /// - nemotronStreaming: model name + current chunk size
    /// - parakeetEou: model name + current chunk size
    private func progressKey(for model: FluidAudioModel) -> String {
        switch model.family {
        case .parakeetTdt:
            return model.name
        case .nemotronStreaming:
            return "\(model.name)@\(nemotronChunkSize.rawValue)"
        case .parakeetEou:
            let ms: Int
            switch parakeetEouChunkSize {
            case .ms160:  ms = 160
            case .ms320:  ms = 320
            case .ms1280: ms = 1280
            }
            return "\(model.name)@\(ms)"
        }
    }

    /// Stable UserDefaults key for tracking whether a given model+chunk variant is downloaded.
    /// For parakeetTdt family, the key does not include chunk size (there is only one variant).
    /// For nemotronStreaming / parakeetEou, the chunk size is appended so each variant
    /// tracks its own download state.
    private func downloadedDefaultsKey(for model: FluidAudioModel) -> String {
        switch model.family {
        case .parakeetTdt:
            return "ParakeetModelDownloaded_\(model.name)"
        case .nemotronStreaming:
            return "NemotronStreamingDownloaded_\(nemotronChunkSize.rawValue)"
        case .parakeetEou:
            let ms: Int
            switch parakeetEouChunkSize {
            case .ms160:  ms = 160
            case .ms320:  ms = 320
            case .ms1280: ms = 1280
            }
            return "ParakeetEouDownloaded_\(ms)"
        }
    }

    /// Directory on disk backing the given model's currently-selected variant.
    /// For parakeetTdt this is version-keyed; for Nemotron / EOU it is chunk-size-keyed
    /// under the FluidAudio SDK's default Application Support cache.
    private func cacheDirectory(for model: FluidAudioModel) -> URL {
        switch model.family {
        case .parakeetTdt:
            let version = FluidAudioModelManager.asrVersion(for: model.name)
            return AsrModels.defaultCacheDirectory(for: version)

        case .nemotronStreaming:
            // StreamingNemotronAsrManager caches under:
            //   <AppSupport>/FluidAudio/Models/nemotron-streaming/<chunkSize>ms/
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return root
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent("nemotron-streaming", isDirectory: true)
                .appendingPathComponent("\(nemotronChunkSize.rawValue)ms", isDirectory: true)

        case .parakeetEou:
            // StreamingEouAsrManager caches under:
            //   <AppSupport>/FluidAudio/Models/parakeet-eou-streaming/<folderName>/
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let subdir: String
            switch parakeetEouChunkSize {
            case .ms160:  subdir = "160ms"
            case .ms320:  subdir = "320ms"
            case .ms1280: subdir = "1280ms"
            }
            return root
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent("parakeet-eou-streaming", isDirectory: true)
                .appendingPathComponent(subdir, isDirectory: true)
        }
    }
}

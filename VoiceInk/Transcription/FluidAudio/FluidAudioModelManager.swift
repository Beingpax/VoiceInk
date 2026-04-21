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

    init() {}

    // MARK: - Query helpers

    func isFluidAudioModelDownloaded(_ model: FluidAudioModel) -> Bool {
        UserDefaults.standard.bool(forKey: downloadedDefaultsKey(for: model))
    }

    /// Legacy name-based lookup. Kept for call sites that only have a model name.
    func isFluidAudioModelDownloaded(named modelName: String) -> Bool {
        guard let model = TranscriptionModelRegistry.models
            .compactMap({ $0 as? FluidAudioModel })
            .first(where: { $0.name == modelName }) else {
            return false
        }
        return isFluidAudioModelDownloaded(model)
    }

    func isFluidAudioModelDownloading(_ model: FluidAudioModel) -> Bool {
        parakeetDownloadStates[model.name] ?? false
    }

    func downloadProgress(for model: FluidAudioModel) -> Double? {
        downloadProgress[model.name]
    }

    // MARK: - Download

    func downloadFluidAudioModel(_ model: FluidAudioModel) async {
        if isFluidAudioModelDownloaded(model) { return }

        let modelName = model.name
        parakeetDownloadStates[modelName] = true
        downloadProgress[modelName] = 0.0

        let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { timer in
            Task { @MainActor in
                if let currentProgress = self.downloadProgress[modelName], currentProgress < 0.9 {
                    self.downloadProgress[modelName] = currentProgress + 0.005
                }
            }
        }

        let defaultsKey = downloadedDefaultsKey(for: model)

        do {
            let version = FluidAudioModelManager.asrVersion(for: modelName)
            _ = try await AsrModels.downloadAndLoad(version: version)
            _ = try await VadManager()

            UserDefaults.standard.set(true, forKey: defaultsKey)
            downloadProgress[modelName] = 1.0
        } catch {
            UserDefaults.standard.set(false, forKey: defaultsKey)
            logger.error("❌ FluidAudio download failed for \(modelName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        timer.invalidate()
        parakeetDownloadStates[modelName] = false
        downloadProgress[modelName] = nil

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

    private func downloadedDefaultsKey(for model: FluidAudioModel) -> String {
        "ParakeetModelDownloaded_\(model.name)"
    }

    private func cacheDirectory(for model: FluidAudioModel) -> URL {
        let version = FluidAudioModelManager.asrVersion(for: model.name)
        return AsrModels.defaultCacheDirectory(for: version)
    }
}

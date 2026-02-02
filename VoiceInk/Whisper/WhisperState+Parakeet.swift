import Foundation
import FluidAudio
import AppKit

extension WhisperState {
    private func parakeetDefaultsKey(for modelName: String) -> String {
        "ParakeetModelDownloaded_\(modelName)"
    }

    private func parakeetVersion(for modelName: String) -> AsrModelVersion {
        modelName.lowercased().contains("v2") ? .v2 : .v3
    }

    private func parakeetCacheDirectory(for version: AsrModelVersion) -> URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    func isParakeetModelDownloaded(named modelName: String) -> Bool {
        UserDefaults.standard.bool(forKey: parakeetDefaultsKey(for: modelName))
    }

    func isParakeetModelDownloaded(_ model: ParakeetModel) -> Bool {
        isParakeetModelDownloaded(named: model.name)
    }

    func isParakeetModelDownloading(_ model: ParakeetModel) -> Bool {
        parakeetDownloadStates[model.name] ?? false
    }

    @MainActor
    func downloadParakeetModel(_ model: ParakeetModel) async {
        if isParakeetModelDownloaded(model) {
            return
        }

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

        let version = parakeetVersion(for: modelName)

        do {
            _ = try await AsrModels.downloadAndLoad(version: version)

            _ = try await VadManager()

            // Download CTC model for vocabulary boosting
            _ = try await CtcModels.downloadAndLoad(variant: .ctc110m)

            UserDefaults.standard.set(true, forKey: parakeetDefaultsKey(for: modelName))
            downloadProgress[modelName] = 1.0
        } catch {
            UserDefaults.standard.set(false, forKey: parakeetDefaultsKey(for: modelName))
        }

        timer.invalidate()
        parakeetDownloadStates[modelName] = false
        downloadProgress[modelName] = nil

        refreshAllAvailableModels()
    }

    @MainActor
    func deleteParakeetModel(_ model: ParakeetModel) {
        if let currentModel = currentTranscriptionModel,
           currentModel.provider == .parakeet,
           currentModel.name == model.name {
            currentTranscriptionModel = nil
            UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
        }

        let version = parakeetVersion(for: model.name)
        let cacheDirectory = parakeetCacheDirectory(for: version)

        do {
            if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.removeItem(at: cacheDirectory)
            }
            UserDefaults.standard.set(false, forKey: parakeetDefaultsKey(for: model.name))
        } catch {
            // Silently ignore removal errors
        }

        // Clean up CTC model if no other Parakeet model is downloaded
        let hasOtherParakeetModel = allAvailableModels
            .compactMap { $0 as? ParakeetModel }
            .contains { $0.name != model.name && isParakeetModelDownloaded($0) }

        if !hasOtherParakeetModel {
            let ctcDirectory = CtcModels.defaultCacheDirectory(for: .ctc110m)
            try? FileManager.default.removeItem(at: ctcDirectory)
            serviceRegistry.parakeetVocabularyService.cleanup()
        }

        refreshAllAvailableModels()
    }

    @MainActor
    func showParakeetModelInFinder(_ model: ParakeetModel) {
        let cacheDirectory = parakeetCacheDirectory(for: parakeetVersion(for: model.name))

        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            NSWorkspace.shared.selectFile(cacheDirectory.path, inFileViewerRootedAtPath: "")
        }
    }
}

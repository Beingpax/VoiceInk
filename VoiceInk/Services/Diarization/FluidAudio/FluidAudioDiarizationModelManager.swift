import Foundation
import FluidAudio
import os.log

/// Downloads and caches the offline diarization models from HuggingFace on first use.
/// Models are stored under ~/Library/Application Support/FluidAudio/Models/speaker-diarization/
/// via OfflineDiarizerModels.defaultModelsDirectory() (resolves to FluidAudio's shared model dir).
@MainActor
final class FluidAudioDiarizationModelManager {
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FluidAudioDiarizationModelManager")

    // Cached UserDefaults flag used only as a fast-path hint — the source of truth is disk.
    private let downloadedDefaultsKey = "OfflineDiarizerModelsDownloaded"

    // Required model files inside the offline diarizer directory.
    private let requiredFiles = ["Segmentation.mlmodelc", "FBank.mlmodelc", "Embedding.mlmodelc", "PldaRho.mlmodelc"]

    private var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models/speaker-diarization")
    }

    var areModelsDownloaded: Bool {
        // Probe disk — don't trust UserDefaults alone. If the cache was wiped externally
        // (e.g. user deleted the folder), the flag can lie and the next diarize call will
        // fail deep in model-load. Re-download instead.
        let dir = modelsDirectory
        for file in requiredFiles {
            if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(file).path) {
                return false
            }
        }
        return true
    }

    /// Ensures offline diarizer models are present locally, downloading if needed.
    func ensureModelsDownloaded() async throws {
        if areModelsDownloaded {
            UserDefaults.standard.set(true, forKey: downloadedDefaultsKey)
            return
        }

        isDownloading = true
        downloadProgress = 0.0

        // Simulate incremental progress while download+compile runs in the background.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.downloadProgress < 0.9 else { return }
                self.downloadProgress += 0.005
            }
        }

        defer {
            timer.invalidate()
            isDownloading = false
            downloadProgress = areModelsDownloaded ? 1.0 : 0.0
        }

        do {
            // OfflineDiarizerModels.load() downloads from Repo.diarizer
            // (FluidInference/speaker-diarization-coreml) with variant "offline"
            // and compiles all four CoreML models to the default models directory.
            _ = try await OfflineDiarizerModels.load()
            UserDefaults.standard.set(true, forKey: downloadedDefaultsKey)
            downloadProgress = 1.0
            logger.info("Offline diarizer models downloaded and compiled")
        } catch {
            UserDefaults.standard.set(false, forKey: downloadedDefaultsKey)
            logger.error("Offline diarizer model download failed: \(error.localizedDescription, privacy: .public)")
            throw DiarizationError.modelMissing
        }
    }

    /// Clears the downloaded flag so the next call to ensureModelsDownloaded() re-fetches.
    func markModelsAsInvalid() {
        UserDefaults.standard.set(false, forKey: downloadedDefaultsKey)
    }
}

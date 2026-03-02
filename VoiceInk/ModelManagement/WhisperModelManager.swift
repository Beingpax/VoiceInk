import Foundation
import os
import Zip
import SwiftUI
import Atomics

struct WhisperModel: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var coreMLEncoderURL: URL?
    var isCoreMLDownloaded: Bool { coreMLEncoderURL != nil }

    var downloadURL: String {
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)"
    }

    var filename: String {
        "\(name).bin"
    }

    var coreMLZipDownloadURL: String? {
        guard !name.contains("q5") && !name.contains("q8") else { return nil }
        return "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(name)-encoder.mlmodelc.zip"
    }

    var coreMLEncoderDirectoryName: String? {
        guard coreMLZipDownloadURL != nil else { return nil }
        return "\(name)-encoder.mlmodelc"
    }
}

private class TaskDelegate: NSObject, URLSessionTaskDelegate {
    private let continuation: CheckedContinuation<Void, Never>
    private let finished = ManagedAtomic(false)

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if finished.exchange(true, ordering: .acquiring) == false {
            continuation.resume()
        }
    }
}

@MainActor
class WhisperModelManager: ObservableObject {
    @Published var availableModels: [WhisperModel] = []
    @Published var isModelLoaded = false
    @Published var loadedLocalModel: WhisperModel?
    @Published var isModelLoading = false
    @Published var downloadProgress: [String: Double] = [:]

    var whisperContext: WhisperContext?
    let whisperPrompt = WhisperPrompt()
    let modelsDirectory: URL
    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperModelManager")

    /// Called when models list changes so ModelManager can refresh
    var onModelsChanged: (() -> Void)?
    /// Called after a model download completes and warmup should be considered
    var onModelDownloaded: ((_ model: LocalModel) -> Void)?

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    // MARK: - Model Directory Management

    func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logError("Error creating models directory", error)
        }
    }

    func loadAvailableModels() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
            availableModels = fileURLs.compactMap { url in
                guard url.pathExtension == "bin" else { return nil }
                return WhisperModel(name: url.deletingPathExtension().lastPathComponent, url: url)
            }
        } catch {
            logError("Error loading available models", error)
        }
    }

    // MARK: - Model Loading

    func loadModel(_ model: WhisperModel) async throws {
        guard whisperContext == nil else { return }

        isModelLoading = true
        defer { isModelLoading = false }

        do {
            whisperContext = try await WhisperContext.createContext(path: model.url.path)

            let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? whisperPrompt.transcriptionPrompt
            await whisperContext?.setPrompt(currentPrompt)

            isModelLoaded = true
            loadedLocalModel = model
        } catch {
            throw VoiceInkEngineError.modelLoadFailed
        }
    }

    // MARK: - Model Download & Management

    private func downloadFileWithProgress(from url: URL, progressKey: String) async throws -> URL {
        let destinationURL = modelsDirectory.appendingPathComponent(UUID().uuidString)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let finished = ManagedAtomic(false)

            func finishOnce(_ result: Result<URL, Error>) {
                if finished.exchange(true, ordering: .acquiring) == false {
                    continuation.resume(with: result)
                }
            }

            // Holds the KVO observation so it stays alive until the download completes
            var observationHolder: NSKeyValueObservation?

            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                // Prevent early deallocation of the KVO observation
                withExtendedLifetime(observationHolder) {}

                if let error = error {
                    finishOnce(.failure(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let tempURL = tempURL else {
                    finishOnce(.failure(URLError(.badServerResponse)))
                    return
                }

                do {
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    finishOnce(.success(destinationURL))
                } catch {
                    finishOnce(.failure(error))
                }
            }

            task.resume()

            var lastUpdateTime = Date()
            var lastProgressValue: Double = 0

            observationHolder = task.progress.observe(\.fractionCompleted) { progress, _ in
                let currentTime = Date()
                let timeSinceLastUpdate = currentTime.timeIntervalSince(lastUpdateTime)
                let currentProgress = round(progress.fractionCompleted * 100) / 100

                if timeSinceLastUpdate >= 0.5 && abs(currentProgress - lastProgressValue) >= 0.01 {
                    lastUpdateTime = currentTime
                    lastProgressValue = currentProgress

                    DispatchQueue.main.async {
                        self.downloadProgress[progressKey] = currentProgress
                    }
                }
            }
        }
    }

    func downloadModel(_ model: LocalModel) async {
        guard let url = URL(string: model.downloadURL) else { return }
        await performModelDownload(model, url)
    }

    private func performModelDownload(_ model: LocalModel, _ url: URL) async {
        do {
            var whisperModel = try await downloadMainModel(model, from: url)

            if let coreMLZipURL = whisperModel.coreMLZipDownloadURL,
               let coreMLURL = URL(string: coreMLZipURL) {
                whisperModel = try await downloadAndSetupCoreMLModel(for: whisperModel, from: coreMLURL)
            }

            availableModels.append(whisperModel)
            self.downloadProgress.removeValue(forKey: model.name + "_main")
            onModelsChanged?()

            if shouldWarmup(model) {
                onModelDownloaded?(model)
            }
        } catch {
            handleModelDownloadError(model, error)
        }
    }

    private func downloadMainModel(_ model: LocalModel, from url: URL) async throws -> WhisperModel {
        let progressKeyMain = model.name + "_main"
        let tempURL = try await downloadFileWithProgress(from: url, progressKey: progressKeyMain)

        let destinationURL = modelsDirectory.appendingPathComponent(model.filename)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        return WhisperModel(name: model.name, url: destinationURL)
    }

    private func downloadAndSetupCoreMLModel(for model: WhisperModel, from url: URL) async throws -> WhisperModel {
        let progressKeyCoreML = model.name + "_coreml"
        let tempURL = try await downloadFileWithProgress(from: url, progressKey: progressKeyCoreML)

        let coreMLZipPath = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc.zip")
        try FileManager.default.moveItem(at: tempURL, to: coreMLZipPath)

        return try await unzipAndSetupCoreMLModel(for: model, zipPath: coreMLZipPath, progressKey: progressKeyCoreML)
    }

    private func unzipAndSetupCoreMLModel(for model: WhisperModel, zipPath: URL, progressKey: String) async throws -> WhisperModel {
        let coreMLDestination = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc")

        try? FileManager.default.removeItem(at: coreMLDestination)
        try await unzipCoreMLFile(zipPath, to: modelsDirectory)
        return try verifyAndCleanupCoreMLFiles(model, coreMLDestination, zipPath, progressKey)
    }

    private func unzipCoreMLFile(_ zipPath: URL, to destination: URL) async throws {
        let finished = ManagedAtomic(false)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            func finishOnce(_ result: Result<Void, Error>) {
                if finished.exchange(true, ordering: .acquiring) == false {
                    continuation.resume(with: result)
                }
            }

            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try Zip.unzipFile(zipPath, destination: destination, overwrite: true, password: nil)
                finishOnce(.success(()))
            } catch {
                finishOnce(.failure(error))
            }
        }
    }

    private func verifyAndCleanupCoreMLFiles(_ model: WhisperModel, _ destination: URL, _ zipPath: URL, _ progressKey: String) throws -> WhisperModel {
        var model = model

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            try? FileManager.default.removeItem(at: zipPath)
            throw VoiceInkEngineError.unzipFailed
        }

        try? FileManager.default.removeItem(at: zipPath)
        model.coreMLEncoderURL = destination
        self.downloadProgress.removeValue(forKey: progressKey)

        return model
    }

    private func shouldWarmup(_ model: LocalModel) -> Bool {
        !model.name.contains("q5") && !model.name.contains("q8")
    }

    private func handleModelDownloadError(_ model: LocalModel, _ error: Error) {
        self.downloadProgress.removeValue(forKey: model.name + "_main")
        self.downloadProgress.removeValue(forKey: model.name + "_coreml")
    }

    func deleteModel(_ model: WhisperModel, currentTranscriptionModelName: String?) async -> Bool {
        var didClearCurrentModel = false
        do {
            try FileManager.default.removeItem(at: model.url)

            if let coreMLURL = model.coreMLEncoderURL {
                try? FileManager.default.removeItem(at: coreMLURL)
            } else {
                let coreMLDir = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc")
                if FileManager.default.fileExists(atPath: coreMLDir.path) {
                    try? FileManager.default.removeItem(at: coreMLDir)
                }
            }

            availableModels.removeAll { $0.id == model.id }
            if currentTranscriptionModelName == model.name {
                didClearCurrentModel = true
                loadedLocalModel = nil
            }
        } catch {
            logError("Error deleting model: \(model.name)", error)
        }

        return didClearCurrentModel
    }

    func unloadModel() async {
        await whisperContext?.releaseResources()
        whisperContext = nil
        isModelLoaded = false
    }

    func clearDownloadedModels() async {
        for model in availableModels {
            do {
                try FileManager.default.removeItem(at: model.url)
            } catch {
                logError("Error deleting model during cleanup", error)
            }
        }
        availableModels.removeAll()
    }

    // MARK: - Resource Management

    func cleanupModelResources(serviceRegistry: TranscriptionServiceRegistry?) async {
        logger.notice("cleanupModelResources: releasing model resources")
        await whisperContext?.releaseResources()
        whisperContext = nil
        isModelLoaded = false
        serviceRegistry?.cleanup()
        logger.notice("cleanupModelResources: completed")
    }

    // MARK: - Import Local Model

    @MainActor
    func importLocalModel(from sourceURL: URL) async {
        guard sourceURL.pathExtension.lowercased() == "bin" else { return }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let destinationURL = modelsDirectory.appendingPathComponent("\(baseName).bin")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            await NotificationManager.shared.showNotification(
                title: "A model named \(baseName).bin already exists",
                type: .warning,
                duration: 4.0
            )
            return
        }

        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            let newWhisperModel = WhisperModel(name: baseName, url: destinationURL)
            availableModels.append(newWhisperModel)

            await NotificationManager.shared.showNotification(
                title: "Imported \(destinationURL.lastPathComponent)",
                type: .success,
                duration: 3.0
            )
        } catch {
            logError("Failed to import local model", error)
            await NotificationManager.shared.showNotification(
                title: "Failed to import model: \(error.localizedDescription)",
                type: .error,
                duration: 5.0
            )
        }

        onModelsChanged?()
    }

    // MARK: - Prompt Update

    func updateContextPrompt() async {
        let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? whisperPrompt.transcriptionPrompt
        if let context = whisperContext {
            await context.setPrompt(currentPrompt)
        }
    }

    // MARK: - Helper Methods

    private func logError(_ message: String, _ error: Error) {
        self.logger.error("\(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - Download Progress View
struct DownloadProgressView: View {
    let modelName: String
    let downloadProgress: [String: Double]

    @Environment(\.colorScheme) private var colorScheme

    private var mainProgress: Double {
        downloadProgress[modelName + "_main"] ?? 0
    }

    private var coreMLProgress: Double {
        supportsCoreML ? (downloadProgress[modelName + "_coreml"] ?? 0) : 0
    }

    private var supportsCoreML: Bool {
        !modelName.contains("q5") && !modelName.contains("q8")
    }

    private var totalProgress: Double {
        supportsCoreML ? (mainProgress * 0.5) + (coreMLProgress * 0.5) : mainProgress
    }

    private var downloadPhase: String {
        if supportsCoreML && downloadProgress[modelName + "_coreml"] != nil {
            return "Downloading Core ML Model for \(modelName)"
        }
        return "Downloading \(modelName) Model"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(downloadPhase)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(.secondaryLabelColor))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.separatorColor).opacity(0.3))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.controlAccentColor))
                        .frame(width: max(0, min(geometry.size.width * totalProgress, geometry.size.width)), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Spacer()
                Text("\(Int(totalProgress * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(.secondaryLabelColor))
            }
        }
        .padding(.vertical, 4)
        .animation(.smooth, value: totalProgress)
    }
}

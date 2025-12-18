import Foundation
import AppKit

extension WhisperState {
    private func senseVoiceDefaultsKey(for modelName: String) -> String {
        "SenseVoiceModelDownloaded_\(modelName)"
    }

    func isSenseVoiceModelDownloaded(named modelName: String) -> Bool {
        UserDefaults.standard.bool(forKey: senseVoiceDefaultsKey(for: modelName))
    }

    func isSenseVoiceModelDownloaded(_ model: SenseVoiceModel) -> Bool {
        let directory = senseVoiceModelDirectory(for: model)
        let modelFile = directory.appendingPathComponent("model.int8.onnx")
        let tokenizerFile = directory.appendingPathComponent("tokens.txt")
        return FileManager.default.fileExists(atPath: modelFile.path) &&
            FileManager.default.fileExists(atPath: tokenizerFile.path)
    }

    private func senseVoiceModelDirectory(for model: SenseVoiceModel) -> URL {
        senseVoiceModelsDirectory.appendingPathComponent(model.name)
    }

    @MainActor
    func downloadSenseVoiceModel(_ model: SenseVoiceModel) async {
        if isSenseVoiceModelDownloaded(model) {
            return
        }

        let modelName = model.name
        senseVoiceDownloadProgress[modelName] = 0.01

        let directory = senseVoiceModelDirectory(for: model)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            guard let modelURL = URL(string: model.modelURL),
                  let tokenizerURL = URL(string: model.tokenizerURL) else {
                throw NSError(domain: "SenseVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid model URLs"])
            }

            let modelFile = directory.appendingPathComponent("model.int8.onnx")
            let tokenizerFile = directory.appendingPathComponent("tokens.txt")

            // Download model file
            senseVoiceDownloadProgress[modelName] = 0.05
            let (modelData, modelResponse) = try await URLSession.shared.data(from: modelURL)
            if let httpResponse = modelResponse as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw NSError(domain: "SenseVoice", code: httpResponse.statusCode, 
                              userInfo: [NSLocalizedDescriptionKey: "Model download failed with status \(httpResponse.statusCode)"])
            }
            try modelData.write(to: modelFile)
            senseVoiceDownloadProgress[modelName] = 0.85

            // Download tokenizer file
            let (tokenizerData, tokenizerResponse) = try await URLSession.shared.data(from: tokenizerURL)
            if let httpResponse = tokenizerResponse as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw NSError(domain: "SenseVoice", code: httpResponse.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "Tokenizer download failed with status \(httpResponse.statusCode)"])
            }
            try tokenizerData.write(to: tokenizerFile)
            senseVoiceDownloadProgress[modelName] = 1.0

            UserDefaults.standard.set(true, forKey: senseVoiceDefaultsKey(for: modelName))
            senseVoiceTranscriptionService.invalidateSession(for: modelName)
            
            await NotificationManager.shared.showNotification(
                title: "SenseVoice model downloaded successfully",
                type: .success,
                duration: 3.0
            )
        } catch {
            senseVoiceDownloadProgress[modelName] = nil
            UserDefaults.standard.set(false, forKey: senseVoiceDefaultsKey(for: modelName))
            try? FileManager.default.removeItem(at: directory)
            
            await NotificationManager.shared.showNotification(
                title: "SenseVoice download failed: \(error.localizedDescription)",
                type: .error,
                duration: 4.0
            )
        }
        
        refreshAllAvailableModels()
    }

    @MainActor
    func deleteSenseVoiceModel(_ model: SenseVoiceModel) {
        // Clear current selection if this model is active
        if let currentModel = currentTranscriptionModel,
           currentModel.provider == .senseVoice,
           currentModel.name == model.name {
            currentTranscriptionModel = nil
            UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
        }
        
        let directory = senseVoiceModelDirectory(for: model)
        try? FileManager.default.removeItem(at: directory)
        senseVoiceDownloadProgress[model.name] = nil
        UserDefaults.standard.set(false, forKey: senseVoiceDefaultsKey(for: model.name))
        senseVoiceTranscriptionService.invalidateSession(for: model.name)
        
        refreshAllAvailableModels()
    }

    func showSenseVoiceModelInFinder(_ model: SenseVoiceModel) {
        let directory = senseVoiceModelDirectory(for: model)
        if FileManager.default.fileExists(atPath: directory.path) {
            NSWorkspace.shared.selectFile(directory.path, inFileViewerRootedAtPath: "")
        }
    }
}

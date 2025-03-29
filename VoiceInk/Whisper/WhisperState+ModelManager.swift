import Foundation
import os

// MARK: - Model Management Extension
extension WhisperState {
    
    // MARK: - Model Directory Management
    
    func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            messageLog += "Error creating models directory: \(error.localizedDescription)\n"
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
            messageLog += "Error loading available models: \(error.localizedDescription)\n"
        }
    }
    
    // MARK: - Model Loading
    
    func loadModel(_ model: WhisperModel) async throws {
        if transcriptionServiceType != .local {
            transcriptionServiceType = .local
        }
        
        logger.notice("🔄 Loading Whisper model: \(model.name)")
        isModelLoading = true
        defer { isModelLoading = false }
        
        currentModel = model
        UserDefaults.standard.currentModel = model.name
        
        await cleanupServiceResources()
        
        let configuration: [String: Any] = ["modelPath": model.url.path]
        do {
            transcriptionService = try await serviceFactory.createService(type: .local, configuration: configuration)
            isModelLoaded = true
            canTranscribe = true
            logger.notice("✅ Successfully loaded model: \(model.name)")
        } catch {
            logger.error("❌ Failed to load model: \(model.name) - \(error.localizedDescription)")
            throw WhisperStateError.modelLoadFailed
        }
    }
    
    func setDefaultModel(_ model: WhisperModel) async {
        do {
            currentModel = model
            UserDefaults.standard.currentModel = model.name
            canTranscribe = true
        } catch {
            currentError = error as? WhisperStateError ?? .unknownError
            canTranscribe = false
        }
    }
    
    // MARK: - Model Download & Management
    
    func downloadModel(_ model: PredefinedModel) async {
        guard let url = URL(string: model.downloadURL) else { return }

        logger.notice("🔽 Downloading model: \(model.name)")
        do {
            let (data, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                let task = URLSession.shared.dataTask(with: url) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode),
                          let data = data else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    continuation.resume(returning: (data, httpResponse))
                }
                
                task.resume()
                
                let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                    DispatchQueue.main.async {
                        self.downloadProgress[model.name] = progress.fractionCompleted
                    }
                }
                
                Task {
                    await withTaskCancellationHandler {
                        observation.invalidate()
                    } operation: {
                        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                    }
                }
            }

            let destinationURL = modelsDirectory.appendingPathComponent(model.filename)
            try data.write(to: destinationURL)

            availableModels.append(WhisperModel(name: model.name, url: destinationURL))
            self.downloadProgress.removeValue(forKey: model.name)
            logger.notice("✅ Successfully downloaded model: \(model.name)")
        } catch {
            logger.error("❌ Failed to download model: \(model.name) - \(error.localizedDescription)")
            currentError = .modelDownloadFailed
            self.downloadProgress.removeValue(forKey: model.name)
        }
    }
    
    func deleteModel(_ model: WhisperModel) async {
        do {
            try FileManager.default.removeItem(at: model.url)
            availableModels.removeAll { $0.id == model.id }
            if currentModel?.id == model.id {
                currentModel = nil
                canTranscribe = false
            }
        } catch {
            messageLog += "Error deleting model: \(error.localizedDescription)\n"
            currentError = .modelDeletionFailed
        }
    }
    
    func unloadModel() {
        Task {
            await cleanupServiceResources()
            
            if let recordedFile = recordedFile {
                try? FileManager.default.removeItem(at: recordedFile)
                self.recordedFile = nil
            }
        }
    }
    
    func clearDownloadedModels() async {
        for model in availableModels {
            do {
                try FileManager.default.removeItem(at: model.url)
            } catch {
                messageLog += "Error deleting model: \(error.localizedDescription)\n"
            }
        }
        availableModels.removeAll()
    }
    
    // MARK: - Resource Management
    
    func cleanupServiceResources() async {
        recorder.stopRecording()
        
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let canCleanup = !isRecording && !isProcessing
        
        if canCleanup {
            logger.notice("🧹 Cleaning up Whisper resources")
            if let service = transcriptionService {
                await service.releaseResources()
                transcriptionService = nil
                isModelLoaded = false
            }
        } else {
            logger.info("Skipping cleanup while recording or processing is active")
        }
    }
} 

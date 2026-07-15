import Foundation

extension AIService {
    func enhanceWithVoiceInkRefine(
        text: String,
        systemPrompt: String,
        model: String? = nil
    ) async throws -> String {
        let result = try await voiceInkRefineService.enhance(
            text,
            systemPrompt: systemPrompt,
            modelID: model
        )
        guard !result.isEmpty else { throw VoiceInkRefineError.emptyOutput }
        return result
    }

    func preloadVoiceInkRefineModelIfDownloaded(
        _ modelID: String,
        recordingSessionID: UUID? = nil
    ) async throws {
        try await voiceInkRefineService.preloadIfDownloaded(
            modelID: modelID,
            recordingSessionID: recordingSessionID
        )
        await MainActor.run {
            self.objectWillChange.send()
        }
    }

    func releaseVoiceInkRefineRecordingSession(_ recordingSessionID: UUID) async {
        await voiceInkRefineService.releaseRecordingSession(recordingSessionID)
        await MainActor.run {
            self.objectWillChange.send()
        }
    }

    func unloadVoiceInkRefineModel() async {
        await voiceInkRefineService.unload()
        await MainActor.run {
            self.objectWillChange.send()
        }
    }

    func voiceInkRefineStorageInfo(for modelID: String) -> VoiceInkRefineModelStorageInfo {
        voiceInkRefineService.storageInfo(for: modelID)
    }

    func voiceInkRefineModelDirectory(for modelID: String) -> URL? {
        voiceInkRefineService.modelDirectory(for: modelID)
    }

    @MainActor
    func downloadVoiceInkRefineModel(_ modelID: String) async {
        guard voiceInkRefineDownloadProgress[modelID] == nil else { return }
        voiceInkRefineDownloadErrors[modelID] = nil
        voiceInkRefineDownloadProgress[modelID] = 0

        do {
            try await voiceInkRefineService.download(modelID: modelID) { [weak self] progress in
                guard let self, let currentProgress = self.voiceInkRefineDownloadProgress[modelID] else {
                    return
                }
                self.voiceInkRefineDownloadProgress[modelID] = max(currentProgress, min(max(progress, 0), 1))
            }
            voiceInkRefineDownloadProgress[modelID] = nil
        } catch {
            voiceInkRefineDownloadProgress[modelID] = nil
            voiceInkRefineDownloadErrors[modelID] = error.localizedDescription
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    @MainActor
    func deleteVoiceInkRefineModel(_ modelID: String) async {
        do {
            try await voiceInkRefineService.deleteDownloadedModel(modelID: modelID)
            voiceInkRefineDownloadErrors[modelID] = nil
        } catch {
            voiceInkRefineDownloadErrors[modelID] = error.localizedDescription
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
}

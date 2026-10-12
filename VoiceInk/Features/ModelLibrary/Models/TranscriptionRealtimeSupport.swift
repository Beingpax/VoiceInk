import Foundation

enum TranscriptionRealtimeSupport {
    static func isAvailable(for model: any TranscriptionModel) -> Bool {
        model.supportsStreaming
    }

    static func isRequired(for model: any TranscriptionModel) -> Bool {
        if model.provider == .fluidAudio {
            return FluidAudioModelManager.requiresRealtime(named: model.name)
        }

        return CloudProviderRegistry.provider(for: model.provider)?.isStreamingOnly ?? false
    }

    static func isEnabled(for model: any TranscriptionModel, modeValue: Bool? = nil) -> Bool {
        guard isAvailable(for: model) else { return false }
        if isRequired(for: model) { return true }
        if let modeValue { return modeValue }
        return true
    }
}

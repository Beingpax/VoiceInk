import Foundation

struct TranscriptionRequestContext {
    let language: String?
    let prompt: String?

    static var currentDefaults: TranscriptionRequestContext {
        let language = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        return TranscriptionRequestContext(
            language: language,
            prompt: WhisperPrompt.resolvedPrompt(for: language)
        )
    }

    func scoped(to model: any TranscriptionModel) -> TranscriptionRequestContext {
        guard model.provider == .whisper else {
            return TranscriptionRequestContext(language: language, prompt: nil)
        }

        return self
    }
}

/// A protocol defining the interface for a transcription service.
/// This allows for a unified way to handle both local and cloud-based transcription models.
protocol TranscriptionService {
    /// Transcribes the audio from a given file URL.
    ///
    /// - Parameters:
    ///   - audioURL: The URL of the audio file to transcribe.
    ///   - model: The `TranscriptionModel` to use for transcription. This provides context about the provider (local, OpenAI, etc.).
    /// - Returns: The transcribed text as a `String`.
    /// - Throws: An error if the transcription fails.
    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws
        -> String
}

extension TranscriptionService {
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let context = TranscriptionRequestContext.currentDefaults.scoped(to: model)
        return try await transcribe(audioURL: audioURL, model: model, context: context)
    }
}

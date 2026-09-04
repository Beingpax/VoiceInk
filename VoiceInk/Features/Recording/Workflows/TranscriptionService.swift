import Foundation

struct TranscriptionRequestContext {
    let language: String?
    let prompt: String?
    /// When true, word timestamps must match the original audio timeline —
    /// engines must not use silence-skipping (VAD) that compresses time.
    /// Required by diarization, which aligns words against the real timeline.
    var preservesTimeline: Bool = false

    static var currentDefaults: TranscriptionRequestContext {
        let language = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        return TranscriptionRequestContext(
            language: language,
            prompt: WhisperPrompt.resolvedPrompt(for: language)
        )
    }

    func scoped(to model: any TranscriptionModel) -> TranscriptionRequestContext {
        guard model.provider == .whisper else {
            return TranscriptionRequestContext(language: language, prompt: nil, preservesTimeline: preservesTimeline)
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

    /// Transcribes and, when the engine supports it, returns word-level timings
    /// alongside the text. Engines without timing support fall back to the
    /// default implementation, which wraps `transcribe` with `words == nil`.
    func transcribeDetailed(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext)
        async throws -> DetailedTranscriptionResult
}

extension TranscriptionService {
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let context = TranscriptionRequestContext.currentDefaults.scoped(to: model)
        return try await transcribe(audioURL: audioURL, model: model, context: context)
    }

    func transcribeDetailed(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext)
        async throws -> DetailedTranscriptionResult
    {
        let text = try await transcribe(audioURL: audioURL, model: model, context: context)
        return DetailedTranscriptionResult(text: text, words: nil)
    }
}

import Foundation
import LLMkit

/// Adapts LLMkit's Soniox stream to VoiceInk's recording and fallback lifecycle.
final class SonioxStreamingProvider: StreamingTranscriptionProvider {
    private let client = LLMkit.SonioxStreamingClient()
    private let vocabulary: [String]
    private let events: AsyncStream<StreamingTranscriptionEvent>.Continuation
    private let finalization: AsyncStream<String>.Continuation
    private var forwardingTask: Task<Void, Never>?

    let transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>
    let finalizationEvents: AsyncStream<String>?

    var stopDisposition: StreamingStopDisposition {
        client.requiresFullRecording ? .useBatchFallback : .finalizeStreaming
    }

    init(customVocabulary: [String]) {
        vocabulary = customVocabulary
        let events = AsyncStream.makeStream(of: StreamingTranscriptionEvent.self)
        transcriptionEvents = events.stream
        self.events = events.continuation
        let finalization = AsyncStream.makeStream(of: String.self)
        finalizationEvents = finalization.stream
        self.finalization = finalization.continuation
    }

    deinit {
        forwardingTask?.cancel()
        events.finish()
        finalization.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        guard let key = APIKeyManager.shared.getAPIKey(forProvider: "Soniox"), !key.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }
        forwardingTask?.cancel()
        let source = client.transcriptionEvents
        let events = events
        forwardingTask = Task {
            for await event in source {
                switch event {
                case .sessionStarted: events.yield(.sessionStarted)
                case .partial(let text): events.yield(.partial(text: text))
                case .committed(let text): events.yield(.committed(text: text))
                case .error(let message): events.yield(.error(StreamingTranscriptionError.serverError(message)))
                }
            }
        }
        do {
            try await client.connect(apiKey: key, model: "stt-rt-v6", language: language, customVocabulary: vocabulary)
        } catch {
            forwardingTask?.cancel()
            forwardingTask = nil
            await client.disconnect()
            throw error
        }
    }

    func sendAudioChunk(_ data: Data) async throws { try await client.sendAudioChunk(data) }

    func commit() async throws {
        let text = try await client.finalize()
        finalization.yield(text)
        finalization.finish()
    }

    func disconnect() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        await client.disconnect()
        events.finish()
        finalization.finish()
    }
}

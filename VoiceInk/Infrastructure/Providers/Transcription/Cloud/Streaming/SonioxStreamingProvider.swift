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
            throw mapError(error)
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        do {
            try await client.sendAudioChunk(data)
        } catch {
            throw mapError(error)
        }
    }

    func commit() async throws {
        do {
            let text = try await client.finalize()
            finalization.yield(text)
            finalization.finish()
        } catch {
            throw mapError(error)
        }
    }

    func disconnect() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        await client.disconnect()
        events.finish()
        finalization.finish()
    }

    private func mapError(_ error: Error) -> Error {
        if let streamingError = error as? SonioxStreamingError {
            switch streamingError {
            case .connection(let message):
                return StreamingTranscriptionError.connectionFailed(message)
            case .timeout:
                return StreamingTranscriptionError.timeout
            case .server, .bufferOverflow, .incompleteStream:
                return StreamingTranscriptionError.serverError(streamingError.localizedDescription)
            }
        }
        if let llmError = error as? LLMKitError {
            switch llmError {
            case .missingAPIKey:
                return StreamingTranscriptionError.missingAPIKey
            case .httpError(_, let message):
                return StreamingTranscriptionError.serverError(message)
            case .networkError(let detail):
                return StreamingTranscriptionError.connectionFailed(detail)
            default:
                return StreamingTranscriptionError.serverError(llmError.localizedDescription)
            }
        }
        if let urlError = error as? URLError, urlError.code != .cancelled {
            return StreamingTranscriptionError.connectionFailed(urlError.localizedDescription)
        }
        return error
    }
}

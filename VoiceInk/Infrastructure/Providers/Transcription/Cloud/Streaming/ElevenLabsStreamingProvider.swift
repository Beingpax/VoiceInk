import Foundation
import LLMkit

/// ElevenLabs streaming provider wrapping `LLMkit.ElevenLabsStreamingClient`.
final class ElevenLabsStreamingProvider: StreamingTranscriptionProvider {

    private let client = LLMkit.ElevenLabsStreamingClient()
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var forwardingTask: Task<Void, Never>?
    private let customVocabulary: [String]
    private let finalizationContinuation: AsyncStream<String>.Continuation
    let finalizationEvents: AsyncStream<String>?

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init(customVocabulary: [String]) {
        self.customVocabulary = customVocabulary
        let finalization = AsyncStream.makeStream(of: String.self)
        finalizationEvents = finalization.stream
        finalizationContinuation = finalization.continuation
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        forwardingTask?.cancel()
        eventsContinuation?.finish()
        finalizationContinuation.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        guard let streamingModel = ElevenLabsProvider.ScribeModel(rawValue: model.name)?.streamingID else {
            throw CloudTranscriptionError.unsupportedModel(model.name)
        }

        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "ElevenLabs"), !apiKey.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        // Cancel any existing forwarding task before starting a new one
        forwardingTask?.cancel()
        startEventForwarding()

        do {
            try await client.connect(
                apiKey: apiKey,
                model: streamingModel,
                language: language,
                customVocabulary: customVocabulary
            )
        } catch {
            // Clean up forwarding task on connection failure
            forwardingTask?.cancel()
            forwardingTask = nil
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
            finalizationContinuation.yield(text)
            finalizationContinuation.finish()
        } catch {
            throw mapError(error)
        }
    }

    func disconnect() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        await client.disconnect()
        eventsContinuation?.finish()
        finalizationContinuation.finish()
    }

    // MARK: - Private

    private func startEventForwarding() {
        forwardingTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.client.transcriptionEvents {
                switch event {
                case .sessionStarted:
                    self.eventsContinuation?.yield(.sessionStarted)
                case .partial(let text):
                    self.eventsContinuation?.yield(.partial(text: text))
                case .committed(let text):
                    self.eventsContinuation?.yield(.committed(text: text))
                case .error(let message):
                    self.eventsContinuation?.yield(.error(StreamingTranscriptionError.serverError(message)))
                }
            }
        }
    }

    private func mapError(_ error: Error) -> Error {
        if let streamingError = error as? ElevenLabsStreamingError { return streamingError }
        guard let llmError = error as? LLMKitError else { return error }
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
}

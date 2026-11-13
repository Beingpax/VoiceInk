import Foundation
import LLMkit

/// Zoom Scribe Live streaming provider wrapping `LLMkit.ZoomScribeStreamingClient`.
final class ZoomScribeStreamingProvider: StreamingTranscriptionProvider {

    private let customVocabulary: [String]
    var finalizationEvents: AsyncStream<String>? { client.finalizationEvents }

    /// Replaced in `connect` once the model and language are known, so polishing matches the request.
    private var client = ZoomScribeStreamingClient(
        trackingIdPrefix: ZoomScribeProvider.trackingIdPrefix,
        textPolishing: false
    )
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var forwardingTask: Task<Void, Never>?

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init(customVocabulary: [String]) {
        self.customVocabulary = customVocabulary
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        forwardingTask?.cancel()
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "Zoom Scribe"), !apiKey.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        // Cancel any existing forwarding task before starting a new one
        forwardingTask?.cancel()
        client = ZoomScribeStreamingClient(
            trackingIdPrefix: ZoomScribeProvider.trackingIdPrefix,
            textPolishing: ZoomScribeProvider.effectiveTextPolishing(model: model.name, language: language)
        )
        startEventForwarding()

        do {
            try await client.connect(
                apiKey: apiKey, model: model.name, language: language,
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
            try await client.commit()
        } catch {
            throw mapError(error)
        }
    }

    func disconnect() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        await client.disconnect()
        eventsContinuation?.finish()
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
        guard let llmError = error as? LLMKitError else { return error }
        switch llmError {
        case .missingAPIKey:
            return StreamingTranscriptionError.missingAPIKey
        case .httpError(_, let message):
            return StreamingTranscriptionError.serverError(message)
        case .networkError(let detail):
            return StreamingTranscriptionError.connectionFailed(detail)
        case .timeout:
            return StreamingTranscriptionError.timeout
        default:
            return StreamingTranscriptionError.serverError(llmError.localizedDescription)
        }
    }
}

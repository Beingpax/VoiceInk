import Foundation
import LLMkit
import SwiftData

/// Cartesia Ink 2 streaming provider wrapping `LLMkit.CartesiaStreamingClient`.
final class CartesiaStreamingProvider: StreamingTranscriptionProvider {

    private let client = LLMkit.CartesiaStreamingClient()
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var forwardingTask: Task<Void, Never>?
    private let finalizationLock = NSLock()
    private var didRequestFinalization = false
    private let modelContext: ModelContext

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        forwardingTask?.cancel()
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language _: String?) async throws {
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "Cartesia"), !apiKey.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        forwardingTask?.cancel()
        setFinalizationRequested(false)
        startEventForwarding()

        do {
            try await client.connect(apiKey: apiKey, model: model.name, language: nil, customVocabulary: [])
        } catch {
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
        setFinalizationRequested(true)
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
            defer {
                if self.isFinalizationRequested {
                    self.eventsContinuation?.yield(.committed(text: ""))
                }
                self.eventsContinuation?.finish()
            }
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

    private var isFinalizationRequested: Bool {
        finalizationLock.lock()
        defer { finalizationLock.unlock() }
        return didRequestFinalization
    }

    private func setFinalizationRequested(_ value: Bool) {
        finalizationLock.lock()
        didRequestFinalization = value
        finalizationLock.unlock()
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
        default:
            return StreamingTranscriptionError.serverError(llmError.localizedDescription ?? "Unknown error")
        }
    }
}

import Foundation
import SwiftData

/// Soniox streaming provider wrapping `SonioxLocalStreamingClient`.
///
/// Uses the local client (instead of `LLMkit.SonioxStreamingClient`) so we can pass an array
/// of language hints — Soniox's `language_hints` is a list, but LLMkit only accepts a single code.
final class SonioxStreamingProvider: StreamingTranscriptionProvider {

    private let client = SonioxLocalStreamingClient()
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var forwardingTask: Task<Void, Never>?
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

    func connect(model: any TranscriptionModel, language: String?) async throws {
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "Soniox"), !apiKey.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        let vocabulary = getCustomDictionaryTerms()
        let hints = SelectedLanguagesStore.languageHints()

        forwardingTask?.cancel()
        startEventForwarding()

        do {
            try await client.connect(apiKey: apiKey, model: "stt-rt-v4", languageHints: hints, customVocabulary: vocabulary)
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

    private func getCustomDictionaryTerms() -> [String] {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])
        guard let vocabularyWords = try? modelContext.fetch(descriptor) else {
            return []
        }
        var seen = Set<String>()
        var unique: [String] = []
        for word in vocabularyWords {
            let trimmed = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(trimmed)
            }
        }
        return unique
    }

    private func mapError(_ error: Error) -> Error {
        if let local = error as? SonioxLocalError {
            switch local {
            case .missingAPIKey:
                return StreamingTranscriptionError.missingAPIKey
            case .httpError(_, let message), .serverError(let message):
                return StreamingTranscriptionError.serverError(message)
            case .timeout:
                return StreamingTranscriptionError.timeout
            default:
                return StreamingTranscriptionError.serverError(local.errorDescription ?? "Unknown error")
            }
        }
        return error
    }
}

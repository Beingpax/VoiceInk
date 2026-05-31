import Foundation
import LLMkit
import os

/// ElevenLabs streaming provider wrapping `LLMkit.ElevenLabsStreamingClient`.
///
/// Supports multiple API keys with automatic rotation on key-level failures
/// (auth_error, quota_exceeded, rate_limited, HTTP 401/403/429). Rotation
/// happens at connect time; mid-session quota errors surface as
/// `.keyQuotaExceeded` so the UI can inform the user and the next session
/// will pick up the next enabled key.
final class ElevenLabsStreamingProvider: StreamingTranscriptionProvider {

    private static let providerKey = "ElevenLabs"
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "ElevenLabsStreamingProvider"
    )

    private var client = LLMkit.ElevenLabsStreamingClient()
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var forwardingTask: Task<Void, Never>?

    /// The key id currently in use for the live connection.
    private var activeKeyId: UUID?
    private var activeKeyLabel: String?

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init() {
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        forwardingTask?.cancel()
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        let keys = APIKeyManager.shared.getAPIKeys(forProvider: Self.providerKey)
        let enabledKeys = keys.filter { !$0.disabled && !$0.key.isEmpty }

        guard !enabledKeys.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        guard let firstActive = APIKeyManager.shared.activeAPIKey(forProvider: Self.providerKey) else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        // Build ordered attempt list starting from the active key.
        var attemptOrder: [APIKeyEntry] = []
        var seenIds = Set<UUID>()
        attemptOrder.append(firstActive)
        seenIds.insert(firstActive.id)
        for key in enabledKeys where !seenIds.contains(key.id) {
            attemptOrder.append(key)
            seenIds.insert(key.id)
        }

        var lastReason = "unknown"
        for (attemptIndex, entry) in attemptOrder.enumerated() {
            forwardingTask?.cancel()
            await client.disconnect()
            client = LLMkit.ElevenLabsStreamingClient()

            activeKeyId = entry.id
            activeKeyLabel = entry.label
            startEventForwarding(forKeyId: entry.id, keyLabel: entry.label)

            do {
                try await client.connect(
                    apiKey: entry.key,
                    model: "scribe_v2_realtime",
                    language: language
                )
                APIKeyManager.shared.setActiveKey(id: entry.id, forProvider: Self.providerKey)
                APIKeyManager.shared.updateAPIKey(
                    id: entry.id,
                    clearFailure: true,
                    forProvider: Self.providerKey
                )
                if attemptIndex > 0 {
                    Self.logger.notice(
                        "Rotated to key \(entry.label, privacy: .public) after \(attemptIndex, privacy: .public) failed attempt(s)"
                    )
                }
                return
            } catch {
                let mapped = mapConnectError(error)
                lastReason = mapped.reason

                forwardingTask?.cancel()
                forwardingTask = nil

                switch mapped.classification {
                case .keyLevel(let reason):
                    Self.logger.warning(
                        "Key \(entry.label, privacy: .public) failed with key-level error: \(reason, privacy: .public). Trying next key."
                    )
                    APIKeyManager.shared.markKeyFailed(
                        id: entry.id,
                        reason: reason,
                        forProvider: Self.providerKey
                    )
                    continue

                case .transient(let reason):
                    Self.logger.error(
                        "Key \(entry.label, privacy: .public) hit a transient failure: \(reason, privacy: .public). Not rotating."
                    )
                    activeKeyId = nil
                    activeKeyLabel = nil
                    throw mapped.surfaceError
                }
            }
        }

        activeKeyId = nil
        activeKeyLabel = nil
        throw StreamingTranscriptionError.allKeysExhausted(lastReason: lastReason)
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
        activeKeyId = nil
        activeKeyLabel = nil
    }

    // MARK: - Private

    private func startEventForwarding(forKeyId keyId: UUID, keyLabel: String) {
        let client = self.client
        let continuation = self.eventsContinuation
        forwardingTask = Task {
            for await event in client.transcriptionEvents {
                switch event {
                case .sessionStarted:
                    continuation?.yield(.sessionStarted)
                case .partial(let text):
                    continuation?.yield(.partial(text: text))
                case .committed(let text):
                    continuation?.yield(.committed(text: text))
                case .error(let message):
                    let classification = APIKeyFailureClass.classifyElevenLabsWSError(message)
                    switch classification {
                    case .keyLevel(let reason):
                        APIKeyManager.shared.markKeyFailed(
                            id: keyId,
                            reason: reason,
                            forProvider: Self.providerKey
                        )
                        _ = APIKeyManager.shared.rotateToNextKey(
                            forProvider: Self.providerKey,
                            reason: reason
                        )
                        continuation?.yield(
                            .error(StreamingTranscriptionError.keyQuotaExceeded(
                                keyLabel: keyLabel,
                                reason: reason
                            ))
                        )
                    case .transient(let reason):
                        continuation?.yield(
                            .error(StreamingTranscriptionError.serverError(reason))
                        )
                    }
                }
            }
        }
    }

    private func mapConnectError(_ error: Error) -> (
        classification: APIKeyFailureClass,
        surfaceError: Error,
        reason: String
    ) {
        if let llmError = error as? LLMKitError {
            switch llmError {
            case .missingAPIKey:
                let reason = "missing API key"
                return (.keyLevel(reason: reason), StreamingTranscriptionError.missingAPIKey, reason)
            case .httpError(let statusCode, let message):
                let classification = APIKeyFailureClass.classifyHTTP(statusCode: statusCode, message: message)
                let surface = StreamingTranscriptionError.serverError("HTTP \(statusCode): \(message)")
                return (classification, surface, "HTTP \(statusCode): \(message)")
            case .networkError(let detail):
                return (
                    .transient(reason: detail),
                    StreamingTranscriptionError.connectionFailed(detail),
                    detail
                )
            case .timeout:
                return (
                    .transient(reason: "timeout"),
                    StreamingTranscriptionError.timeout,
                    "timeout"
                )
            default:
                let msg = llmError.errorDescription ?? "Unknown error"
                return (
                    .transient(reason: msg),
                    StreamingTranscriptionError.serverError(msg),
                    msg
                )
            }
        }
        let reason = error.localizedDescription
        return (
            .transient(reason: reason),
            StreamingTranscriptionError.connectionFailed(reason),
            reason
        )
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
            return StreamingTranscriptionError.serverError(llmError.errorDescription ?? "Unknown error")
        }
    }
}

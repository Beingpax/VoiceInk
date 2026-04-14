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

    /// The key id currently in use for the live connection, so mid-session
    /// failures can be reported with the correct label and future sessions
    /// rotate past it automatically.
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

        // Determine the starting key (the currently active one if it's still
        // enabled, otherwise the first enabled one).
        guard let firstActive = APIKeyManager.shared.activeAPIKey(forProvider: Self.providerKey) else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        // Build an ordered attempt list starting from the active key, without
        // duplicates, bounded to the enabled key count so we never infinite-loop.
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
            // Cancel any existing forwarding task before starting a new one.
            forwardingTask?.cancel()
            // Ensure the client is fresh for each attempt (the previous attempt
            // may have partially connected before failing).
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
                // Connect succeeded — make sure this key is the persisted active
                // one (in case we advanced past earlier failing keys).
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

                // Always tear down the forwarding task on a failed attempt so we
                // don't leak event streams from a partial connection.
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
                    // Continue to the next key in the attempt order.
                    continue

                case .transient(let reason):
                    // Don't burn through other keys for a network blip — fail fast.
                    Self.logger.error(
                        "Key \(entry.label, privacy: .public) hit a transient failure: \(reason, privacy: .public). Not rotating."
                    )
                    activeKeyId = nil
                    activeKeyLabel = nil
                    throw mapped.surfaceError
                }
            }
        }

        // Exhausted the attempt list with key-level failures on every key.
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
        // Capture the client reference locally so the task doesn't read mutable
        // `self.client` from a non-isolated context. `keyId` and `keyLabel` are
        // captured by value so mid-session rotation logic uses the correct key.
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
                    // Distinguish key-level from transient errors even in
                    // mid-session messages so higher layers can show the right
                    // error and future sessions rotate.
                    let classification = APIKeyFailureClass.classifyElevenLabsWSError(message)
                    switch classification {
                    case .keyLevel(let reason):
                        APIKeyManager.shared.markKeyFailed(
                            id: keyId,
                            reason: reason,
                            forProvider: Self.providerKey
                        )
                        // Advance the active index so the next session
                        // automatically rotates to the next enabled key.
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

    /// Classifies a connect-time error and returns both the classification and
    /// the error to surface if we stop retrying.
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
        // Non-LLMkit errors are treated as transient (connection-level) so we
        // don't rotate keys when e.g. the user has no internet.
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

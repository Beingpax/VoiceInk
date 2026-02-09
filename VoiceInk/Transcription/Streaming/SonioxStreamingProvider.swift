import Foundation
import SwiftData
import os

/// Soniox stt-rt-v4 realtime streaming provider using WebSocket.
final class SonioxStreamingProvider: StreamingTranscriptionProvider {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SonioxStreaming")
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private let modelContext: ModelContext

    /// Accumulated final tokens for committed transcription.
    private var finalText = ""

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "Soniox"), !apiKey.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        let urlString = "wss://stt-rt.soniox.com/transcribe-websocket"
        guard let url = URL(string: urlString) else {
            throw StreamingTranscriptionError.connectionFailed("Invalid WebSocket URL")
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)

        self.urlSession = session
        self.webSocketTask = task

        task.resume()

        logger.notice("WebSocket connecting to \(url.absoluteString)")

        // Send initial configuration message
        try await sendConfiguration(apiKey: apiKey, model: model, language: language)

        logger.notice("Sent configuration, starting receive loop")
        eventsContinuation?.yield(.sessionStarted)

        // Start the background receive loop
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let task = webSocketTask else {
            throw StreamingTranscriptionError.notConnected
        }

        // Soniox expects raw binary audio frames, not base64-encoded JSON
        try await task.send(.data(data))
    }

    func commit() async throws {
        guard let task = webSocketTask else {
            throw StreamingTranscriptionError.notConnected
        }

        // Send manual finalization message to finalize all pending audio
        let finalizeMessage: [String: Any] = ["type": "finalize"]
        let jsonData = try JSONSerialization.data(withJSONObject: finalizeMessage)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        logger.notice("Sending finalize message (commit)")
        try await task.send(.string(jsonString))
    }

    func disconnect() async {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        eventsContinuation?.finish()
        finalText = ""
        logger.notice("WebSocket disconnected")
    }

    // MARK: - Private

    private func sendConfiguration(apiKey: String, model: any TranscriptionModel, language: String?) async throws {
        guard let task = webSocketTask else {
            throw StreamingTranscriptionError.notConnected
        }

        var config: [String: Any] = [
            "api_key": apiKey,
            "model": model.name,
            "audio_format": "pcm_s16le",
            "sample_rate": 16000,
            "num_channels": 1
        ]

        let selectedLanguage = language ?? UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        if selectedLanguage != "auto" && !selectedLanguage.isEmpty {
            config["language_hints"] = [selectedLanguage]
            config["language_hints_strict"] = true
            config["enable_language_identification"] = true
        } else {
            config["enable_language_identification"] = true
        }

        // Add custom vocabulary context
        let dictionaryTerms = getCustomDictionaryTerms()
        if !dictionaryTerms.isEmpty {
            config["context"] = [
                "terms": dictionaryTerms
            ]
            logger.debug("Added \(dictionaryTerms.count) vocabulary terms to context")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: config)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        try await task.send(.string(jsonString))
        logger.notice("Sent configuration with model \(model.name)")
    }

    private func getCustomDictionaryTerms() -> [String] {
        // Fetch vocabulary words from SwiftData
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])
        guard let vocabularyWords = try? modelContext.fetch(descriptor) else {
            return []
        }

        let words = vocabularyWords
            .map { $0.word.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // De-duplicate while preserving order
        var seen = Set<String>()
        var unique: [String] = []
        for w in words {
            let key = w.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(w)
            }
        }
        return unique
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    logger.error("WebSocket receive error: \(error.localizedDescription)")
                    eventsContinuation?.yield(.error(error))
                }
                break
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("Received unparseable message")
            return
        }

        // Check for error
        if let errorCode = json["error_code"] as? Int {
            let errorMsg = json["error_message"] as? String ?? "Unknown error (code \(errorCode))"
            logger.error("Server error: \(errorMsg)")
            eventsContinuation?.yield(.error(StreamingTranscriptionError.serverError(errorMsg)))
            return
        }

        // Check for finished signal
        if let finished = json["finished"] as? Bool, finished {
            logger.notice("Received finished signal - session complete")
            // Yield any remaining accumulated final text
            if !finalText.isEmpty {
                eventsContinuation?.yield(.committed(text: finalText))
                finalText = ""
            } else {
                // Yield empty committed event to signal completion
                eventsContinuation?.yield(.committed(text: ""))
            }
            return
        }

        // Parse tokens
        guard let tokens = json["tokens"] as? [[String: Any]] else {
            logger.debug("Received message without tokens array")
            return
        }

        // Process tokens if array is not empty
        if !tokens.isEmpty {
            processTokens(tokens)
        }
    }

    private func processTokens(_ tokens: [[String: Any]]) {
        var newFinalText = ""
        var newPartialText = ""
        var sawFinMarker = false

        // First pass: process ALL tokens in this batch
        for token in tokens {
            guard let text = token["text"] as? String else { continue }

            // Check for the special <fin> marker token
            if text == "<fin>" {
                logger.debug("Received <fin> marker in token batch")
                sawFinMarker = true
                continue
            }

            let isFinal = token["is_final"] as? Bool ?? false

            if isFinal {
                newFinalText += text
            } else {
                newPartialText += text
            }
        }

        // Accumulate final text from this batch
        if !newFinalText.isEmpty {
            finalText += newFinalText
        }

        // If we saw <fin> marker, yield ALL accumulated final text (including tokens from this batch)
        if sawFinMarker {
            eventsContinuation?.yield(.committed(text: finalText))
            finalText = ""
        } else if !newPartialText.isEmpty {
            // Show live partial: final text so far + current non-final tokens
            let currentPartial = finalText + newPartialText
            eventsContinuation?.yield(.partial(text: currentPartial))
        }
    }
}

import Foundation
import SwiftData
import os

/// Deepgram Nova-3 streaming provider using WebSocket
final class DeepgramStreamingProvider: StreamingTranscriptionProvider {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DeepgramStreaming")
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private let modelContext: ModelContext
    private var accumulatedFinalText = ""

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        keepaliveTask?.cancel()
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "Deepgram"), !apiKey.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "model", value: model.name),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "numerals", value: "true"),
            URLQueryItem(name: "interim_results", value: "true")
        ]

        if let language = language, language != "auto", !language.isEmpty {
            queryItems.append(URLQueryItem(name: "language", value: language))
        }

        // Add custom vocabulary as keyterm parameters
        let vocabularyTerms = getCustomVocabularyTerms()
        for term in vocabularyTerms {
            queryItems.append(URLQueryItem(name: "keyterm", value: term))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw StreamingTranscriptionError.connectionFailed("Invalid WebSocket URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)

        self.urlSession = session
        self.webSocketTask = task

        task.resume()

        logger.notice("WebSocket connecting to \(url.absoluteString)")

        eventsContinuation?.yield(.sessionStarted)
        logger.notice("Streaming session started")

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        keepaliveTask = Task { [weak self] in
            await self?.keepaliveLoop()
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let task = webSocketTask else {
            throw StreamingTranscriptionError.notConnected
        }

        try await task.send(.data(data))
    }

    func commit() async throws {
        guard let task = webSocketTask else {
            throw StreamingTranscriptionError.notConnected
        }

        let finalizeMessage: [String: Any] = ["type": "Finalize"]
        let jsonData = try JSONSerialization.data(withJSONObject: finalizeMessage)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        try await task.send(.string(jsonString))
    }

    func disconnect() async {
        keepaliveTask?.cancel()
        keepaliveTask = nil

        if let task = webSocketTask {
            do {
                let closeMessage: [String: Any] = ["type": "CloseStream"]
                let jsonData = try JSONSerialization.data(withJSONObject: closeMessage)
                let jsonString = String(data: jsonData, encoding: .utf8)!
                try await task.send(.string(jsonString))
            } catch {
                // Ignore errors during disconnect
            }
        }

        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        eventsContinuation?.finish()
        accumulatedFinalText = ""
        logger.notice("WebSocket disconnected")
    }

    // MARK: - Private

    private func keepaliveLoop() async {
        do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }

        while !Task.isCancelled {
            guard let task = webSocketTask else { break }

            do {
                let keepaliveMessage: [String: Any] = ["type": "KeepAlive"]
                let jsonData = try JSONSerialization.data(withJSONObject: keepaliveMessage)
                let jsonString = String(data: jsonData, encoding: .utf8)!

                try await task.send(.string(jsonString))
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                if !Task.isCancelled {
                    logger.warning("Keepalive error: \(error.localizedDescription)")
                }
                break
            }
        }
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
            logger.warning("Failed to parse JSON message")
            return
        }

        // Skip control messages
        if let type = json["type"] as? String {
            if type == "Metadata" || type == "SpeechStarted" || type == "UtteranceEnd" {
                return
            }
        }

        if let error = json["error"] as? String {
            logger.error("Deepgram error: \(error)")
            eventsContinuation?.yield(.error(StreamingTranscriptionError.serverError(error)))
            return
        }

        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              !alternatives.isEmpty,
              let firstAlternative = alternatives.first,
              let transcript = firstAlternative["transcript"] as? String else {
            return
        }

        let isFinal = json["is_final"] as? Bool ?? false
        let speechFinal = json["speech_final"] as? Bool ?? false

        if isFinal || speechFinal {
            if !transcript.isEmpty {
                if !accumulatedFinalText.isEmpty {
                    accumulatedFinalText += " "
                }
                accumulatedFinalText += transcript
                eventsContinuation?.yield(.committed(text: transcript))
            } else {
                eventsContinuation?.yield(.committed(text: ""))
            }
        } else {
            // Show accumulated finals + current partial
            if !transcript.isEmpty {
                let fullPartial: String
                if !accumulatedFinalText.isEmpty {
                    fullPartial = accumulatedFinalText + " " + transcript
                } else {
                    fullPartial = transcript
                }
                eventsContinuation?.yield(.partial(text: fullPartial))
            }
        }
    }

    private func getCustomVocabularyTerms() -> [String] {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])
        guard let vocabularyWords = try? modelContext.fetch(descriptor) else {
            return []
        }

        let words = vocabularyWords
            .map { $0.word.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Deduplicate
        var seen = Set<String>()
        var unique: [String] = []
        for w in words {
            let key = w.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(w)
            }
        }

        // Limit to 50 terms
        return Array(unique.prefix(50))
    }
}

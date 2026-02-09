import Foundation
import os

/// Mistral Voxtral Realtime streaming provider using WebSocket.
final class MistralStreamingProvider: StreamingTranscriptionProvider {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MistralStreaming")
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?

    /// Accumulated text from transcription.text.delta events.
    private var accumulatedText = ""

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init() {
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
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "Mistral"), !apiKey.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        var components = URLComponents(string: "wss://api.mistral.ai/v1/audio/transcriptions/realtime")!
        components.queryItems = [
            URLQueryItem(name: "model", value: "voxtral-mini-transcribe-realtime-2602")
        ]

        guard let url = components.url else {
            throw StreamingTranscriptionError.connectionFailed("Invalid WebSocket URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)

        self.urlSession = session
        self.webSocketTask = task

        task.resume()

        logger.notice("WebSocket connecting to \(url.absoluteString)")

        // Wait for the session.created message to confirm connection
        let message = try await task.receive()
        switch message {
        case .string(let text):
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                if type == "session.created" {
                    logger.notice("Streaming session created")
                    eventsContinuation?.yield(.sessionStarted)
                } else if type == "error" {
                    let errorMsg = extractErrorMessage(from: json)
                    throw StreamingTranscriptionError.serverError(errorMsg)
                }
            }
        case .data:
            break
        @unknown default:
            break
        }

        // Send session.update with audio format configuration
        try await sendSessionUpdate()

        // Start the background receive loop
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let task = webSocketTask else {
            throw StreamingTranscriptionError.notConnected
        }

        let base64Audio = data.base64EncodedString()

        let message: [String: Any] = [
            "type": "input_audio.append",
            "audio": base64Audio
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        try await task.send(.string(jsonString))
    }

    func commit() async throws {
        guard let task = webSocketTask else {
            throw StreamingTranscriptionError.notConnected
        }

        let message: [String: Any] = [
            "type": "input_audio.end"
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        logger.notice("Sending input_audio.end (commit)")
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
        accumulatedText = ""
        logger.notice("WebSocket disconnected")
    }

    // MARK: - Private

    private func sendSessionUpdate() async throws {
        guard let task = webSocketTask else { return }

        let message: [String: Any] = [
            "type": "session.update",
            "session": [
                "audio_format": [
                    "encoding": "pcm_s16le",
                    "sample_rate": 16000
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        try await task.send(.string(jsonString))
        logger.notice("Sent session.update with audio format config")
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            logger.warning("Received unparseable message")
            return
        }

        switch type {
        case "transcription.text.delta":
            if let deltaText = json["text"] as? String {
                accumulatedText += deltaText
                eventsContinuation?.yield(.partial(text: accumulatedText))
            }

        case "transcription.done":
            let finalText = accumulatedText
            eventsContinuation?.yield(.committed(text: finalText))
            accumulatedText = ""

        case "transcription.segment":
            // Segment events may contain finalized segment text
            if let segmentText = json["text"] as? String {
            }

        case "transcription.language":
            if let language = json["language"] as? String {
                logger.notice("Detected language: \(language)")
            }

        case "session.updated":
            logger.notice("Session updated acknowledged")

        case "error":
            let errorMsg = extractErrorMessage(from: json)
            logger.error("Server error: \(errorMsg)")
            eventsContinuation?.yield(.error(StreamingTranscriptionError.serverError(errorMsg)))

        default:
            logger.debug("Unhandled message type: \(type)")
        }
    }

    private func extractErrorMessage(from json: [String: Any]) -> String {
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String {
                return message
            }
            if let detail = error["detail"] as? String {
                return detail
            }
        }
        if let error = json["error"] as? String {
            return error
        }
        if let message = json["message"] as? String {
            return message
        }
        return "Unknown error"
    }
}

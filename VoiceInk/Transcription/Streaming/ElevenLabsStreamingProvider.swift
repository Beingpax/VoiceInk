import Foundation
import os

/// ElevenLabs Scribe V2 Real-Time streaming provider using WebSocket.
final class ElevenLabsStreamingProvider: StreamingTranscriptionProvider {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ElevenLabsStreaming")
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?

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
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "ElevenLabs"), !apiKey.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        // Build the WebSocket URL with query parameters
        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: "vad"),
        ]

        if let language = language, language != "auto", !language.isEmpty {
            queryItems.append(URLQueryItem(name: "language_code", value: language))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw StreamingTranscriptionError.connectionFailed("Invalid WebSocket URL")
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)

        self.urlSession = session
        self.webSocketTask = task

        task.resume()

        logger.notice("WebSocket connecting to \(url.absoluteString)")

        // Wait for the session_started message to confirm connection
        let message = try await task.receive()
        switch message {
        case .string(let text):
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let messageType = json["message_type"] as? String {
                if messageType == "session_started" {
                    logger.notice("Streaming session started")
                    eventsContinuation?.yield(.sessionStarted)
                } else if messageType == "error" || messageType == "auth_error" {
                    let errorMsg = json["message"] as? String ?? "Unknown error"
                    throw StreamingTranscriptionError.serverError(errorMsg)
                }
            }
        case .data:
            break
        @unknown default:
            break
        }

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
            "message_type": "input_audio_chunk",
            "audio_base_64": base64Audio,
            "commit": false,
            "sample_rate": 16000
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
            "message_type": "input_audio_chunk",
            "audio_base_64": "",
            "commit": true,
            "sample_rate": 16000
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        logger.notice("Sending commit message")
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
        logger.notice("WebSocket disconnected")
    }

    // MARK: - Private

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
              let messageType = json["message_type"] as? String else {
            logger.warning("Received unparseable message")
            return
        }

        switch messageType {
        case "partial_transcript":
            if let transcript = json["text"] as? String {
                eventsContinuation?.yield(.partial(text: transcript))
            }

        case "committed_transcript", "committed_transcript_with_timestamps":
            if let transcript = json["text"] as? String {
                eventsContinuation?.yield(.committed(text: transcript))
            }

        case "error", "auth_error", "quota_exceeded", "rate_limited",
             "resource_exhausted", "session_time_limit_exceeded",
             "input_error", "chunk_size_exceeded", "transcriber_error":
            let errorMsg = json["message"] as? String ?? messageType
            logger.error("Server error: \(messageType) - \(errorMsg)")
            eventsContinuation?.yield(.error(StreamingTranscriptionError.serverError(errorMsg)))

        default:
            logger.debug("Unhandled message type: \(messageType)")
        }
    }
}

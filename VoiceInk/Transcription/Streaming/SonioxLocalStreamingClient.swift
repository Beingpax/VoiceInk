import Foundation

/// Self-hosted Soniox `stt-rt-v4` streaming client.
///
/// Mirrors `LLMkit.SonioxStreamingClient` so we can pass an array of `language_hints`,
/// which the LLMkit version doesn't expose.
final class SonioxLocalStreamingClient: @unchecked Sendable {

    enum Event {
        case sessionStarted
        case partial(text: String)
        case committed(text: String)
        case error(String)
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var eventsContinuation: AsyncStream<Event>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private var finalText = ""

    private(set) var transcriptionEvents: AsyncStream<Event>

    init() {
        var continuation: AsyncStream<Event>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()
        eventsContinuation?.finish()
    }

    func connect(apiKey: String, model: String, languageHints: [String], customVocabulary: [String] = []) async throws {
        let urlString = "wss://stt-rt.soniox.com/transcribe-websocket"
        guard let url = URL(string: urlString) else {
            throw SonioxLocalError.invalidURL
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)

        self.urlSession = session
        self.webSocketTask = task
        task.resume()

        try await sendConfiguration(apiKey: apiKey, model: model, languageHints: languageHints, customVocabulary: customVocabulary)

        eventsContinuation?.yield(.sessionStarted)

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let task = webSocketTask else {
            throw SonioxLocalError.serverError("Not connected to Soniox streaming.")
        }
        try await task.send(.data(data))
    }

    func commit() async throws {
        guard let task = webSocketTask else {
            throw SonioxLocalError.serverError("Not connected to Soniox streaming.")
        }
        let payload: [String: Any] = ["type": "finalize"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = String(data: data, encoding: .utf8)!
        try await task.send(.string(json))
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
    }

    // MARK: - Private

    private func sendConfiguration(apiKey: String, model: String, languageHints: [String], customVocabulary: [String]) async throws {
        guard let task = webSocketTask else {
            throw SonioxLocalError.serverError("Not connected to Soniox streaming.")
        }

        var config: [String: Any] = [
            "api_key": apiKey,
            "model": model,
            "audio_format": "pcm_s16le",
            "sample_rate": 16000,
            "num_channels": 1,
            "enable_language_identification": true
        ]

        if !languageHints.isEmpty {
            config["language_hints"] = languageHints
            config["language_hints_strict"] = true
        }

        if !customVocabulary.isEmpty {
            config["context"] = ["terms": customVocabulary]
        }

        let data = try JSONSerialization.data(withJSONObject: config)
        let json = String(data: data, encoding: .utf8)!
        try await task.send(.string(json))
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
                    eventsContinuation?.yield(.error(error.localizedDescription))
                }
                break
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let errorCode = json["error_code"] as? Int {
            let errorMsg = json["error_message"] as? String ?? "Unknown error (code \(errorCode))"
            eventsContinuation?.yield(.error(errorMsg))
            return
        }

        if let finished = json["finished"] as? Bool, finished {
            eventsContinuation?.yield(.committed(text: finalText))
            finalText = ""
            return
        }

        guard let tokens = json["tokens"] as? [[String: Any]], !tokens.isEmpty else { return }
        processTokens(tokens)
    }

    private func processTokens(_ tokens: [[String: Any]]) {
        var newFinalText = ""
        var newPartialText = ""
        var sawFinMarker = false

        for token in tokens {
            guard let text = token["text"] as? String else { continue }
            if text == "<fin>" {
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

        if !newFinalText.isEmpty {
            finalText += newFinalText
        }

        if sawFinMarker {
            eventsContinuation?.yield(.committed(text: finalText))
            finalText = ""
        } else if !newPartialText.isEmpty {
            eventsContinuation?.yield(.partial(text: finalText + newPartialText))
        }
    }
}

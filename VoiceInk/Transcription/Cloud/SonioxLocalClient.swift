import Foundation

/// Self-hosted Soniox REST client.
///
/// Exists alongside `LLMkit.SonioxClient` because LLMkit only forwards a single language code,
/// while Soniox's `language_hints` is an array — required to transcribe audio that mixes languages
/// (e.g. English + Indonesian) without picking one and dropping the other.
enum SonioxLocalClient {
    private static let apiBase = "https://api.soniox.com/v1"

    static func transcribe(
        audioData: Data,
        fileName: String,
        apiKey: String,
        model: String,
        languageHints: [String],
        customVocabulary: [String],
        maxWaitSeconds: TimeInterval = 300,
        timeout: TimeInterval = 30
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SonioxLocalError.missingAPIKey
        }

        let fileId = try await uploadFile(audioData: audioData, fileName: fileName, apiKey: apiKey, timeout: timeout)
        let transcriptionId = try await createTranscription(
            fileId: fileId,
            apiKey: apiKey,
            model: model,
            languageHints: languageHints,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
        try await pollStatus(id: transcriptionId, apiKey: apiKey, maxWaitSeconds: maxWaitSeconds, timeout: timeout)
        let transcript = try await fetchTranscript(id: transcriptionId, apiKey: apiKey, timeout: timeout)

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SonioxLocalError.emptyResult
        }
        return transcript
    }

    static func verifyAPIKey(_ apiKey: String, timeout: TimeInterval = 10) async -> (isValid: Bool, errorMessage: String?) {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (false, "API key is missing or empty.")
        }
        guard let url = URL(string: "\(apiBase)/files") else { return (false, "Invalid URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (false, "No HTTP response received.")
            }
            if (200..<300).contains(http.statusCode) {
                return (true, nil)
            }
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            return (false, message)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Steps

    private static func uploadFile(audioData: Data, fileName: String, apiKey: String, timeout: TimeInterval) async throws -> String {
        guard let url = URL(string: "\(apiBase)/files") else {
            throw SonioxLocalError.invalidURL
        }

        let boundary = "VoiceInkSoniox-\(UUID().uuidString)"
        let body = makeMultipartBody(boundary: boundary, fileName: fileName, fileData: audioData)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        try validate(response: response, data: data)

        struct Response: Decodable { let id: String }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw SonioxLocalError.decodingError
        }
        return decoded.id
    }

    private static func createTranscription(
        fileId: String,
        apiKey: String,
        model: String,
        languageHints: [String],
        customVocabulary: [String],
        timeout: TimeInterval
    ) async throws -> String {
        guard let url = URL(string: "\(apiBase)/transcriptions") else {
            throw SonioxLocalError.invalidURL
        }

        var payload: [String: Any] = [
            "file_id": fileId,
            "model": model,
            "enable_speaker_diarization": false,
            "enable_language_identification": true
        ]

        if !customVocabulary.isEmpty {
            payload["context"] = ["terms": customVocabulary]
        }

        if !languageHints.isEmpty {
            payload["language_hints"] = languageHints
            payload["language_hints_strict"] = true
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        struct Response: Decodable { let id: String }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw SonioxLocalError.decodingError
        }
        return decoded.id
    }

    private static func pollStatus(id: String, apiKey: String, maxWaitSeconds: TimeInterval, timeout: TimeInterval) async throws {
        guard let url = URL(string: "\(apiBase)/transcriptions/\(id)") else {
            throw SonioxLocalError.invalidURL
        }

        let start = Date()
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)

            struct Status: Decodable { let status: String }
            if let decoded = try? JSONDecoder().decode(Status.self, from: data) {
                switch decoded.status.lowercased() {
                case "completed":
                    return
                case "failed":
                    throw SonioxLocalError.serverError("Soniox transcription job failed.")
                default:
                    break
                }
            }

            if Date().timeIntervalSince(start) > maxWaitSeconds {
                throw SonioxLocalError.timeout
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private static func fetchTranscript(id: String, apiKey: String, timeout: TimeInterval) async throws -> String {
        guard let url = URL(string: "\(apiBase)/transcriptions/\(id)/transcript") else {
            throw SonioxLocalError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        struct Response: Decodable { let text: String }
        if let decoded = try? JSONDecoder().decode(Response.self, from: data) {
            return decoded.text
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        throw SonioxLocalError.emptyResult
    }

    // MARK: - Helpers

    private static func makeMultipartBody(boundary: String, fileName: String, fileData: Data) -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SonioxLocalError.serverError("No HTTP response received.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw SonioxLocalError.httpError(statusCode: http.statusCode, message: message)
        }
    }
}

enum SonioxLocalError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case decodingError
    case emptyResult
    case timeout
    case serverError(String)
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Soniox API key is missing."
        case .invalidURL:
            return "Failed to construct Soniox URL."
        case .decodingError:
            return "Failed to decode Soniox response."
        case .emptyResult:
            return "Soniox returned an empty transcript."
        case .timeout:
            return "Soniox transcription timed out."
        case .serverError(let message):
            return message
        case .httpError(let code, let message):
            return "Soniox HTTP \(code): \(message)"
        }
    }
}

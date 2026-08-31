import Foundation
import LLMkit

enum ConnectionTestResult {
    case success
    case failure(message: String)
}

/// Lightweight connectivity checks for the custom model editors.
struct CustomModelConnectionTester {
    /// Probes an OpenAI-compatible transcription endpoint with a tiny junk
    /// upload. The server authenticates before validating the audio, so a
    /// 4xx "bad audio" answer still proves the endpoint and key are good.
    static func testTranscriptionEndpoint(endpoint: String, apiKey: String, modelName: String) async
        -> ConnectionTestResult
    {
        guard let url = URL(string: endpoint), isAllowedScheme(url) else {
            return .failure(
                message: String(localized: "Endpoint must use HTTPS (plain HTTP is allowed only for localhost)"))
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append(
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"probe.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
                .data(using: .utf8)!)
        body.append(Data(count: 1024))
        body.append(
            "\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(modelName)\r\n--\(boundary)--\r\n"
                .data(using: .utf8)!)

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.upload(for: request, from: body)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(message: String(localized: "Unexpected response from the server"))
            }

            switch httpResponse.statusCode {
            case 200, 400, 415, 422:
                // Authenticated and routed; the junk audio being rejected is expected.
                return .success
            case 401, 403:
                return .failure(message: String(localized: "Invalid API key"))
            case 404:
                return .failure(
                    message: String(localized: "Endpoint not found (HTTP 404) — check the API endpoint URL"))
            default:
                let message = Self.serverMessage(from: data)
                return .failure(
                    message: String(format: String(localized: "HTTP %lld: %@"), Int64(httpResponse.statusCode), message)
                )
            }
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }

    /// Verifies an OpenAI-compatible chat endpoint using the same request
    /// LLMkit performs when a custom enhancement model is added.
    static func testEnhancementEndpoint(baseURL: String, apiKey: String, modelName: String) async
        -> ConnectionTestResult
    {
        guard let url = URL(string: baseURL), isAllowedScheme(url) else {
            return .failure(
                message: String(localized: "Base URL must use HTTPS (plain HTTP is allowed only for localhost)"))
        }

        let result = await OpenAILLMClient.verifyAPIKey(baseURL: url, apiKey: apiKey, model: modelName)

        if result.isValid {
            return .success
        }
        return .failure(message: result.errorMessage ?? String(localized: "Could not verify this API key"))
    }

    /// HTTPS everywhere; plain HTTP only toward loopback, matching the app's
    /// existing local-server use cases (e.g. Ollama at http://localhost:11434).
    private static func isAllowedScheme(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https":
            return true
        case "http":
            let host = url.host?.lowercased() ?? ""
            return host == "localhost" || host == "127.0.0.1" || host == "::1"
        default:
            return false
        }
    }

    private static func serverMessage(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return String(localized: "No error message")
        }
        return String(text.prefix(120))
    }
}

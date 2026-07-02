import Foundation
import LLMkit

enum ConnectionTestResult {
    case success(latencyMs: Int)
    case failure(message: String)
}

/// Lightweight connectivity checks for the custom model editors.
struct CustomModelConnectionTester {
    /// Probes an OpenAI-compatible transcription endpoint with a tiny junk
    /// upload. The server authenticates before validating the audio, so a
    /// 4xx "bad audio" answer still proves the endpoint and key are good.
    static func testTranscriptionEndpoint(endpoint: String, apiKey: String, modelName: String) async -> ConnectionTestResult {
        guard let url = URL(string: endpoint), url.scheme?.hasPrefix("http") == true else {
            return .failure(String(localized: "API endpoint must be a valid URL"))
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"probe.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(Data(count: 1024))
        body.append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(modelName)\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        let start = Date()
        do {
            let (data, response) = try await session.upload(for: request, from: body)
            let latencyMs = Int(Date().timeIntervalSince(start) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(String(localized: "Unexpected response from the server"))
            }

            switch httpResponse.statusCode {
            case 200, 400, 415, 422:
                // Authenticated and routed; the junk audio being rejected is expected.
                return .success(latencyMs: latencyMs)
            case 401, 403:
                return .failure(String(localized: "Invalid API key"))
            case 404:
                return .failure(String(localized: "Endpoint not found (HTTP 404) — check the API endpoint URL"))
            default:
                let message = Self.serverMessage(from: data)
                return .failure(String(format: String(localized: "HTTP %lld: %@"), Int64(httpResponse.statusCode), message))
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Verifies an OpenAI-compatible chat endpoint using the same request
    /// LLMkit performs when a custom enhancement model is added.
    static func testEnhancementEndpoint(baseURL: String, apiKey: String, modelName: String) async -> ConnectionTestResult {
        guard let url = URL(string: baseURL), url.scheme?.hasPrefix("http") == true else {
            return .failure(String(localized: "Base URL must be a valid URL"))
        }

        let start = Date()
        let result = await OpenAILLMClient.verifyAPIKey(baseURL: url, apiKey: apiKey, model: modelName)
        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)

        if result.isValid {
            return .success(latencyMs: latencyMs)
        }
        return .failure(result.errorMessage ?? String(localized: "Could not verify this API key"))
    }

    private static func serverMessage(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return String(localized: "No error message")
        }
        return String(text.prefix(120))
    }
}

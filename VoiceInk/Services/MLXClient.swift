import Foundation
import LLMkit

/// Client for a local MLX server exposing an OpenAI-compatible API (e.g. `mlx_lm.server`).
///
/// Unlike Ollama, MLX servers don't have a native protocol in LLMkit — they speak the standard
/// OpenAI chat-completions format, so generation is delegated to `OpenAILLMClient`. A
/// placeholder API key is used since local MLX servers don't check it, but `OpenAILLMClient`
/// requires a non-empty string.
struct MLXClient {
    static let defaultBaseURL = URL(string: "http://localhost:8080")!

    private static let placeholderAPIKey = "mlx-local"

    static func checkConnection(baseURL: URL, timeout: TimeInterval = 5) async -> Bool {
        (try? await fetchModels(baseURL: baseURL, timeout: timeout)) != nil
    }

    static func fetchModels(baseURL: URL, timeout: TimeInterval = 10) async throws -> [MLXModel] {
        let url = baseURL.appendingPathComponent("v1/models")

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw MLXError.serviceUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw MLXError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MLXError.serverError
        }

        guard let decoded = try? JSONDecoder().decode(MLXModelsResponse.self, from: data) else {
            throw MLXError.invalidResponse
        }
        return decoded.data
    }

    static func generate(
        baseURL: URL,
        model: String,
        prompt: String,
        systemPrompt: String,
        temperature: Double = 0.3,
        timeout: TimeInterval = 30
    ) async throws -> String {
        let chatURL = baseURL.appendingPathComponent("v1/chat/completions")
        return try await OpenAILLMClient.chatCompletion(
            baseURL: chatURL,
            apiKey: placeholderAPIKey,
            model: model,
            messages: [.user(prompt)],
            systemPrompt: systemPrompt,
            temperature: temperature,
            timeout: timeout
        )
    }
}

struct MLXModel: Codable, Identifiable, Equatable {
    let id: String
}

private struct MLXModelsResponse: Decodable {
    let data: [MLXModel]
}

enum MLXError: Error, LocalizedError {
    case invalidURL
    case serviceUnavailable
    case invalidResponse
    case modelNotFound
    case serverError
    case invalidRequest
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid MLX server URL")
        case .serviceUnavailable:
            return String(localized: "MLX server is not available. Is `mlx_lm.server` running?")
        case .invalidResponse:
            return String(localized: "Invalid response from MLX server")
        case .modelNotFound:
            return String(localized: "Selected model not found")
        case .serverError:
            return String(localized: "MLX server error")
        case .invalidRequest:
            return String(localized: "System prompt is required")
        case .timeout:
            return String(localized: "MLX request timed out")
        }
    }
}

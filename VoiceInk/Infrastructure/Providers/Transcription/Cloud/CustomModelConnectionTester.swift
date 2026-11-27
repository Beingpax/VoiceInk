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
                message: String(localized: "Endpoint must use HTTPS (plain HTTP is allowed only for IP addresses and local host names)"))
        }

        if CustomCloudModel.isChatCompletionsEndpoint(endpoint) {
            return await testChatCompletionsEndpoint(url: url, apiKey: apiKey, modelName: modelName)
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

        return await sendProbe(request: request, body: body)
    }

    private static func testChatCompletionsEndpoint(url: URL, apiKey: String, modelName: String) async
        -> ConnectionTestResult
    {
        let body: Data
        do {
            body = try OpenAICompatibleTranscriptionService.chatCompletionsBody(
                audioData: silentWAV(), modelName: modelName,
                instruction: TranscriptionInstruction.default.prompt(language: nil),
                temperature: 0, maxTokens: 1)
        } catch {
            return .failure(message: error.localizedDescription)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        return await sendProbe(request: request, body: body)
    }

    private static func sendProbe(request: URLRequest, body: Data) async -> ConnectionTestResult {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.upload(for: request, from: body)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(message: String(localized: "Unexpected response from the server"))
            }

            return probeResult(for: httpResponse, data: data)
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }

    private static func probeResult(for httpResponse: HTTPURLResponse, data: Data) -> ConnectionTestResult {
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
    }

    /// A 0.5 s, 16 kHz, 16-bit mono silent WAV so chat-completions probes send
    /// audio-shaped input without touching the filesystem.
    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 16_000
        let sampleCount = Int(sampleRate) / 2
        let dataSize = UInt32(sampleCount * 2)
        let header: [UInt8] = Array("RIFF".utf8) + bytes(UInt32(36) + dataSize)
            + Array("WAVEfmt ".utf8) + bytes(UInt32(16)) + bytes(UInt16(1))
            + bytes(UInt16(1)) + bytes(sampleRate) + bytes(sampleRate * 2)
            + bytes(UInt16(2)) + bytes(UInt16(16)) + Array("data".utf8) + bytes(dataSize)

        var wav = Data(header)
        wav.append(contentsOf: [UInt8](repeating: 0, count: Int(dataSize)))
        return wav
    }

    private static func bytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    /// Verifies an OpenAI-compatible chat endpoint using the same request
    /// LLMkit performs when a custom enhancement model is added.
    static func testEnhancementEndpoint(baseURL: String, apiKey: String, modelName: String) async
        -> ConnectionTestResult
    {
        guard let url = URL(string: baseURL), isAllowedScheme(url) else {
            return .failure(
                message: String(localized: "Base URL must use HTTPS (plain HTTP is allowed only for IP addresses and local host names)"))
        }

        let result = await OpenAILLMClient.verifyAPIKey(baseURL: url, apiKey: apiKey, model: modelName)

        if result.isValid {
            return .success
        }
        return .failure(message: result.errorMessage ?? String(localized: "Could not verify this API key"))
    }

    /// HTTPS everywhere; plain HTTP only for the hosts App Transport Security exempts
    /// (IP address literals, unqualified host names, and `.local` names), so local
    /// servers such as Ollama or vLLM on the LAN pass the same check the app's requests do.
    private static func isAllowedScheme(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https":
            return true
        case "http":
            return isLocalHost(url.host?.lowercased() ?? "")
        default:
            return false
        }
    }

    private static func isLocalHost(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 || inet_pton(AF_INET6, host, &ipv6) == 1 {
            return true
        }
        return !host.contains(".") || host.hasSuffix(".local")
    }

    private static func serverMessage(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return String(localized: "No error message")
        }
        return String(text.prefix(120))
    }
}

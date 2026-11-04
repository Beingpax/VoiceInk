import Foundation

class OpenAICompatibleTranscriptionService {
    func transcribe(
        audioURL: URL, model: CustomCloudModel, context: TranscriptionRequestContext, timeout: TimeInterval
    ) async throws -> String {
        guard let url = URL(string: model.apiEndpoint) else {
            throw NSError(
                domain: "CustomWhisperTranscriptionService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid API endpoint URL"])
        }

        if model.usesChatCompletions {
            return try await transcribeWithChatCompletions(
                audioURL: audioURL, url: url, model: model, context: context, timeout: timeout)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(model.apiKey)", forHTTPHeaderField: "Authorization")

        let body = try buildRequestBody(
            audioURL: audioURL, modelName: model.modelName, boundary: boundary, context: context)
        // Ephemeral session per request: the shared session persists Alt-Svc and upgrades
        // new connections to HTTP/3, but QUIC bulk uploads blackhole behind VPNs that drop
        // full-size UDP datagrams (e.g. GlobalProtect), timing out large audio uploads.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        do {
            return try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
        } catch {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }

    private func buildRequestBody(
        audioURL: URL, modelName: String, boundary: String, context: TranscriptionRequestContext
    ) throws -> Data {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }

        let selectedLanguage = context.language ?? "auto"
        let crlf = "\r\n"
        var body = Data()

        func append(_ string: String) { body.append(string.data(using: .utf8)!) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\(crlf)")
            append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)")
            body.append(value.data(using: .utf8)!)
            append(crlf)
        }

        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\(crlf)")
        append("Content-Type: audio/wav\(crlf)\(crlf)")
        body.append(audioData)
        append(crlf)

        field("model", modelName)
        field("response_format", "json")
        field("temperature", "0")

        if selectedLanguage != "auto" && !selectedLanguage.isEmpty {
            field("language", selectedLanguage)
        }

        append("--\(boundary)--\(crlf)")
        return body
    }

    /// Instructions and audio travel in a single user message; Nemotron-style
    /// models served by vLLM read the transcript back from `choices[0].message.content`.
    private func transcribeWithChatCompletions(
        audioURL: URL, url: URL, model: CustomCloudModel, context: TranscriptionRequestContext,
        timeout: TimeInterval
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(model.apiKey)", forHTTPHeaderField: "Authorization")

        let body = try buildChatCompletionsBody(audioURL: audioURL, model: model, context: context)
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let decoded = try? JSONDecoder().decode(ChatCompletionsResponse.self, from: data),
            let content = decoded.choices.first?.message.content,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CloudTranscriptionError.noTranscriptionReturned
        }

        return Self.processedTranscript(from: content)
    }

    private func buildChatCompletionsBody(
        audioURL: URL, model: CustomCloudModel, context: TranscriptionRequestContext
    ) throws -> Data {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }

        var instruction = (context.instruction ?? .default).prompt(language: context.language)
        if let terms = context.vocabulary?.terms, !terms.isEmpty {
            instruction += " Context terms: " + terms.joined(separator: ", ") + "."
        }

        let audioDataURL =
            "data:\(Self.audioMIMEType(for: audioURL));base64,\(audioData.base64EncodedString())"

        let message: [String: Any] = [
            "role": "user",
            "content": [
                ["type": "text", "text": instruction],
                ["type": "audio_url", "audio_url": ["url": audioDataURL]],
            ] as [[String: Any]],
        ]

        let body: [String: Any] = [
            "model": model.modelName,
            "messages": [message],
            "temperature": 0,
            "chat_template_kwargs": ["enable_thinking": false],
            "skip_special_tokens": false,
            "spaces_between_special_tokens": false,
        ]

        return try JSONSerialization.data(withJSONObject: body)
    }

    private static func audioMIMEType(for audioURL: URL) -> String {
        switch audioURL.pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "flac": return "audio/flac"
        case "ogg": return "audio/ogg"
        default: return "audio/wav"
        }
    }

    private static func processedTranscript(from content: String) -> String {
        let withoutThinking = removingThinkingBlock(content)
        let withoutLoops = removingGenerationLoops(withoutThinking)
        return formattingSpeakerTags(withoutLoops)
    }

    private static func removingThinkingBlock(_ text: String) -> String {
        guard
            let regex = try? NSRegularExpression(
                pattern: "<think>.*?</think>", options: [.dotMatchesLineSeparators])
        else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Collapses the degenerate token loops instruction-tuned audio models fall
    /// into, following the guardrail published with NVIDIA's Nemotron model card.
    private static func removingGenerationLoops(_ text: String) -> String {
        let collapsedCharacters = replacingMatches(
            in: text, pattern: "(.)\\1{20,}", template: "$1")
        return replacingMatches(
            in: collapsedCharacters, pattern: "(.{1,4096}?)\\1{19,}", template: "$1")
    }

    private static func replacingMatches(in text: String, pattern: String, template: String) -> String {
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern, options: [.dotMatchesLineSeparators])
        else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    /// Turns `<spk:0>` markers into `Speaker 1:` paragraphs; text without tags is
    /// returned unchanged.
    private static func formattingSpeakerTags(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\s*<spk:(\\d+)>\\s*") else {
            return text
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: text),
                let numberRange = Range(match.range(at: 1), in: text)
            else { continue }

            result += text[cursor..<matchRange.lowerBound]
            let number = (Int(text[numberRange]) ?? 0) + 1
            let separator = result.isEmpty ? "" : "\n\n"
            result += "\(separator)Speaker \(number): "
            cursor = matchRange.upperBound
        }

        result += text[cursor...]
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ChatCompletionsResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct TranscriptionResponse: Decodable {
        let text: String
        let language: String?
        let duration: Double?
    }
}

import Foundation
import os

private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "GeminiMeetingSummarizer")

// Hard-coded for MVP. A picker in Meetings settings can expose this later.
private let geminiModel = "gemini-2.5-flash"

@MainActor
final class GeminiMeetingSummarizer: MeetingSummarizer {
    private let aiService: AIService

    init(aiService: AIService) {
        self.aiService = aiService
    }

    var providerDisplayName: String { "Gemini" }

    var isConfigured: Bool {
        APIKeyManager.shared.hasAPIKey(forProvider: AIProvider.gemini.rawValue)
    }

    func summarize(transcript: String) async throws -> MeetingSummary {
        guard isConfigured,
              let apiKey = APIKeyManager.shared.getAPIKey(forProvider: AIProvider.gemini.rawValue)
        else {
            throw MeetingSummaryError.notConfigured
        }

        let prompt = buildPrompt(transcript: transcript)
        let requestBody = buildRequestBody(prompt: prompt)

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModel):generateContent?key=\(apiKey)") else {
            throw MeetingSummaryError.requestFailed("Invalid Gemini API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // URLCache.shared is disabled at app launch — no extra work needed here.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw MeetingSummaryError.requestFailed("Failed to encode request: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            logger.error("Network error calling Gemini: \(error.localizedDescription, privacy: .public)")
            throw MeetingSummaryError.requestFailed("Network error: \(error.localizedDescription)")
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            // Response body can echo the prompt back (which includes the full meeting transcript) — keep it private.
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? "<unreadable>"
            logger.error("Gemini HTTP \(httpResponse.statusCode, privacy: .public): \(snippet, privacy: .private)")
            throw MeetingSummaryError.requestFailed("HTTP \(httpResponse.statusCode): \(snippet)")
        }

        return try parseResponse(data: data)
    }

    // MARK: - Private helpers

    private func buildPrompt(transcript: String) -> String {
        """
        You are summarizing a meeting transcript. The transcript is diarized: each line is prefixed with the speaker label and timestamp.

        Produce:
        - title: a short meeting title (3–7 words)
        - subtitle: a single-line description of what the meeting was about (under 15 words)
        - tldr: 2–4 sentences capturing the outcome and key decisions
        - keyPoints: 3–6 bullet points of the main topics discussed
        - actionItems: each action item as "Name: Action (by deadline if stated)". Empty array if none.

        Transcript:
        \(transcript)
        """
    }

    private func buildRequestBody(prompt: String) -> GeminiRequestBody {
        let schema = ResponseSchema(
            type: "OBJECT",
            properties: [
                "title":       SchemaProperty(type: "STRING"),
                "subtitle":    SchemaProperty(type: "STRING"),
                "tldr":        SchemaProperty(type: "STRING"),
                "keyPoints":   SchemaProperty(type: "ARRAY", items: SchemaItems(type: "STRING")),
                "actionItems": SchemaProperty(type: "ARRAY", items: SchemaItems(type: "STRING"))
            ],
            required: ["title", "subtitle", "tldr", "keyPoints", "actionItems"],
            propertyOrdering: ["title", "subtitle", "tldr", "keyPoints", "actionItems"]
        )

        let generationConfig = GenerationConfig(
            responseMimeType: "application/json",
            responseSchema: schema
        )

        return GeminiRequestBody(
            contents: [GeminiContent(parts: [GeminiPart(text: prompt)])],
            generationConfig: generationConfig
        )
    }

    private func parseResponse(data: Data) throws -> MeetingSummary {
        let outerResponse: GeminiOuterResponse
        do {
            outerResponse = try JSONDecoder().decode(GeminiOuterResponse.self, from: data)
        } catch {
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? "<unreadable>"
            logger.error("Failed to decode Gemini outer response: \(error.localizedDescription, privacy: .public) — body: \(snippet, privacy: .private)")
            throw MeetingSummaryError.invalidResponse("Could not decode Gemini response: \(error.localizedDescription)")
        }

        guard let jsonText = outerResponse.candidates.first?.content.parts.first?.text else {
            throw MeetingSummaryError.invalidResponse("No text in Gemini response candidates")
        }

        guard let jsonData = jsonText.data(using: .utf8) else {
            throw MeetingSummaryError.invalidResponse("Gemini returned non-UTF8 JSON text")
        }

        let inner: GeminiSummaryPayload
        do {
            inner = try JSONDecoder().decode(GeminiSummaryPayload.self, from: jsonData)
        } catch {
            logger.error("Failed to decode inner summary JSON: \(error.localizedDescription, privacy: .public) — text: \(jsonText, privacy: .private)")
            throw MeetingSummaryError.invalidResponse("Could not decode summary JSON: \(error.localizedDescription)")
        }

        return MeetingSummary(
            title: inner.title,
            subtitle: inner.subtitle,
            tldr: inner.tldr,
            keyPoints: inner.keyPoints,
            actionItems: inner.actionItems
        )
    }
}

// MARK: - Codable request types

private struct GeminiRequestBody: Encodable {
    let contents: [GeminiContent]
    let generationConfig: GenerationConfig
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    let text: String
}

private struct GenerationConfig: Encodable {
    let responseMimeType: String
    let responseSchema: ResponseSchema
}

private struct ResponseSchema: Encodable {
    let type: String
    let properties: [String: SchemaProperty]
    let required: [String]
    let propertyOrdering: [String]
}

private struct SchemaProperty: Encodable {
    let type: String
    var items: SchemaItems?
}

private struct SchemaItems: Encodable {
    let type: String
}

// MARK: - Codable response types

private struct GeminiOuterResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiResponseContent
}

private struct GeminiResponseContent: Decodable {
    let parts: [GeminiResponsePart]
}

private struct GeminiResponsePart: Decodable {
    let text: String
}

// Inner payload — what Gemini emits as the stringified JSON blob.
private struct GeminiSummaryPayload: Decodable {
    let title: String
    let subtitle: String
    let tldr: String
    let keyPoints: [String]
    let actionItems: [String]
}

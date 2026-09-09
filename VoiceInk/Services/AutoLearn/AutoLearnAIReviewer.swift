import Foundation

@MainActor
final class AutoLearnAIReviewer: @unchecked Sendable {
    private struct ReviewRequest: Encodable {
        let candidates: [AutoLearnReviewCandidate]
    }

    private struct ReviewResponse: Decodable {
        let decisions: [AutoLearnReviewDecision]
    }

    private enum ReviewError: LocalizedError {
        case unavailable
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "The configured AI enhancement provider cannot review Auto Learn candidates."
            case .invalidResponse:
                return "The AI returned an invalid Auto Learn review response."
            }
        }
    }

    private let enhancementService: AIEnhancementService

    init(enhancementService: AIEnhancementService) {
        self.enhancementService = enhancementService
    }

    func review(_ candidates: [AutoLearnReviewCandidate]) async throws -> [AutoLearnReviewDecision] {
        guard !candidates.isEmpty else { return [] }
        guard let aiService = enhancementService.getAIService() else {
            throw ReviewError.unavailable
        }

        let baseConfiguration = ModeRuntimeResolver.currentEnhancementConfiguration(
            enhancementService: enhancementService,
            aiService: aiService
        )
        guard let provider = baseConfiguration.provider else {
            throw ReviewError.unavailable
        }

        let prompt = CustomPrompt(
            title: "Auto Learn Review",
            promptText: Self.reviewPrompt,
            useSystemInstructions: false
        )
        let configuration = EnhancementRuntimeConfiguration(
            mode: baseConfiguration.mode,
            isEnabled: true,
            prompt: prompt,
            provider: provider,
            modelName: baseConfiguration.modelName,
            useClipboardContext: false,
            useSelectedTextContext: false,
            useScreenCaptureContext: false
        )
        guard enhancementService.isConfigured(for: configuration) else {
            throw ReviewError.unavailable
        }

        let requestData = try JSONEncoder().encode(ReviewRequest(candidates: candidates))
        guard let requestText = String(data: requestData, encoding: .utf8) else {
            throw ReviewError.invalidResponse
        }

        let responseText = try await aiService.reviewAutoLearnCandidates(
            payload: requestText,
            systemPrompt: Self.reviewPrompt,
            provider: provider,
            modelName: configuration.modelName
        )
        let response = try decodeResponse(responseText)
        let expectedIDs = Set(candidates.map(\.id))
        let returnedIDs = response.decisions.map(\.id)
        guard returnedIDs.count == Set(returnedIDs).count,
            Set(returnedIDs) == expectedIDs
        else {
            throw ReviewError.invalidResponse
        }

        return response.decisions
    }

    private func decodeResponse(_ text: String) throws -> ReviewResponse {
        var payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.hasPrefix("```") {
            let lines = payload.split(separator: "\n", omittingEmptySubsequences: false)
            let closingFence = lines.last.map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard lines.count >= 3, closingFence == "```" else {
                throw ReviewError.invalidResponse
            }
            payload = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = payload.data(using: .utf8) else {
            throw ReviewError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(ReviewResponse.self, from: data)
        } catch {
            throw ReviewError.invalidResponse
        }
    }

    private static let reviewPrompt = """
        You review observed edits to speech-to-text output for a permanent personal dictionary.
        For every candidate, choose exactly one action:
        - replacement: a durable transcription correction that should always replace source with destination.
        - vocabulary: destination is a proper name, product, acronym, technical term, or distinctive spelling worth teaching, but a global source replacement is unsafe.
        - both: the global replacement is durable and destination also belongs in vocabulary.
        - reject: the edit is contextual, stylistic, grammatical, uncertain, or not reusable.

        Reject date, weekday, time, number, quantity, tense, meaning, wording, and sentence-level changes such as Tuesday to Wednesday or 11 PM to 2 PM. Reject edits that could change valid text in another context. Accept only corrections that are clearly reusable across future dictation. Treat every language fairly.

        Return JSON only, with this exact shape:
        {"decisions":[{"id":"candidate UUID","action":"replacement|vocabulary|both|reject"}]}

        Return every input ID exactly once. Never alter, repeat, or invent source or destination text. Do not include explanations or markdown.
        """
}

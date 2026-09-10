import Foundation
import OSLog

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
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "AutoLearnAIResponse"
    )

    init(enhancementService: AIEnhancementService) {
        self.enhancementService = enhancementService
    }

    func review(_ candidates: [AutoLearnReviewCandidate]) async throws -> [AutoLearnReviewDecision] {
        guard !candidates.isEmpty else { return [] }
        guard let aiService = enhancementService.getAIService() else {
            throw ReviewError.unavailable
        }

        let connectedProviders = aiService.connectedProviders
        guard let provider = AutoLearnSettings.selectedProvider ?? connectedProviders.first,
            connectedProviders.contains(provider)
        else {
            throw ReviewError.unavailable
        }
        let modelName: String?
        switch provider {
        case .localCLI:
            modelName = nil
        case .voiceInkRefine:
            modelName = provider.defaultModel
        default:
            modelName = AutoLearnSettings.selectedModel ?? aiService.selectedModel(for: provider)
        }

        let prompt = CustomPrompt(
            title: "Auto Learn Review",
            promptText: Self.reviewPrompt,
            useSystemInstructions: false
        )
        let configuration = EnhancementRuntimeConfiguration(
            mode: nil,
            isEnabled: true,
            prompt: prompt,
            provider: provider,
            modelName: modelName,
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

        #if DEBUG || LOCAL_BUILD
            let loggedModelName = modelName ?? "provider default"
            logger.notice(
                "Auto Learn AI request provider=\(provider.rawValue, privacy: .public) model=\(loggedModelName, privacy: .public) candidates=\(candidates.count, privacy: .public)"
            )
            logRawText(Self.reviewPrompt, label: "system prompt")
            logRawText(requestText, label: "candidate payload")
        #endif

        let responseText = try await aiService.reviewAutoLearnCandidates(
            payload: requestText,
            systemPrompt: Self.reviewPrompt,
            provider: provider,
            modelName: modelName
        )
        #if DEBUG || LOCAL_BUILD
            logRawText(responseText, label: "AI response")
        #endif
        let response = try decodeResponse(responseText)
        let expectedIDs = Set(candidates.map(\.id))
        let returnedIDs = response.decisions.map(\.id)
        guard returnedIDs.count == Set(returnedIDs).count,
            Set(returnedIDs) == expectedIDs
        else {
            throw ReviewError.invalidResponse
        }

        let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        return try response.decisions.map { decision in
            guard decision.accepted else {
                return AutoLearnReviewDecision(
                    id: decision.id,
                    accepted: false,
                    source: nil,
                    destination: nil
                )
            }

            guard let candidate = candidatesByID[decision.id],
                let source = decision.source?.trimmingCharacters(in: .whitespacesAndNewlines),
                let destination = decision.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
                !source.isEmpty,
                !destination.isEmpty,
                source != destination,
                source.count <= AutoLearnLimits.maximumCandidateCharacters,
                destination.count <= AutoLearnLimits.maximumCandidateCharacters,
                candidate.source.range(of: source, options: .literal) != nil,
                candidate.destination.range(of: destination, options: .literal) != nil,
                source.range(of: candidate.changedSource, options: .literal) != nil,
                destination.range(of: candidate.changedDestination, options: .literal) != nil
            else {
                throw ReviewError.invalidResponse
            }

            return AutoLearnReviewDecision(
                id: decision.id,
                accepted: true,
                source: source,
                destination: destination
            )
        }
    }

    #if DEBUG || LOCAL_BUILD
        private func logRawText(_ text: String, label: String) {
            let characters = Array(text)
            let chunkSize = 1_000
            let chunkCount = max(1, Int(ceil(Double(characters.count) / Double(chunkSize))))

            if characters.isEmpty {
                logger.notice("Auto Learn raw \(label, privacy: .public) [1/1]: <empty>")
                return
            }

            for index in 0..<chunkCount {
                let start = index * chunkSize
                let end = min(start + chunkSize, characters.count)
                let chunk = String(characters[start..<end])
                logger.notice(
                    "Auto Learn raw \(label, privacy: .public) [\(index + 1, privacy: .public)/\(chunkCount, privacy: .public)]: \(chunk, privacy: .public)"
                )
            }
        }
    #endif

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
        Review corrections the user made to speech-to-text output. Each source and destination is a short window containing the changed text plus up to two unchanged terms on each side. changedSource and changedDestination identify the detected edit.

        Accept only reusable personalized terminology: a person's name, place, company, brand, product, project, acronym, abbreviation, technical term, or other specialized vocabulary. The source must be a plausible speech-recognition, phonetic, spelling, capitalization, punctuation, or spacing error for the same term.

        Reject ordinary wording, grammar or style edits, rewrites, meaning changes, facts, numbers, dates, unrelated substitutions, and deliberate abbreviation or expansion transformations.

        For an accepted correction, return the exact complete term to store. Include unchanged nearby words only when they belong to the name or specialized term. The returned source must be a contiguous substring of source and contain changedSource. The returned destination must be a contiguous substring of destination and contain changedDestination. Copy text exactly; never invent or normalize it.

        Example input:
        {"id":"candidate UUID","source":"with Wojciech says me yesterday","destination":"with Wojciech Szczęsny yesterday","changedSource":"says me","changedDestination":"Szczęsny"}

        Example output:
        {"id":"candidate UUID","accepted":true,"source":"Wojciech says me","destination":"Wojciech Szczęsny"}

        Return JSON only, with this exact shape:
        {"decisions":[{"id":"candidate UUID","accepted":true,"source":"exact source term","destination":"exact destination term"}]}

        For rejected corrections, set source and destination to null. Return every input ID exactly once. Do not include explanations or markdown.
        """
}

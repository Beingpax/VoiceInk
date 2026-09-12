import Foundation
import OSLog

@MainActor
final class AutoLearnAIReviewer: @unchecked Sendable {
    private struct AutoLearnReviewRequest: Encodable {
        struct CandidateForReview: Encodable {
            let candidateID: Int
            let originalTextContext: String
            let correctedTextContext: String
            let originalChangedText: String
            let correctedChangedText: String
        }

        let candidatesForReview: [CandidateForReview]
    }

    private struct AutoLearnReviewResponse: Decodable {
        let reviewDecisions: [CandidateReviewDecision]
    }

    private struct CandidateReviewDecision: Decodable {
        let candidateID: Int
        let learningAction: AutoLearnReviewAction
        let correctedTermIsPersonName: Bool?
        let incorrectTextToReplace: String?
        let correctedVocabularyTerm: String?
    }

    private enum ReviewError: LocalizedError {
        case unavailable
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return String(
                    localized: "The configured AI enhancement provider cannot review Auto Learn candidates."
                )
            case .invalidResponse:
                return String(localized: "The AI returned an invalid Auto Learn review response.")
            }
        }
    }

    private let enhancementService: AIEnhancementService
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "AutoLearnAIReview"
    )

    init(enhancementService: AIEnhancementService) {
        self.enhancementService = enhancementService
    }

    func review(_ candidates: [AutoLearnReviewCandidate]) async throws -> AutoLearnReviewResult {
        guard !candidates.isEmpty else {
            return AutoLearnReviewResult(reviewDecisions: [], unresolvedCandidateIDs: [])
        }
        guard let aiService = enhancementService.getAIService() else {
            throw ReviewError.unavailable
        }

        let connectedProviders = aiService.connectedProviders
        // Respect the user's provider choice. Ollama keeps correction review on-device.
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

        let candidatesForReview = candidates.enumerated().map { index, candidate in
            AutoLearnReviewRequest.CandidateForReview(
                candidateID: index,
                originalTextContext: candidate.originalTextContext,
                correctedTextContext: candidate.correctedTextContext,
                originalChangedText: candidate.detectedOriginalText,
                correctedChangedText: candidate.userCorrectedText
            )
        }
        let requestData = try JSONEncoder().encode(
            AutoLearnReviewRequest(candidatesForReview: candidatesForReview)
        )
        guard let requestText = String(data: requestData, encoding: .utf8) else {
            throw ReviewError.invalidResponse
        }

        let responseText = try await aiService.reviewAutoLearnCandidates(
            payload: requestText,
            systemPrompt: Self.reviewPrompt,
            provider: provider,
            modelName: modelName
        )
        let candidateReviewDecisions = try decodeResponse(responseText)
        let expectedCandidateIDs = Set(candidates.indices)
        let decisionsByCandidateID = Dictionary(grouping: candidateReviewDecisions) {
            $0.candidateID
        }
        for unknownCandidateID in decisionsByCandidateID.keys
        where !expectedCandidateIDs.contains(unknownCandidateID) {
            logger.warning(
                "Ignoring Auto Learn decision with unknown candidate ID=\(unknownCandidateID, privacy: .public)"
            )
        }

        var reviewDecisions: [AutoLearnReviewDecision] = []
        var unresolvedCandidateIDs = Set<UUID>()

        for (index, candidate) in candidates.enumerated() {
            guard let matches = decisionsByCandidateID[index], matches.count == 1,
                let decision = matches.first
            else {
                unresolvedCandidateIDs.insert(candidate.candidateID)
                continue
            }
            let learningAction = decision.learningAction

            guard learningAction != .rejectCorrection else {
                reviewDecisions.append(
                    AutoLearnReviewDecision(
                        candidateID: candidate.candidateID,
                        learningAction: .rejectCorrection,
                        incorrectTextToReplace: nil,
                        correctedVocabularyTerm: nil
                    )
                )
                continue
            }

            guard let correctedTermIsPersonName = decision.correctedTermIsPersonName,
                let correctedVocabularyTerm = decision.correctedVocabularyTerm?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                unresolvedCandidateIDs.insert(candidate.candidateID)
                continue
            }
            guard
                !correctedVocabularyTerm.isEmpty,
                correctedVocabularyTerm.count <= AutoLearnLimits.maximumCandidateCharacters,
                candidate.correctedTextContext.range(
                    of: correctedVocabularyTerm,
                    options: .literal
                ) != nil,
                correctedVocabularyTerm.range(
                    of: candidate.userCorrectedText,
                    options: .literal
                ) != nil,
                !correctedTermIsPersonName
                    || !hasOmittedAdjacentNameComponent(
                        correctedVocabularyTerm,
                        in: candidate.correctedTextContext
                    )
            else {
                unresolvedCandidateIDs.insert(candidate.candidateID)
                continue
            }

            if learningAction == .addVocabularyOnly {
                reviewDecisions.append(
                    AutoLearnReviewDecision(
                        candidateID: candidate.candidateID,
                        learningAction: .addVocabularyOnly,
                        incorrectTextToReplace: nil,
                        correctedVocabularyTerm: correctedVocabularyTerm
                    )
                )
                continue
            }

            guard let incorrectTextToReplace = decision.incorrectTextToReplace?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                unresolvedCandidateIDs.insert(candidate.candidateID)
                continue
            }
            guard
                !incorrectTextToReplace.isEmpty,
                incorrectTextToReplace != correctedVocabularyTerm,
                incorrectTextToReplace.count <= AutoLearnLimits.maximumCandidateCharacters,
                candidate.originalTextContext.range(
                    of: incorrectTextToReplace,
                    options: .literal
                ) != nil,
                incorrectTextToReplace.range(
                    of: candidate.detectedOriginalText,
                    options: .literal
                ) != nil,
                !correctedTermIsPersonName
                    || !hasOmittedAdjacentNameComponent(
                        incorrectTextToReplace,
                        in: candidate.originalTextContext
                    )
            else {
                unresolvedCandidateIDs.insert(candidate.candidateID)
                continue
            }

            reviewDecisions.append(
                AutoLearnReviewDecision(
                    candidateID: candidate.candidateID,
                    learningAction: .addReplacementAndVocabulary,
                    incorrectTextToReplace: incorrectTextToReplace,
                    correctedVocabularyTerm: correctedVocabularyTerm
                )
            )
        }

        return AutoLearnReviewResult(
            reviewDecisions: reviewDecisions,
            unresolvedCandidateIDs: unresolvedCandidateIDs
        )
    }

    private func decodeResponse(_ text: String) throws -> [CandidateReviewDecision] {
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
            return try JSONDecoder()
                .decode(AutoLearnReviewResponse.self, from: data)
                .reviewDecisions
        } catch {
            throw ReviewError.invalidResponse
        }
    }

    private func hasOmittedAdjacentNameComponent(
        _ term: String,
        in context: String
    ) -> Bool {
        guard let termRange = context.range(of: term) else { return false }
        if let precedingRange = adjacentToken(before: termRange.lowerBound, in: context),
            isLikelyNameComponent(context[precedingRange])
        {
            return true
        }
        if let followingRange = adjacentToken(after: termRange.upperBound, in: context),
            isLikelyNameComponent(context[followingRange])
        {
            return true
        }
        return false
    }

    private func adjacentToken(
        before index: String.Index,
        in text: String
    ) -> Range<String.Index>? {
        var upperBound = index
        while upperBound > text.startIndex {
            let previous = text.index(before: upperBound)
            guard text[previous].isWhitespace else { break }
            upperBound = previous
        }
        guard upperBound < index, upperBound > text.startIndex else { return nil }

        var lowerBound = upperBound
        while lowerBound > text.startIndex {
            let previous = text.index(before: lowerBound)
            guard !text[previous].isWhitespace else { break }
            lowerBound = previous
        }
        return lowerBound..<upperBound
    }

    private func adjacentToken(
        after index: String.Index,
        in text: String
    ) -> Range<String.Index>? {
        var lowerBound = index
        while lowerBound < text.endIndex, text[lowerBound].isWhitespace {
            lowerBound = text.index(after: lowerBound)
        }
        guard lowerBound > index, lowerBound < text.endIndex else { return nil }

        var upperBound = lowerBound
        while upperBound < text.endIndex, !text[upperBound].isWhitespace {
            upperBound = text.index(after: upperBound)
        }
        return lowerBound..<upperBound
    }

    private func isLikelyNameComponent(_ token: Substring) -> Bool {
        let trimmed = token.trimmingCharacters(in: .punctuationCharacters)
        guard let firstLetter = trimmed.first(where: { $0.isLetter }), firstLetter.isUppercase else {
            return false
        }
        return trimmed.allSatisfy {
            $0.isLetter || $0 == "-" || $0 == "'" || $0 == "’"
        }
    }

    private static let reviewPrompt = """
        Review user corrections to speech-to-text. Each candidate contains originalChangedText and correctedChangedText plus short originalTextContext and correctedTextContext windows.

        Classify every candidate independently with exactly one learningAction:

        1. addReplacementAndVocabulary
        Use when the corrected text is a reusable person, place, company, brand, product, project, acronym, technical term, or specialized word, and the original text is a plausible transcription of the same spoken term. Phonetic similarity, not merely related meaning, is what makes a replacement safe. Judge pronunciation as well as spelling. Allow capitalization, punctuation, joined or split words, and substantial spelling differences when the phrases still sound alike. Examples include "voicing", "Boysync", and "boys ing" to "VoiceInk"; "get hub" to "GitHub"; "post gray sequel" to "PostgreSQL"; "data base" to "database"; "web hook" to "webhook"; "cube or netties" to "Kubernetes"; and "sequel light" to "SQLite".

        A spelling correction inside a person's name is addReplacementAndVocabulary. Include the complete name from both context windows: "Maya Jonson" to "Maya Johnson", and "Prakash Jossipax" to "Prakash Joshi Pax". Do not downgrade these to addVocabularyOnly merely because only one name component changed.

        2. addVocabularyOnly
        Use when the corrected text is reusable terminology but the original text is too phonetically and orthographically different to be a safe global replacement. Semantic relatedness alone is insufficient for a replacement. For example, classify "Procastus Apex" to "Prakash Joshi Pax", "speech app" to "VoiceInk", "project owner" to "Ada Lovelace", and "mister Smith" to "Dr. Jane Smith" as addVocabularyOnly. Return the complete corrected entity from correctedTextContext. Uncertainty about whether two phrases sound like the same spoken term should prefer addVocabularyOnly, not addReplacementAndVocabulary.

        3. rejectCorrection
        Use when the corrected text is not reusable terminology, or the edit is ordinary wording, grammar, style, meaning, facts, numbers, dates, an unrelated rewrite, or a deliberate abbreviation or expansion. Deliberate semantic shortening is not a transcription correction: reject "application programming interface" to "API", "central processing unit" to "CPU", and "pull request" to "PR". If the original text already correctly names a term, reject additions or removals of qualifiers, editions, or generic type words, such as "PostgreSQL" to "PostgreSQL database", "Claude" to "Claude AI", "GitHub" to "GitHub Enterprise", and "Visual Studio" to "Visual Studio Code". Do not add ordinary nouns merely because they are nouns.

        A common original word may still use addReplacementAndVocabulary when it plausibly sounds like the corrected term. For the product VoiceInk, each of "voicing", "Boysink", and "boys ing" passes the phonetic gate and is addReplacementAndVocabulary. Do not use addVocabularyOnly merely because the original text is an ordinary word.

        Hard replacement gate: addReplacementAndVocabulary is allowed only when the complete original and corrected terms have recognizably similar pronunciation or differ only by spelling, capitalization, punctuation, or word boundaries. A synonym, description, role, or semantic reference is never enough. Phrases such as "database company" and "Supabase", "our designer" and "Sofia Hernández", "cloud vendor" and "Cloudflare", or "new framework" and "SvelteKit" do not sound alike and must be addVocabularyOnly. Never create a global replacement for these descriptive sources.

        A capitalization-only edit of an ordinary word is rejectCorrection unless the context clearly uses a proper name or specialized term. For example, reject "apple" to "Apple" in "eat an apple today"; accept "voiceink" to "VoiceInk" when it names the product.

        Multiple original transcription errors may independently map to the same corrected term. Judge each candidate independently and never reject or downgrade one because another candidate has the same corrected term.

        Be conservative. A false acceptance is more harmful than missing a useful correction. If the corrected text is not clearly reusable terminology, or the edit does not clearly satisfy an acceptance rule, use rejectCorrection. Use addVocabularyOnly for a phonetically distant original phrase only when the corrected term is unambiguously a proper name, brand, product, project, acronym, technical term, or specialized term.

        Select complete term boundaries from the context. For every person's name, return the maximal contiguous person name visible in both contexts—not only the edited component. If a surname changes, include its unchanged given and middle names. If a given name changes, include its unchanged surname. This rule is mandatory for both addReplacementAndVocabulary and addVocabularyOnly, even when the changed component alone could be reusable. Apply the same complete-boundary rule to multiword entities and specialized terms. Do not include surrounding sentence words.

        Never return only a changed surname or name fragment when an unchanged adjacent name component belongs to the same person. Follow these exact boundary examples:

        Input: {"candidateID":1,"originalTextContext":"with Prakash Jossipax yesterday","correctedTextContext":"with Prakash Joshi Pax yesterday","originalChangedText":"Jossipax","correctedChangedText":"Joshi Pax"}
        Decision: {"candidateID":1,"learningAction":"addReplacementAndVocabulary","correctedTermIsPersonName":true,"incorrectTextToReplace":"Prakash Jossipax","correctedVocabularyTerm":"Prakash Joshi Pax"}

        Input: {"candidateID":2,"originalTextContext":"met Maya Jonson yesterday","correctedTextContext":"met Maya Johnson yesterday","originalChangedText":"Jonson","correctedChangedText":"Johnson"}
        Decision: {"candidateID":2,"learningAction":"addReplacementAndVocabulary","correctedTermIsPersonName":true,"incorrectTextToReplace":"Maya Jonson","correctedVocabularyTerm":"Maya Johnson"}

        Input: {"candidateID":3,"originalTextContext":"heard Satya Nadela speak","correctedTextContext":"heard Satya Nadella speak","originalChangedText":"Nadela","correctedChangedText":"Nadella"}
        Decision: {"candidateID":3,"learningAction":"addReplacementAndVocabulary","correctedTermIsPersonName":true,"incorrectTextToReplace":"Satya Nadela","correctedVocabularyTerm":"Satya Nadella"}

        Input: {"candidateID":4,"originalTextContext":"a film by Hiao Miyazaki","correctedTextContext":"a film by Hayao Miyazaki","originalChangedText":"Hiao","correctedChangedText":"Hayao"}
        Decision: {"candidateID":4,"learningAction":"addReplacementAndVocabulary","correctedTermIsPersonName":true,"incorrectTextToReplace":"Hiao Miyazaki","correctedVocabularyTerm":"Hayao Miyazaki"}

        For addReplacementAndVocabulary, incorrectTextToReplace is the complete erroneous term and correctedVocabularyTerm is the complete corrected term to store in Vocabulary. incorrectTextToReplace must be an exact contiguous substring of originalTextContext containing originalChangedText. correctedVocabularyTerm must be an exact contiguous substring of correctedTextContext containing correctedChangedText. Set correctedTermIsPersonName to true only when correctedVocabularyTerm is a person's name; otherwise set it to false.

        For addVocabularyOnly, set incorrectTextToReplace to null and return the complete corrected entity as correctedVocabularyTerm. correctedVocabularyTerm must be an exact contiguous substring of correctedTextContext containing correctedChangedText. Set correctedTermIsPersonName to true only when correctedVocabularyTerm is a person's name; otherwise set it to false.

        For rejectCorrection, set correctedTermIsPersonName, incorrectTextToReplace, and correctedVocabularyTerm to null.

        Return JSON only in this exact shape:
        {"reviewDecisions":[{"candidateID":0,"learningAction":"addReplacementAndVocabulary","correctedTermIsPersonName":true,"incorrectTextToReplace":"complete original term","correctedVocabularyTerm":"complete corrected term"}]}

        Allowed learningAction values are addReplacementAndVocabulary, addVocabularyOnly, and rejectCorrection. correctedTermIsPersonName must be true or false for accepted corrections and null for rejectCorrection. Copy every integer candidateID exactly and return every input candidateID exactly once. Copy text exactly from the supplied context. Do not include explanations or markdown.
        """
}

import AppKit
import NaturalLanguage
import SwiftData
import XCTest
@testable import VoiceInk

@MainActor
final class AutoLearnLocalReviewerTests: XCTestCase {
    private func candidate(_ original: String, _ corrected: String, language: String? = "en")
        -> AutoLearnReviewCandidate {
        .init(candidateID: UUID(), originalText: original, correctedText: corrected, languageCode: language)
    }

    func testConfirmedSpellingCorrectionSavesOnlyTheEdit() async throws {
        let analyzer = FixtureAnalyzer(misspelled: ["sentance"], suggestions: ["sentance": ["sentence"]])
        let result = try await AutoLearnLocalReviewer(analyzer: analyzer).review(
            [candidate("The sentance is clear", "The sentence is clear")], knownTerms: [])
        XCTAssertTrue(result.approvalDecisions.isEmpty)
        XCTAssertEqual(result.reviewDecisions.first?.learningAction, .addReplacementOnly)
        XCTAssertEqual(result.reviewDecisions.first?.incorrectTextToReplace, "sentance")
        XCTAssertEqual(result.reviewDecisions.first?.correctedVocabularyTerm, "sentence")
    }

    func testFalsePositivesDoNotBecomeRulesOrProposals() async throws {
        let fixtures = [
            ("Send it form here", "Send it from here"),
            ("I walk home", "I walked home"),
            ("It is a cup", "It is a cap"),
            ("Call the project manager", "Call Michael Johnson"),
            ("We need the bigger box", "We need the larger box"),
            ("Meet Sarah Connor today", "Meet John Connor today"),
            ("I met Prakash Joshi Pages", "I met Prakash Joshi Pax"),
            ("It costs thirty dollars", "It costs forty dollars"),
            ("Meeting is on June 12", "Meeting is on June 13"),
            ("Use Openai today", "Use OpenAI today"),
            ("email@example.com", "email@sample.com"),
            ("Keep this secret token", "Keep this secret-token"),
            ("I met Jhn yesterday", "I met John Smith yesterday"),
            ("I met Jhn and Jane", "I met John and Janet"),
            ("I met John", "I met John Smith"),
            ("I met John Smith", "I met Smith"),
        ]
        let analyzer = FixtureAnalyzer(misspelled: ["Jhn"],
            entities: ["Michael Johnson": .personalName, "John Connor": .personalName,
                "Prakash Joshi": .personalName, "John Smith": .personalName])
        let reviewer = AutoLearnLocalReviewer(analyzer: analyzer)
        for (original, corrected) in fixtures {
            let result = try await reviewer.review([candidate(original, corrected)], knownTerms: ["Michael Johnson", "from"])
            XCTAssertEqual(result.reviewDecisions.first?.learningAction, .rejectCorrection, "\(original) → \(corrected)")
            XCTAssertTrue(result.approvalDecisions.isEmpty, "\(original) → \(corrected)")
        }
    }

    func testNERNamesRequireApprovalAndPreserveUnchangedComponents() async throws {
        let analyzer = FixtureAnalyzer(misspelled: ["Jhn", "Paax"],
            entities: ["John Smith": .personalName, "Prakash Joshi": .personalName,
                "Micheal Johnson": .personalName, "Michael Johnson": .personalName])
        let reviewer = AutoLearnLocalReviewer(analyzer: analyzer)
        let fixtures = [
            ("Please email Jhn Smith tomorrow", "Please email John Smith tomorrow", "Jhn Smith", "John Smith"),
            ("I met Prakash Joshi Paax today", "I met Prakash Joshi Pax today", "Prakash Joshi Paax", "Prakash Joshi Pax"),
            ("I met Micheal Johnson today", "I met Michael Johnson today", "Micheal Johnson", "Michael Johnson"),
        ]
        for (original, corrected, source, destination) in fixtures {
            let result = try await reviewer.review([candidate(original, corrected)], knownTerms: [])
            XCTAssertTrue(result.reviewDecisions.isEmpty)
            XCTAssertEqual(result.approvalDecisions.count, 1)
            XCTAssertEqual(result.approvalDecisions.first?.learningAction, .addReplacementOnly)
            XCTAssertEqual(result.approvalDecisions.first?.incorrectTextToReplace, source)
            XCTAssertEqual(result.approvalDecisions.first?.correctedVocabularyTerm, destination)
        }
    }

    func testPeoplePlacesAndOrganizationsStayUnderUserControl() async throws {
        let analyzer = FixtureAnalyzer(misspelled: ["Katmandu", "Acmee"],
            entities: ["Kathmandu": .placeName, "Acme Labs": .organizationName])
        let reviewer = AutoLearnLocalReviewer(analyzer: analyzer)
        for edit in [candidate("We visited Katmandu yesterday", "We visited Kathmandu yesterday"),
                     candidate("I work at Acmee Labs", "I work at Acme Labs")] {
            let result = try await reviewer.review([edit], knownTerms: [])
            XCTAssertTrue(result.reviewDecisions.isEmpty)
            XCTAssertEqual(result.approvalDecisions.first?.learningAction, .addReplacementOnly)
        }
    }

    func testApprovedFullNameCanQualifyWithoutAddingVocabulary() async throws {
        let analyzer = FixtureAnalyzer(misspelled: ["Jhn"], entities: ["John Smith": .personalName])
        let result = try await AutoLearnLocalReviewer(analyzer: analyzer).review(
            [candidate("Please email Jhn Smith tomorrow", "Please email John Smith tomorrow")],
            knownTerms: ["John Smith"])
        XCTAssertEqual(result.reviewDecisions.first?.learningAction, .addReplacementOnly)
        XCTAssertEqual(result.reviewDecisions.first?.incorrectTextToReplace, "Jhn Smith")
        XCTAssertTrue(result.approvalDecisions.isEmpty)
    }

    func testApprovedTargetDoesNotOverrideValidSourceWords() async throws {
        let analyzer = FixtureAnalyzer()
        let result = try await AutoLearnLocalReviewer(analyzer: analyzer).review(
            [candidate("Go from here", "Go form here")], knownTerms: ["form"])
        XCTAssertEqual(result.reviewDecisions.first?.learningAction, .rejectCorrection)
        XCTAssertTrue(result.approvalDecisions.isEmpty)
    }

    func testUnknownTechnicalTermNeedsAnApprovedDestination() async throws {
        let analyzer = FixtureAnalyzer(misspelled: ["Lumora", "Lumorra"])
        let reviewer = AutoLearnLocalReviewer(analyzer: analyzer)
        let edit = candidate("We use Lumorra daily", "We use Lumora daily")
        let unknown = try await reviewer.review([edit], knownTerms: [])
        let approved = try await reviewer.review([edit], knownTerms: ["Lumora"])
        XCTAssertEqual(unknown.reviewDecisions.first?.learningAction, .rejectCorrection)
        XCTAssertEqual(approved.reviewDecisions.first?.learningAction, .addReplacementOnly)
    }

    func testUnavailableLanguageOrSpellingDoesNotGuess() async throws {
        let analyzer = FixtureAnalyzer(misspelled: ["sentance"], suggestions: ["sentance": ["sentence"]])
        let reviewer = AutoLearnLocalReviewer(analyzer: analyzer)
        var result = try await reviewer.review([candidate("The sentance is clear", "The sentence is clear", language: "ne")], knownTerms: [])
        XCTAssertEqual(result.reviewDecisions.first?.learningAction, .rejectCorrection)
        analyzer.spellingAvailable = false
        result = try await reviewer.review([candidate("The sentance is clear", "The sentence is clear")], knownTerms: [])
        XCTAssertEqual(result.reviewDecisions.first?.learningAction, .rejectCorrection)
    }

    func testCancelledLocalReviewStopsBeforeReturningDecisions() async throws {
        let reviewer = AutoLearnLocalReviewer(analyzer: FixtureAnalyzer(misspelled: ["sentance"],
            suggestions: ["sentance": ["sentence"]]))
        let edit = candidate("The sentance is clear", "The sentence is clear")
        let task = Task { try await reviewer.review([edit], knownTerms: []) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled review must not return decisions")
        } catch is CancellationError {
            // Expected: the service returns claimed candidates to the queue.
        }
    }

    func testCancelledStoreApplyDoesNotCreateRules() async throws {
        let container = try ModelContainer(for: WordReplacement.self, VocabularyWord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = WordReplacementStore(modelContainer: container)
        let edit = candidate("The sentance is clear", "The sentence is clear")
        let decision = AutoLearnReviewDecision(candidateID: edit.candidateID, learningAction: .addReplacementOnly,
            incorrectTextToReplace: "sentance", correctedVocabularyTerm: "sentence")
        let task = Task {
            await Task.yield()
            return try await store.apply([decision], candidates: [edit])
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled apply must not commit")
        } catch is CancellationError {}
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<WordReplacement>()).isEmpty)
    }

    func testUnicodeNameAlignmentKeepsDiacriticsAndFullName() async throws {
        let analyzer = FixtureAnalyzer(misspelled: ["Jose"], entities: ["José García": .personalName])
        let result = try await AutoLearnLocalReviewer(analyzer: analyzer).review(
            [candidate("I met Jose García today", "I met José García today")], knownTerms: [])
        XCTAssertEqual(result.approvalDecisions.first?.incorrectTextToReplace, "Jose García")
        XCTAssertEqual(result.approvalDecisions.first?.correctedVocabularyTerm, "José García")
    }

    func testManualResultCannotCreateVocabularyAndCanBeUndone() async throws {
        let container = try ModelContainer(for: WordReplacement.self, VocabularyWord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = WordReplacementStore(modelContainer: container)
        let analyzer = FixtureAnalyzer(misspelled: ["Jhn"], entities: ["John Smith": .personalName])
        let edit = candidate("Please email Jhn Smith tomorrow", "Please email John Smith tomorrow")
        let result = try await AutoLearnLocalReviewer(analyzer: analyzer).review([edit], knownTerms: [])
        let summary = try await store.apply(result.approvalDecisions, candidates: [edit])
        XCTAssertEqual(summary.createdCount, 1)
        XCTAssertEqual(summary.vocabularyCount, 0)
        let context = ModelContext(container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<VocabularyWord>()).isEmpty)
        let replacements = try context.fetch(FetchDescriptor<WordReplacement>())
        XCTAssertEqual(replacements.first?.originalText, "Jhn Smith")
        XCTAssertEqual(replacements.first?.replacementText, "John Smith")
        try await store.undo(XCTUnwrap(summary.learnedCorrections.first))
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<WordReplacement>()).isEmpty)
    }

    func testAIReviewDefaultsOnAndExplicitOptOutSurvivesRegistration() async throws {
        let suite = "VoiceInk.AutoLearnTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(AutoLearnSettings.aiReviewEnabled(defaults: defaults))
        defaults.set(false, forKey: AutoLearnSettings.aiReviewEnabledKey)
        defaults.register(defaults: [AutoLearnSettings.aiReviewEnabledKey: true])
        XCTAssertFalse(AutoLearnSettings.aiReviewEnabled(defaults: defaults))
        XCTAssertFalse(AutoLearnSettings.aiReviewEnabled(defaults: try XCTUnwrap(UserDefaults(suiteName: suite))))
    }

    func testOlderBackupLeavesTheReviewPreferenceUnspecified() async throws {
        let backup = try JSONDecoder().decode(GeneralBackup.self, from: Data("{}".utf8))
        XCTAssertNil(backup.isAutoLearnAIReviewEnabled)
    }

    func testQueuePreservesCapturedLanguageAndRecoversLegacyRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("queue.json")
        let legacyID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [[
            "candidateID": legacyID.uuidString, "originalText": "The sentance is clear",
            "correctedText": "The sentence is clear", "reviewStatus": "reviewing"
        ]])
        try data.write(to: fileURL)
        let queue = AutoLearnPendingQueue(fileURL: fileURL)
        try await queue.recoverInterruptedReviews()
        let legacy = try await queue.claimPending(limit: 10)
        XCTAssertEqual(legacy.first?.candidateID, legacyID)
        XCTAssertNil(legacy.first?.languageCode)
        try await queue.remove([legacyID])
        let edits = ["en", "fr"].map { language in
            DetectedCorrectionCandidate(originalText: "The sentance is clear",
                correctedText: "The sentence is clear", languageCode: language)
        }
        let inserted = try await queue.enqueue(edits)
        XCTAssertEqual(inserted, 2)
        let restored = AutoLearnPendingQueue(fileURL: fileURL)
        let candidates = try await restored.claimPending(limit: 10)
        XCTAssertEqual(Set(candidates.compactMap(\.languageCode)), ["en", "fr"])
        try await restored.release(Set(candidates.map(\.candidateID)))
        let pending = try await restored.pendingCount()
        XCTAssertEqual(pending, 2)
    }

    func testUncertainLocalNamesPersistAsReplacementOnlyProposals() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("proposals.json")
        let store = AutoLearnReviewProposalStore(fileURL: fileURL)
        let analyzer = FixtureAnalyzer(misspelled: ["Jhn"], entities: ["John Smith": .personalName])
        let edit = candidate("Please email Jhn Smith tomorrow", "Please email John Smith tomorrow")
        let result = try await AutoLearnLocalReviewer(analyzer: analyzer).review([edit], knownTerms: [])
        try await store.append(decisions: result.approvalDecisions, candidates: [edit])
        // Reprocessing a cancelled or interrupted batch must not duplicate it.
        try await store.append(decisions: result.approvalDecisions, candidates: [edit])
        let restored = AutoLearnReviewProposalStore(fileURL: fileURL)
        let proposals = try await restored.all()
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals.first?.incorrectTextToReplace, "Jhn Smith")
        XCTAssertEqual(proposals.first?.correctedVocabularyTerm, "John Smith")
        XCTAssertEqual(proposals.first?.addsReplacement, true)
        XCTAssertEqual(proposals.first?.addsVocabulary, false)
    }

    func testNativeAppleSpellingAndNameRecognition() async throws {
        guard NLTagger.availableTagSchemes(for: .word, language: .english).contains(.nameType) else {
            throw XCTSkip("English NER assets are not installed")
        }
        let analyzer = AutoLearnLocalTextAnalyzer()
        guard analyzer.spelling(for: "sentence", language: .english) != nil else {
            throw XCTSkip("English spelling is unavailable")
        }
        let reviewer = AutoLearnLocalReviewer(analyzer: analyzer)
        let spelling = try await reviewer.review([candidate("The sentance is clear", "The sentence is clear")], knownTerms: [])
        XCTAssertEqual(spelling.reviewDecisions.first?.learningAction, .addReplacementOnly)
        let name = try await reviewer.review([candidate("Please email Jhn Smith tomorrow", "Please email John Smith tomorrow")], knownTerms: [])
        XCTAssertEqual(name.approvalDecisions.first?.incorrectTextToReplace, "Jhn Smith")
        XCTAssertEqual(name.approvalDecisions.first?.correctedVocabularyTerm, "John Smith")
        let approvedName = try await reviewer.review(
            [candidate("Please email Jhn Smith tomorrow", "Please email John Smith tomorrow")],
            knownTerms: ["John Smith"])
        XCTAssertEqual(approvedName.reviewDecisions.first?.learningAction, .addReplacementOnly)
        XCTAssertEqual(approvedName.reviewDecisions.first?.incorrectTextToReplace, "Jhn Smith")
        let incompleteNER = try await reviewer.review(
            [candidate("I met Prakash Joshi Paax today", "I met Prakash Joshi Pax today")], knownTerms: [])
        XCTAssertEqual(incompleteNER.approvalDecisions.first?.incorrectTextToReplace, "Prakash Joshi Paax")
        XCTAssertEqual(incompleteNER.approvalDecisions.first?.correctedVocabularyTerm, "Prakash Joshi Pax")
        for edit in [candidate("Send it form here", "Send it from here"),
                     candidate("I walk home every day", "I walked home every day"),
                     candidate("I met Prakash Joshi Pages", "I met Prakash Joshi Pax"),
                     candidate("Call the project manager", "Call Michael Johnson")] {
            let result = try await reviewer.review([edit], knownTerms: [])
            XCTAssertEqual(result.reviewDecisions.first?.learningAction, .rejectCorrection)
            XCTAssertTrue(result.approvalDecisions.isEmpty)
        }
    }
}

@MainActor
private final class FixtureAnalyzer: AutoLearnLocalTextAnalyzing {
    var spellingAvailable = true
    private let misspelled: Set<String>
    private let suggestions: [String: [String]]
    private let entities: [String: NLTag]

    init(misspelled: Set<String> = [], suggestions: [String: [String]] = [:], entities: [String: NLTag] = [:]) {
        self.misspelled = misspelled
        self.suggestions = suggestions
        self.entities = entities
    }

    func analyze(_ text: String, languageHint: String?) -> AutoLearnLocalTextAnalysis? {
        guard languageHint == "en" else { return nil }
        var tokens: [AutoLearnLocalTextAnalysis.Token] = []
        var search = text.startIndex..<text.endIndex
        for word in text.split(separator: " ").map(String.init) {
            guard let range = text.range(of: word, range: search) else { continue }
            tokens.append(.init(range: NSRange(range, in: text), text: word, lexicalClass: .noun,
                lemma: word == "walked" ? "walk" : word.lowercased()))
            search = range.upperBound..<text.endIndex
        }
        let names = entities.compactMap { term, type -> AutoLearnLocalTextAnalysis.Entity? in
            guard let range = text.range(of: term) else { return nil }
            return .init(range: NSRange(range, in: text), type: type)
        }
        return .init(language: .english, tokens: tokens, entities: names)
    }

    func spelling(for text: String, language: NLLanguage) -> AutoLearnSpellingEvidence? {
        guard spellingAvailable else { return nil }
        return .init(isMisspelled: misspelled.contains(text), suggestions: suggestions[text] ?? [])
    }
}

import SwiftData
import XCTest
@testable import VoiceInk

@MainActor
final class DictionarySmokeTests: XCTestCase {
    func testExistingWordReplacementStillRuns() throws {
        let schema = Schema([WordReplacement.self])
        let configuration = ModelConfiguration("dictionary", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        context.insert(WordReplacement(originalText: "web socket", replacementText: "WebSocket"))
        try context.save()

        let result = WordReplacementService.shared.applyReplacements(
            to: "The web socket is open.", using: context
        )

        XCTAssertEqual(result, "The WebSocket is open.")
    }
    func testAutoLearnAddsUnsectionedTermAlongsideSectionedTermOnlyOnce() async throws {
        let schema = Schema([VocabularyWord.self, VocabularySection.self, WordReplacement.self])
        let configuration = ModelConfiguration("dictionary", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        let section = VocabularySection(name: "Work")
        context.insert(section)
        context.insert(VocabularyWord(word: "VoiceInk", sectionID: section.id))
        try context.save()
        let store = WordReplacementStore(modelContainer: container)
        let candidate = AutoLearnReviewCandidate(
            candidateID: UUID(), originalText: "voice ink", correctedText: "VoiceInk"
        )
        let decision = AutoLearnReviewDecision(
            candidateID: candidate.candidateID,
            learningAction: .addVocabularyOnly,
            incorrectTextToReplace: nil,
            correctedVocabularyTerm: " VOICEINK "
        )

        let first = try await store.apply([decision], candidates: [candidate])
        let repeated = try await store.apply([decision], candidates: [candidate])

        let reader = ModelContext(container)
        let words = try reader.fetch(FetchDescriptor<VocabularyWord>())
        XCTAssertEqual(first.vocabularyCount, 1)
        XCTAssertEqual(repeated.vocabularyCount, 0)
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words.filter { $0.sectionID == nil }.map(\.word), ["VOICEINK"])
        XCTAssertEqual(words.filter { $0.sectionID == section.id }.map(\.word), ["VoiceInk"])
    }

}

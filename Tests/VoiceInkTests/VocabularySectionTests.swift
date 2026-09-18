import SwiftData
import XCTest
@testable import VoiceInk

@MainActor
final class VocabularySectionTests: XCTestCase {
    func testSectionAndWordAssignmentPersist() throws {
        let schema = Schema([VocabularyWord.self, VocabularySection.self])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("dictionary.store")

        do {
            let configuration = ModelConfiguration(
                "dictionary", schema: schema, url: storeURL, cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: configuration)
            let writer = ModelContext(container)
            let section = VocabularySection(name: "Tech Stack", sectionDescription: "Use for technologies")
            writer.insert(section)
            writer.insert(VocabularyWord(word: "SwiftData", sectionID: section.id))
            try writer.save()
        }

        let configuration = ModelConfiguration(
            "dictionary", schema: schema, url: storeURL, cloudKitDatabase: .none
        )
        let reopened = try ModelContainer(for: schema, configurations: configuration)
        let reader = ModelContext(reopened)
        let savedSection = try XCTUnwrap(reader.fetch(FetchDescriptor<VocabularySection>()).first)
        let savedWord = try XCTUnwrap(reader.fetch(FetchDescriptor<VocabularyWord>()).first)
        XCTAssertEqual(savedSection.name, "Tech Stack")
        XCTAssertEqual(savedSection.sectionDescription, "Use for technologies")
        XCTAssertEqual(savedWord.sectionID, savedSection.id)
    }

    func testPromptKeepsDescriptionsWithTheirTerms() {
        let section = VocabularySection(name: "Tech Stack", sectionDescription: "Use when discussing technologies")
        let people = VocabularySection(name: "People")
        let words = [
            VocabularyWord(word: "Luis", sectionID: people.id),
            VocabularyWord(word: "WebSocket", sectionID: section.id),
            VocabularyWord(word: "SwiftData", sectionID: section.id),
            VocabularyWord(word: "VoiceInk"),
        ]

        let prompt = CustomVocabularyService.format(words: words, sections: [section, people])

        XCTAssertEqual(
            prompt,
            "Important Vocabulary:\nOther terms: VoiceInk\nPeople: Luis\nTech Stack — Use when discussing technologies: SwiftData, WebSocket"
        )
    }

    func testUnsectionedVocabularyKeepsExistingPromptFormat() {
        let words = [VocabularyWord(word: "VoiceInk"), VocabularyWord(word: "SwiftData")]

        let prompt = CustomVocabularyService.format(words: words, sections: [])

        XCTAssertEqual(prompt, "Important Vocabulary: SwiftData, VoiceInk")
    }

    func testDictionaryArchiveRestoresSectionDescriptionAndAssignment() async throws {
        let schema = Schema([VocabularyWord.self, WordReplacement.self, VocabularySection.self])
        let configuration = ModelConfiguration("dictionary", schema: schema, isStoredInMemoryOnly: true)
        let source = try ModelContainer(for: schema, configurations: configuration)
        let sourceContext = ModelContext(source)
        let section = VocabularySection(name: "Tech Stack", sectionDescription: "Use for technologies")
        sourceContext.insert(section)
        sourceContext.insert(VocabularyWord(word: "SwiftData", sectionID: section.id))
        try sourceContext.save()

        let archive = try DictionaryImportExportService.makeArchive(modelContext: sourceContext)
        let data = try DictionaryImportExportService.encodeArchive(archive)
        let decoded = try DictionaryImportExportService.decodeArchiveData(data).archive
        let destination = try ModelContainer(for: schema, configurations: configuration)
        let destinationContext = ModelContext(destination)

        _ = try await DictionaryImportExportService.apply(
            archive: decoded, mode: .replace, modelContext: destinationContext
        )

        let savedSection = try XCTUnwrap(destinationContext.fetch(FetchDescriptor<VocabularySection>()).first)
        let savedWord = try XCTUnwrap(destinationContext.fetch(FetchDescriptor<VocabularyWord>()).first)
        XCTAssertEqual(savedSection.sectionDescription, "Use for technologies")
        XCTAssertEqual(savedWord.sectionID, savedSection.id)
    }

    func testVersionOneDictionaryArchiveStillDecodes() throws {
        let json = """
            {"format":"voiceink.dictionary","schemaVersion":1,"exportedAt":"2026-01-01T00:00:00Z",\
            "vocabulary":[{"term":"VoiceInk","createdAt":null}],"replacements":[]}
            """

        let archive = try DictionaryImportExportService.decodeArchiveData(Data(json.utf8)).archive

        XCTAssertTrue(archive.sections.isEmpty)
        XCTAssertNil(archive.vocabulary[0].sectionID)
    }

    func testDeletingSectionLeavesItsWordsUnsectioned() throws {
        let schema = Schema([VocabularyWord.self, VocabularySection.self])
        let configuration = ModelConfiguration("dictionary", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        let section = VocabularySection(name: "Tech Stack", sectionDescription: "Use for technologies")
        let word = VocabularyWord(word: "SwiftData", sectionID: section.id)
        context.insert(section)
        context.insert(word)
        try context.save()

        let error = VocabularySectionService.delete(section, words: [word], context: context)

        XCTAssertNil(error)
        XCTAssertTrue(try context.fetch(FetchDescriptor<VocabularySection>()).isEmpty)
        XCTAssertNil(try XCTUnwrap(context.fetch(FetchDescriptor<VocabularyWord>()).first).sectionID)
    }

    func testSavedSectionAndWordsAppearTogetherInEnhancementVocabulary() throws {
        let schema = Schema([VocabularyWord.self, VocabularySection.self])
        let configuration = ModelConfiguration("dictionary", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        XCTAssertNil(VocabularySectionService.save(
            nil,
            name: "Tech Stack",
            description: "Use when discussing technologies",
            existing: [],
            context: context
        ))
        let section = try XCTUnwrap(context.fetch(FetchDescriptor<VocabularySection>()).first)
        XCTAssertNil(DictionaryService.addVocabularyWords(
            "SwiftData, WebSocket", existing: [], context: context, sectionID: section.id
        ))

        XCTAssertEqual(
            CustomVocabularyService.shared.getCustomVocabulary(from: context),
            "Important Vocabulary:\nTech Stack — Use when discussing technologies: SwiftData, WebSocket"
        )
    }
}

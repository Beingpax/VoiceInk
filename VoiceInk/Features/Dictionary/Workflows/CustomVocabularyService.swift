import Foundation
import SwiftData

class CustomVocabularyService {
    static let shared = CustomVocabularyService()

    private init() {}

    func getCustomVocabulary(from context: ModelContext) -> String {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\VocabularyWord.word)])
        guard let words = try? context.fetch(descriptor), !words.isEmpty else {
            return ""
        }
        let sections = (try? context.fetch(FetchDescriptor<VocabularySection>())) ?? []
        return Self.format(words: words, sections: sections)
    }

    static func format(words: [VocabularyWord], sections: [VocabularySection]) -> String {
        let sortedWords = words.map { ($0.word.trimmingCharacters(in: .whitespacesAndNewlines), $0.sectionID) }
            .filter { !$0.0.isEmpty }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
        guard !sortedWords.isEmpty else { return "" }

        let sectionByID = sections.reduce(into: [UUID: VocabularySection]()) { result, section in
            result[section.id] = section
        }
        let ungrouped = sortedWords.filter { sectionID in
            guard let id = sectionID.1 else { return true }
            return sectionByID[id] == nil
        }.map(\.0)
        let groups = sections.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .compactMap { section -> String? in
                let terms = sortedWords.filter { $0.1 == section.id }.map(\.0)
                guard !terms.isEmpty else { return nil }
                let name = section.name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                let description = section.sectionDescription.split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                let heading = description.isEmpty ? name : "\(name) — \(description)"
                return "\(heading): \(terms.joined(separator: ", "))"
            }

        if groups.isEmpty {
            return escapePromptDelimiters("Important Vocabulary: \(sortedWords.map(\.0).joined(separator: ", "))")
        }
        let ungroupedLine = ungrouped.isEmpty ? [] : ["Other terms: \(ungrouped.joined(separator: ", "))"]
        return escapePromptDelimiters((["Important Vocabulary:"] + ungroupedLine + groups).joined(separator: "\n"))
    }

    private static func escapePromptDelimiters(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

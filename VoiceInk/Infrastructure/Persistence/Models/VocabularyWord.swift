import Foundation
import SwiftData

struct VocabularyWordIdentity: Hashable, Sendable {
    let normalizedWord: String
    let sectionID: UUID?

    init(word: String, sectionID: UUID?) {
        let normalized = word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        normalizedWord = (normalized as NSString).folding(options: .caseInsensitive, locale: nil)
        self.sectionID = sectionID
    }
}

@Model
final class VocabularyWord {
    var word: String = ""
    var dateAdded: Date = Date()
    var sectionID: UUID?

    init(word: String, dateAdded: Date = Date(), sectionID: UUID? = nil) {
        self.word = word
        self.dateAdded = dateAdded
        self.sectionID = sectionID
    }
}

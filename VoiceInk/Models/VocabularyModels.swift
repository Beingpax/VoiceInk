import Foundation
import SwiftData

@Model
final class VocabularyWord {
    @Attribute(.unique) var word: String
    var dateAdded: Date

    init(word: String) {
        self.word = word
        self.dateAdded = Date()
    }
}

@Model
final class WordReplacement {
    var id: UUID
    var originalVariants: String // Comma-separated variants like "Voicing, Voice ink"
    var replacement: String
    var dateAdded: Date

    init(originalVariants: String, replacement: String) {
        self.id = UUID()
        self.originalVariants = originalVariants
        self.replacement = replacement
        self.dateAdded = Date()
    }
}

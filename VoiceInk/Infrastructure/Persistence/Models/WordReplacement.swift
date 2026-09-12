import Foundation
import SwiftData

@Model
final class WordReplacement {
    var id: UUID = UUID()
    var originalText: String = ""
    var replacementText: String = ""
    var dateAdded: Date = Date()
    var isEnabled: Bool = true

    init(originalText: String, replacementText: String, dateAdded: Date = Date()) {
        self.originalText = originalText.precomposedStringWithCanonicalMapping
        self.replacementText = replacementText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        self.dateAdded = dateAdded
        // Keep this persisted field for store and CloudKit compatibility; every rule remains active.
        self.isEnabled = true
    }
}

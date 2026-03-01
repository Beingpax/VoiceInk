import Foundation
import SwiftData

@Model
final class VocabularyWord {
    var word: String = ""
    var dateAdded: Date = Date()
    var phoneticHints: String = ""

    init(word: String, dateAdded: Date = Date(), phoneticHints: String = "") {
        self.word = word
        self.dateAdded = dateAdded
        self.phoneticHints = phoneticHints
    }
}

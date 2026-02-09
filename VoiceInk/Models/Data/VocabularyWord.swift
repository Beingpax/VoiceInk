import Foundation
import SwiftData

@Model
final class VocabularyWord {
    var word: String = ""
    var dateAdded: Date = Date()

    init(word: String, dateAdded: Date = Date()) {
        self.word = word
        self.dateAdded = dateAdded
    }
}

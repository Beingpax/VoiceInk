import Foundation
import SwiftData

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

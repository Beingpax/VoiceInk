import Foundation
import SwiftData

@Model
final class WordReplacement {
    var id: UUID = UUID()
    var originalText: String = ""
    var replacementText: String = ""
    var dateAdded: Date = Date()
    var isEnabled: Bool = true
    var isCaseSensitive: Bool = false
    var isRegex: Bool = false

    init(originalText: String, replacementText: String, dateAdded: Date = Date(), isEnabled: Bool = true, isCaseSensitive: Bool = false, isRegex: Bool = false) {
        self.originalText = originalText
        self.replacementText = replacementText
        self.dateAdded = dateAdded
        self.isEnabled = isEnabled
        self.isCaseSensitive = isCaseSensitive
        self.isRegex = isRegex
    }
}

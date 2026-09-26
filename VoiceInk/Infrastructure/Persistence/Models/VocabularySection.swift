import Foundation
import SwiftData

@Model
final class VocabularySection {
    var id: UUID = UUID()
    var name: String = ""
    var sectionDescription: String = ""

    init(id: UUID = UUID(), name: String, sectionDescription: String = "") {
        self.id = id
        self.name = name
        self.sectionDescription = sectionDescription
    }
}

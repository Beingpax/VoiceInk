import Foundation

struct TextSnippet: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let content: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.content = content
        self.createdAt = createdAt
    }

    var previewText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(Empty)" }
        if trimmed.count <= 80 {
            return trimmed
        }
        let prefix = trimmed.prefix(77)
        return "\(prefix)…"
    }
}

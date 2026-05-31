import Foundation

struct ModeIcon: Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        case symbol
        case emoji
    }

    var kind: Kind
    var value: String

    init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    static func symbol(_ value: String) -> ModeIcon {
        ModeIcon(kind: .symbol, value: value)
    }

    static func emoji(_ value: String) -> ModeIcon {
        ModeIcon(kind: .emoji, value: value)
    }

    static let defaultIcon = ModeIcon.symbol("message.fill")

    static let defaultSymbols: [String] = [
        // Core
        "sparkles",
        "gearshape.fill",

        // Communication
        "envelope.fill",
        "message.fill",
        "bubble.left.and.bubble.right.fill",
        "phone.fill",

        // Work
        "briefcase.fill",
        "building.2.fill",
        "calendar.circle.fill",
        "person.2.fill",

        // Writing
        "doc.text.fill",
        "book.fill",
        "quote.bubble.fill",

        // Technical
        "terminal.fill",
        "wrench.and.screwdriver.fill",

        // Organization
        "folder.fill",
        "tray.full.fill",

        // Business
        "cart.fill",
        "creditcard.fill",
        "banknote.fill",

        // Learning and health
        "lightbulb.fill",
        "graduationcap.fill",
        "heart.fill",

        // Places
        "house.fill",
        "globe.americas.fill",
        "map.fill",
        "airplane",

        // Creative
        "camera.fill",
        "photo.fill",
        "paintpalette.fill",
        "mic.fill",

        // Personal
        "leaf.fill"
    ]

    var legacyEmojiValue: String? {
        kind == .emoji ? value : nil
    }
}

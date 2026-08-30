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

    static let defaultIcon = ModeIcon.symbol("receipt.fill")

    static let defaultSymbols: [String] = [
        "1.calendar",
        "apple.terminal.fill",
        "archivebox.fill",
        "bag.fill",
        "bolt.horizontal.circle.fill",
        "book.pages.fill",
        "briefcase.fill",
        "bubble.left.and.text.bubble.right.fill",
        "building.columns.circle.fill",
        "camera.fill",
        "captions.bubble.fill",
        "character.book.closed.fill",
        "dollarsign.bank.building.fill",
        "envelope.fill",
        "flask.fill",
        "graduationcap.fill",
        "house.fill",
        "keyboard.fill",
        "lightbulb.max.fill",
        "long.text.page.and.pencil.fill",
        "magazine.fill",
        "map.fill",
        "microphone.fill",
        "music.pages",
        "paintbrush.pointed.fill",
        "phone.bubble.fill",
        "photo.fill.on.rectangle.fill",
        "play.rectangle.fill",
        "quote.bubble.fill",
        "receipt.fill",
        "sparkles",
        "star.hexagon.fill",
        "tray.full.fill",
        "tree.fill",
        "wallet.bifold.fill",
    ]

    var legacyEmojiValue: String? {
        kind == .emoji ? value : nil
    }
}

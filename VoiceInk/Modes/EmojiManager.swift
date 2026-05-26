import Foundation

class EmojiManager: ObservableObject {
    static let shared = EmojiManager()
    
    private let defaultEmojis = ["🏢", "🏠", "💼", "🎮", "📱", "📺", "🎵", "📚", "✏️", "🎨", "🧠", "⚙️", "💻", "🌐", "📝", "📊", "🔍", "💬", "📈", "🔧"]
    private let customEmojisKey = "userAddedEmojis"
    
    @Published var customEmojis: [String] = []
    
    private init() {
        loadCustomEmojis()
    }
    
    var allEmojis: [String] {
        return defaultEmojis + customEmojis
    }
    
    func addCustomEmoji(_ emoji: String) -> Bool {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedEmoji.isEmpty, !allEmojis.contains(trimmedEmoji) else {
            return false
        }
        
        customEmojis.append(trimmedEmoji)
        saveCustomEmojis()
        return true
    }
    
    private func loadCustomEmojis() {
        if let savedEmojis = UserDefaults.standard.array(forKey: customEmojisKey) as? [String] {
            customEmojis = savedEmojis
        }
    }
    
    private func saveCustomEmojis() {
        UserDefaults.standard.set(customEmojis, forKey: customEmojisKey)
    }
    
    func removeCustomEmoji(_ emoji: String) -> Bool {
        if let index = customEmojis.firstIndex(of: emoji) {
            customEmojis.remove(at: index)
            saveCustomEmojis()
            return true
        }
        return false
    }
    
    func isCustomEmoji(_ emoji: String) -> Bool {
        return customEmojis.contains(emoji)
    }
}
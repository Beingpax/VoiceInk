import Foundation
import Combine

struct DailyScratchpad: Codable, Identifiable, Equatable {
    let id: UUID
    let date: String
    var content: String
    var lastModified: Date
    var entryCount: Int
    
    init(id: UUID = UUID(), date: String, content: String, lastModified: Date = Date(), entryCount: Int = 0) {
        self.id = id
        self.date = date
        self.content = content
        self.lastModified = lastModified
        self.entryCount = entryCount
    }
    
    var previewText: String {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanContent.isEmpty {
            return "No entries yet"
        }
        let preview = String(cleanContent.prefix(100))
        return preview + (cleanContent.count > 100 ? "..." : "")
    }
    
    var isToday: Bool {
        date == Self.todayString
    }
    
    static var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

extension Notification.Name {
    static let scratchpadEntryAdded = Notification.Name("scratchpadEntryAdded")
}

@MainActor
class DailyScratchpadManager: ObservableObject {
    @Published var scratchpads: [DailyScratchpad] = []
    @Published var currentViewDate: String? = nil
    
    private let userDefaults = UserDefaults.standard
    private let storageKey = "dailyScratchpads"
    
    init() {
        loadScratchpads()
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScratchpadEntry),
            name: .scratchpadEntryAdded,
            object: nil
        )
    }
    
    @objc private func handleScratchpadEntry(_ notification: Notification) {
        guard let entryText = notification.userInfo?["entry"] as? String else { return }
        addEntryToToday(entryText)
    }
    
    func addEntryToToday(_ text: String) {
        let today = DailyScratchpad.todayString
        
        if let index = scratchpads.firstIndex(where: { $0.date == today }) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timestamp = formatter.string(from: Date())
            
            let newEntry = scratchpads[index].content.isEmpty ? 
                "\(timestamp) - \(text)" : 
                "\n\n\(timestamp) - \(text)"
            
            scratchpads[index].content += newEntry
            scratchpads[index].lastModified = Date()
            scratchpads[index].entryCount += 1
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timestamp = formatter.string(from: Date())
            
            let newScratchpad = DailyScratchpad(
                date: today,
                content: "\(timestamp) - \(text)",
                lastModified: Date(),
                entryCount: 1
            )
            scratchpads.insert(newScratchpad, at: 0)
        }
        
        saveScratchpads()
    }
    
    func getScratchpad(for date: String) -> DailyScratchpad? {
        return scratchpads.first(where: { $0.date == date })
    }
    
    func getOrCreateScratchpad(for date: String) -> DailyScratchpad {
        if let existing = getScratchpad(for: date) {
            return existing
        }
        
        let newScratchpad = DailyScratchpad(date: date, content: "", lastModified: Date(), entryCount: 0)
        scratchpads.append(newScratchpad)
        scratchpads.sort { $0.date > $1.date }
        saveScratchpads()
        return newScratchpad
    }
    
    func updateScratchpad(_ scratchpad: DailyScratchpad, content: String) {
        guard let index = scratchpads.firstIndex(where: { $0.id == scratchpad.id }) else { return }
        scratchpads[index].content = content
        scratchpads[index].lastModified = Date()
        saveScratchpads()
    }
    
    func deleteScratchpad(_ scratchpad: DailyScratchpad) {
        scratchpads.removeAll { $0.id == scratchpad.id }
        saveScratchpads()
    }
    
    func setCurrentViewDate(_ date: String?) {
        currentViewDate = date
        userDefaults.set(date, forKey: "currentScratchpadViewDate")
    }
    
    func restoreLastView() {
        currentViewDate = userDefaults.string(forKey: "currentScratchpadViewDate")
    }
    
    private func loadScratchpads() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DailyScratchpad].self, from: data) else {
            return
        }
        scratchpads = decoded.sorted { $0.date > $1.date }
    }
    
    private func saveScratchpads() {
        guard let encoded = try? JSONEncoder().encode(scratchpads) else { return }
        userDefaults.set(encoded, forKey: storageKey)
    }
}
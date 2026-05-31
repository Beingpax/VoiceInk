import Foundation

/// A named profile that stores activation shortcut configurations.
/// Each profile captures the primary/secondary shortcut selections, their modes,
/// and the actual custom shortcut data, allowing users to quickly switch between
/// different shortcut configurations.
struct ShortcutProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var primarySelection: String // ShortcutSelection rawValue: "none" or "custom"
    var secondarySelection: String
    var primaryMode: String // Mode rawValue: "toggle", "pushToTalk", "hybrid"
    var secondaryMode: String
    var primaryShortcutData: Data? // Encoded Shortcut for primary
    var secondaryShortcutData: Data? // Encoded Shortcut for secondary

    init(
        id: UUID = UUID(),
        name: String,
        primarySelection: String = "custom",
        secondarySelection: String = "none",
        primaryMode: String = "hybrid",
        secondaryMode: String = "hybrid",
        primaryShortcutData: Data? = nil,
        secondaryShortcutData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.primarySelection = primarySelection
        self.secondarySelection = secondarySelection
        self.primaryMode = primaryMode
        self.secondaryMode = secondaryMode
        self.primaryShortcutData = primaryShortcutData
        self.secondaryShortcutData = secondaryShortcutData
    }

    /// Create a profile from the current RecordingShortcutManager state
    @MainActor
    static func fromCurrentState(
        name: String,
        manager: RecordingShortcutManager
    ) -> ShortcutProfile {
        let primaryData: Data? = ShortcutStore.shortcut(for: .primaryRecording)
            .flatMap { try? JSONEncoder().encode($0) }
        let secondaryData: Data? = ShortcutStore.shortcut(for: .secondaryRecording)
            .flatMap { try? JSONEncoder().encode($0) }

        return ShortcutProfile(
            name: name,
            primarySelection: manager.primaryRecordingShortcut.rawValue,
            secondarySelection: manager.secondaryRecordingShortcut.rawValue,
            primaryMode: manager.primaryRecordingShortcutMode.rawValue,
            secondaryMode: manager.secondaryRecordingShortcutMode.rawValue,
            primaryShortcutData: primaryData,
            secondaryShortcutData: secondaryData
        )
    }
}

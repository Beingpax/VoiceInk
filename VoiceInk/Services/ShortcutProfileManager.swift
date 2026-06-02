import Foundation
import Combine

/// Manages shortcut profiles: persistence, switching, CRUD operations.
/// Works with RecordingShortcutManager to apply profile configurations.
@MainActor
class ShortcutProfileManager: ObservableObject {
    @Published private(set) var profiles: [ShortcutProfile] = []
    @Published var activeProfileID: UUID?
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    private static let storageKey = "shortcutProfiles"
    private static let activeProfileKey = "shortcutProfileActiveID"
    private static let enabledKey = "shortcutProfilesEnabled"

    private weak var recordingShortcutManager: RecordingShortcutManager?

    var activeProfile: ShortcutProfile? {
        profiles.first { $0.id == activeProfileID } ?? profiles.first
    }

    var activeProfileName: String {
        activeProfile?.name ?? "Default"
    }

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        loadProfiles()
    }

    func setRecordingShortcutManager(_ manager: RecordingShortcutManager) {
        self.recordingShortcutManager = manager
    }

    // MARK: - Persistence

    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ShortcutProfile].self, from: data) {
            profiles = decoded
        }

        if let idString = UserDefaults.standard.string(forKey: Self.activeProfileKey),
           let id = UUID(uuidString: idString) {
            activeProfileID = id
        } else {
            activeProfileID = profiles.first?.id
        }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        if let id = activeProfileID {
            UserDefaults.standard.set(id.uuidString, forKey: Self.activeProfileKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeProfileKey)
        }
    }

    // MARK: - Profile Operations

    func createProfileFromCurrent(name: String? = nil) {
        guard let manager = recordingShortcutManager else { return }

        let profileName = uniqueName(for: name ?? "New Profile")
        let profile = ShortcutProfile.fromCurrentState(name: profileName, manager: manager)

        profiles.append(profile)
        activeProfileID = profile.id
        saveProfiles()
    }

    func duplicateProfile(_ profile: ShortcutProfile) {
        var duplicate = profile
        duplicate.id = UUID()
        duplicate.name = uniqueName(for: "\(profile.name) Copy")

        profiles.append(duplicate)
        activeProfileID = duplicate.id
        saveProfiles()
    }

    func deleteProfile(id: UUID) {
        guard profiles.count > 1 else { return }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        let wasActive = activeProfileID == id
        profiles.remove(at: index)

        if wasActive {
            let fallback = index < profiles.count ? profiles[index] : profiles.last
            activeProfileID = fallback?.id
            if isEnabled, let fallback {
                applyProfile(fallback)
            }
        }

        saveProfiles()
    }

    func renameProfile(id: UUID, to newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        profiles[index].name = uniqueName(for: trimmed, excluding: id)
        saveProfiles()
    }

    func switchToProfile(id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        activeProfileID = profile.id
        saveProfiles()

        if isEnabled {
            applyProfile(profile)
        }
    }

    /// Save the current shortcut state into the active profile
    func saveCurrentStateToActiveProfile() {
        guard let manager = recordingShortcutManager,
              let activeID = activeProfileID,
              let index = profiles.firstIndex(where: { $0.id == activeID }) else { return }

        let primaryData: Data? = ShortcutStore.shortcut(for: .primaryRecording)
            .flatMap { try? JSONEncoder().encode($0) }
        let secondaryData: Data? = ShortcutStore.shortcut(for: .secondaryRecording)
            .flatMap { try? JSONEncoder().encode($0) }

        profiles[index].primarySelection = manager.primaryRecordingShortcut.rawValue
        profiles[index].secondarySelection = manager.secondaryRecordingShortcut.rawValue
        profiles[index].primaryMode = manager.primaryRecordingShortcutMode.rawValue
        profiles[index].secondaryMode = manager.secondaryRecordingShortcutMode.rawValue
        profiles[index].primaryShortcutData = primaryData
        profiles[index].secondaryShortcutData = secondaryData

        saveProfiles()
    }

    // MARK: - Apply Profile

    func applyProfile(_ profile: ShortcutProfile) {
        guard let manager = recordingShortcutManager else { return }

        // Apply shortcut data to ShortcutStore
        if let data = profile.primaryShortcutData,
           let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) {
            ShortcutStore.setShortcut(shortcut, for: .primaryRecording)
        } else {
            ShortcutStore.setShortcut(nil, for: .primaryRecording)
        }

        if let data = profile.secondaryShortcutData,
           let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) {
            ShortcutStore.setShortcut(shortcut, for: .secondaryRecording)
        } else {
            ShortcutStore.setShortcut(nil, for: .secondaryRecording)
        }

        // Apply selection and mode
        let primarySelection = RecordingShortcutManager.ShortcutSelection(rawValue: profile.primarySelection) ?? .custom
        let secondarySelection = RecordingShortcutManager.ShortcutSelection(rawValue: profile.secondarySelection) ?? .none
        let primaryMode = RecordingShortcutManager.Mode(rawValue: profile.primaryMode) ?? .hybrid
        let secondaryMode = RecordingShortcutManager.Mode(rawValue: profile.secondaryMode) ?? .hybrid

        manager.primaryRecordingShortcut = primarySelection
        manager.secondaryRecordingShortcut = secondarySelection
        manager.primaryRecordingShortcutMode = primaryMode
        manager.secondaryRecordingShortcutMode = secondaryMode
    }

    // MARK: - Helpers

    private func uniqueName(for base: String, excluding: UUID? = nil) -> String {
        let existingNames = Set(
            profiles
                .filter { $0.id != excluding }
                .map { $0.name.lowercased() }
        )

        var candidate = base
        var suffix = 2
        while existingNames.contains(candidate.lowercased()) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }
}

import SwiftUI

struct ShortcutProfilesSettingsView: View {
    @EnvironmentObject var shortcutProfileManager: ShortcutProfileManager
    @State private var editingProfileID: UUID?
    @State private var editingName: String = ""
    @State private var showingDeleteConfirmation: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Shortcut Profiles")
                    .font(.headline)
                Spacer()
                Toggle("Enable", isOn: $shortcutProfileManager.isEnabled)
                    .toggleStyle(.switch)
            }

            if shortcutProfileManager.isEnabled {
                Text("Create named profiles to quickly switch between different shortcut configurations.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                profileList

                HStack {
                    Button("Create Profile from Current") {
                        shortcutProfileManager.createProfileFromCurrent()
                    }

                    if let active = shortcutProfileManager.activeProfile {
                        Button("Duplicate Active") {
                            shortcutProfileManager.duplicateProfile(active)
                        }
                    }

                    Spacer()

                    Button("Save Current to Active Profile") {
                        shortcutProfileManager.saveCurrentStateToActiveProfile()
                    }
                    .disabled(shortcutProfileManager.activeProfile == nil)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private var profileList: some View {
        if shortcutProfileManager.profiles.isEmpty {
            Text("No profiles yet. Create one to get started.")
                .foregroundColor(.secondary)
                .italic()
                .padding(.vertical, 8)
        } else {
            List {
                ForEach(shortcutProfileManager.profiles) { profile in
                    HStack {
                        if editingProfileID == profile.id {
                            TextField("Profile Name", text: $editingName, onCommit: {
                                shortcutProfileManager.renameProfile(id: profile.id, to: editingName)
                                editingProfileID = nil
                            })
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)

                            Button("Done") {
                                shortcutProfileManager.renameProfile(id: profile.id, to: editingName)
                                editingProfileID = nil
                            }
                        } else {
                            HStack(spacing: 8) {
                                if profile.id == shortcutProfileManager.activeProfileID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                                Text(profile.name)
                                    .fontWeight(profile.id == shortcutProfileManager.activeProfileID ? .semibold : .regular)
                            }

                            Spacer()

                            Button("Switch") {
                                shortcutProfileManager.switchToProfile(id: profile.id)
                            }
                            .disabled(profile.id == shortcutProfileManager.activeProfileID)

                            Button("Rename") {
                                editingProfileID = profile.id
                                editingName = profile.name
                            }

                            Button("Delete") {
                                shortcutProfileManager.deleteProfile(id: profile.id)
                            }
                            .disabled(shortcutProfileManager.profiles.count <= 1)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 120, maxHeight: 250)
        }
    }
}

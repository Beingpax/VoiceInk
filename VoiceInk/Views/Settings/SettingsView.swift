import SwiftUI
import Cocoa
import KeyboardShortcuts
import LaunchAtLogin
import AVFoundation

// MARK: - Settings View

/// Main settings view for the application.
/// Component views are organized in extension files:
/// - SettingsView+Types.swift - SearchableSetting, SettingsTab enum, Text extension
/// - SettingsView+General.swift - General settings tab
/// - SettingsView+Audio.swift - Audio settings tab
/// - SettingsView+Transcription.swift - Transcription settings tab
/// - SettingsView+Shortcuts.swift - Shortcuts settings tab
/// - SettingsView+Data.swift - Data settings tab
/// - SettingsView+Navigation.swift - SettingsNavigationRail, SettingsRailItem

struct SettingsView: View {
    // Environment objects - internal access for extension files
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var whisperState: WhisperState
    @EnvironmentObject var enhancementService: AIEnhancementService
    @StateObject var deviceManager = AudioDeviceManager.shared
    @ObservedObject var soundManager = SoundManager.shared
    @ObservedObject var mediaController = MediaController.shared
    @ObservedObject var playbackController = PlaybackController.shared
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = true
    @AppStorage("autoUpdateCheck") var autoUpdateCheck = true
    @AppStorage("enableAnnouncements") var enableAnnouncements = true
    @State var showResetOnboardingAlert = false
    @State var currentShortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)
    @State var isCustomCancelEnabled = false
    @State var isCustomSoundsExpanded = false
    @State var selectedTab: SettingsTab = .general
    @State var showTrashView = false
    @State var trashItemCount: Int = 0
    @State var showLicenseSheet = false
    @State var showDictionarySheet = false
    @State var searchText: String = ""
    
    // Store the passed tab to detect changes from parent
    private let requestedTab: SettingsTab
    
    // Searchable settings definitions
    var searchableSettings: [SearchableSetting] {
        var settings = [
            // General
            SearchableSetting(tab: .general, section: "App Behavior", keywords: ["dock", "icon", "menu bar", "launch", "login", "startup", "update", "automatic", "announcements", "onboarding", "reset"]),
            SearchableSetting(tab: .general, section: "Community & License", keywords: ["license", "community", "edition", "open source", "privacy"]),
            
            // Audio
            SearchableSetting(tab: .audio, section: "Audio Input", keywords: ["microphone", "mic", "input", "device", "audio input"]),
            SearchableSetting(tab: .audio, section: "Audio Feedback", keywords: ["sound", "feedback", "volume", "recording sound", "beep", "notification"]),
            SearchableSetting(tab: .audio, section: "Recording Behavior", keywords: ["mute", "system audio", "recording", "behavior"]),
            
            // Transcription
            SearchableSetting(tab: .transcription, section: "Dictionary", keywords: ["dictionary", "words", "phrases", "quick rules", "replacement", "spelling", "custom words"]),
            SearchableSetting(tab: .transcription, section: "Clipboard & Paste", keywords: ["clipboard", "paste", "copy", "transcript", "applescript"]),
            SearchableSetting(tab: .transcription, section: "Recorder Style", keywords: ["recorder", "style", "notch", "mini", "interface"]),
            SearchableSetting(tab: .transcription, section: "Power Mode", keywords: ["power mode", "context", "app", "browser", "url", "automatic"]),
            SearchableSetting(tab: .transcription, section: "Experimental", keywords: ["experimental", "beta", "features"]),
            
            // Shortcuts
            SearchableSetting(tab: .shortcuts, section: "VoiceInk Shortcuts", keywords: ["hotkey", "shortcut", "keyboard", "trigger", "option", "command", "push to talk", "hands-free"]),
            SearchableSetting(tab: .shortcuts, section: "Other App Shortcuts", keywords: ["paste last", "transcript", "enhanced", "retry", "cancel", "middle click", "mouse"]),
            
            // AI
            SearchableSetting(tab: .enhancement, section: "AI Enhancement", keywords: ["ai", "enhancement", "llm", "openai", "anthropic", "google", "ollama", "local", "model", "token", "prompt", "persona"]),
            SearchableSetting(tab: .enhancement, section: "Cloud Sync", keywords: ["icloud", "sync", "cloud", "backup", "restore", "devices"]),
            
            // Data
            SearchableSetting(tab: .data, section: "Trash", keywords: ["trash", "deleted", "recover", "restore", "transcriptions"]),
            SearchableSetting(tab: .data, section: "Data & Privacy", keywords: ["privacy", "data", "cleanup", "storage", "history", "delete"]),
            SearchableSetting(tab: .data, section: "Data Management", keywords: ["import", "export", "backup", "settings", "prompts", "preferences"]),
            
            // Permissions
            SearchableSetting(tab: .permissions, section: "Permissions", keywords: ["permissions", "accessibility", "microphone", "access", "privacy", "security"]),
        ]
        
        #if DEBUG
        settings.append(SearchableSetting(tab: .general, section: "Performance Metrics", keywords: ["performance", "metrics", "metrickit", "cpu", "memory", "hang", "debug", "monitoring"]))
        #endif
        
        return settings
    }
    
    func matchesSearch(_ setting: SearchableSetting) -> Bool {
        guard !searchText.isEmpty else { return true }
        let query = searchText.lowercased()
        return setting.section.lowercased().contains(query) ||
               setting.keywords.contains { $0.lowercased().contains(query) }
    }
    
    func tabHasMatches(_ tab: SettingsTab) -> Bool {
        guard !searchText.isEmpty else { return true }
        return searchableSettings.filter { $0.tab == tab }.contains { matchesSearch($0) }
    }
    
    func sectionMatches(_ sectionTitle: String, in tab: SettingsTab) -> Bool {
        guard !searchText.isEmpty else { return true }
        return searchableSettings.first { $0.tab == tab && $0.section == sectionTitle }.map { matchesSearch($0) } ?? false
    }

    init(selectedTab: SettingsTab = .general) {
        self.requestedTab = selectedTab
        _selectedTab = State(initialValue: selectedTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Navigation Rail
            SettingsNavigationRail(
                tabs: SettingsTab.allCases,
                selectedTab: $selectedTab,
                searchText: $searchText,
                tabHasMatches: tabHasMatches,
                onSelect: { tab in
                    selectedTab = tab
                }
            )
            .frame(width: 220)
            .background(VoiceInkTheme.Palette.surface)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(VoiceInkTheme.Palette.outline),
                alignment: .trailing
            )
            
            // Main Content Area
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: VoiceInkSpacing.lg) {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 24, weight: .bold))
                        .padding(.bottom, VoiceInkSpacing.sm)
                    
                    settingsContent(for: selectedTab)
                }
                .padding(VoiceInkSpacing.xl)
                .frame(maxWidth: 800, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(VoiceInkTheme.Palette.canvas)
        }
        .navigationTitle("Settings")
        .onChange(of: requestedTab) { _, newTab in
            selectedTab = newTab
        }
        .onAppear {
            isCustomCancelEnabled = KeyboardShortcuts.getShortcut(for: .cancelRecorder) != nil
        }
        .alert("Reset Onboarding", isPresented: $showResetOnboardingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                DispatchQueue.main.async {
                    hasCompletedOnboarding = false
                }
            }
        } message: {
            Text("Are you sure you want to reset the onboarding? You'll see the introduction screens again the next time you launch the app.")
        }
        .sheet(isPresented: $showTrashView) {
            TrashView(modelContext: whisperState.modelContext)
                .onDisappear {
                    updateTrashCount()
                }
        }
        .sheet(isPresented: $showLicenseSheet) {
            LicenseManagementView()
                .frame(minWidth: 600, minHeight: 500)
        }
        .sheet(isPresented: $showDictionarySheet) {
            DictionarySettingsView(whisperPrompt: whisperState.whisperPrompt)
                .frame(minWidth: 700, minHeight: 500)
                .padding()
        }
    }
    
    func updateTrashCount() {
        trashItemCount = TrashCleanupService.shared.getTrashCount(modelContext: whisperState.modelContext)
    }
    
    @ViewBuilder
    private func settingsContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: generalSettings
        case .audio: audioSettings
        case .transcription: transcriptionSettings
        case .shortcuts: shortcutsSettings
        case .enhancement: EnhancementSettingsView()
        case .data: dataSettings
        case .permissions: PermissionsView().voiceInkSectionPadding()
        }
    }
}

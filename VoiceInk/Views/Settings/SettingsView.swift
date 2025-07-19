import SwiftUI
import Cocoa
import KeyboardShortcuts
import LaunchAtLogin
import AVFoundation
// Additional imports for Settings components

struct SettingsView: View {
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @StateObject private var deviceManager = AudioDeviceManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var showResetOnboardingAlert = false
    @State private var currentShortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)
    @State private var isCustomCancelEnabled = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hotkey Selection Section
                SettingsSection(
                    icon: "command.circle",
                    title: "VoiceInk Shortcut",
                    subtitle: "Choose how you want to trigger VoiceInk"
                ) {
                    VStack(alignment: .leading, spacing: 18) {
                        hotkeyView(
                            title: "Hotkey 1",
                            binding: $hotkeyManager.selectedHotkey1,
                            shortcutName: .toggleMiniRecorder
                        )

                        // Hotkey 2 Configuration (Conditional)
                        if hotkeyManager.selectedHotkey2 != .none {
                            Divider()
                            hotkeyView(
                                title: "Hotkey 2",
                                binding: $hotkeyManager.selectedHotkey2,
                                shortcutName: .toggleMiniRecorder2,
                                isRemovable: true,
                                onRemove: {
                                    withAnimation { hotkeyManager.selectedHotkey2 = .none }
                                }
                            )
                        }

                        // "Add another hotkey" button
                        if hotkeyManager.selectedHotkey1 != .none && hotkeyManager.selectedHotkey2 == .none {
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation { hotkeyManager.selectedHotkey2 = .rightOption }
                                }) {
                                    Label("Add another hotkey", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                        }

                        Text("Quick tap to start hands-free recording (tap again to stop). Press and hold for push-to-talk (release to stop recording).")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        // Cancel Recording Override Toggle
                        Toggle(isOn: $isCustomCancelEnabled) {
                            Text("Override default double-tap Escape cancellation")
                        }
                        .toggleStyle(.switch)
                        .onChange(of: isCustomCancelEnabled) { _, newValue in
                            if !newValue {
                                KeyboardShortcuts.setShortcut(nil, for: .cancelRecorder)
                            }
                        }
                        
                        // Show shortcut recorder only when override is enabled
                        if isCustomCancelEnabled {
                            HStack(spacing: 12) {
                                Text("Custom Cancel Shortcut")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                KeyboardShortcuts.Recorder(for: .cancelRecorder)
                                    .controlSize(.small)
                                
                                Spacer()
                            }
                            .padding(.leading, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Text("By default, double-tap Escape to cancel recordings. Enable override above for single-press custom cancellation (useful for Vim users).")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                }

                // Recording Feedback Section
                SettingsSection(
                    icon: "speaker.wave.2.bubble.left.fill",
                    title: "Recording Feedback",
                    subtitle: "Customize app & system feedback"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $whisperState.isAutoCopyEnabled) {
                            Text("Auto-copy to clipboard")
                        }
                        .toggleStyle(.switch)

                        Toggle(isOn: .init(
                            get: { SoundManager.shared.isEnabled },
                            set: { SoundManager.shared.isEnabled = $0 }
                        )) {
                            Text("Sound feedback")
                        }
                        .toggleStyle(.switch)

                        Toggle(isOn: $mediaController.isSystemMuteEnabled) {
                            Text("Mute system audio during recording")
                        }
                        .toggleStyle(.switch)
                        .help("Automatically mute system audio when recording starts and restore when recording stops")
                        
                        HStack {
                            Toggle("Auto-send after hold-to-record", isOn: $whisperState.isHoldToRecordAutoSendEnabled)
                            
                            InfoTip(
                                title: "Auto-send for Hold-to-Record",
                                message: "When enabled, transcribed text will be sent automatically (Enter key pressed) after releasing the key in continuous hold mode. This does not affect toggle recording mode."
                            )
                            
                            Spacer()
                        }
                        .help("Automatically press Enter after transcription when using continuous hold-to-record mode")
                    }
                }

                // Recorder Preference Section
                SettingsSection(
                    icon: "rectangle.on.rectangle",
                    title: "Recorder Style",
                    subtitle: "Choose your preferred recorder interface"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select how you want the recorder to appear on your screen.")
                            .settingsDescription()
                        
                        Picker("Recorder Style", selection: $whisperState.recorderType) {
                            Text("Notch Recorder").tag("notch")
                            Text("Mini Recorder").tag("mini")
                        }
                        .pickerStyle(.radioGroup)
                        .padding(.vertical, 4)
                    }
                }

                // Paste Method Section
                SettingsSection(
                    icon: "doc.on.clipboard",
                    title: "Paste Method",
                    subtitle: "Choose how text is pasted"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select the method used to paste text. Use AppleScript if you have a non-standard keyboard layout.")
                            .settingsDescription()
                        
                        Toggle("Use AppleScript Paste Method", isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "UseAppleScriptPaste") },
                            set: { UserDefaults.standard.set($0, forKey: "UseAppleScriptPaste") }
                        ))
                        .toggleStyle(.switch)
                    }
                }

                // App Appearance Section
                SettingsSection(
                    icon: "dock.rectangle",
                    title: "App Appearance",
                    subtitle: "Dock and Menu Bar options"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose how VoiceInk appears in your system.")
                            .settingsDescription()
                        
                        Toggle("Hide Dock Icon (Menu Bar Only)", isOn: $menuBarManager.isMenuBarOnly)
                            .toggleStyle(.switch)
                    }
                }

                // Audio Cleanup Section
                SettingsSection(
                    icon: "trash.circle",
                    title: "Audio Cleanup",
                    subtitle: "Manage recording storage"
                ) {
                    AudioCleanupSettingsView()
                }
                
                // Startup Section
                SettingsSection(
                    icon: "power",
                    title: "Startup",
                    subtitle: "Launch options"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose whether VoiceInk should start automatically when you log in.")
                            .settingsDescription()
                        
                        LaunchAtLogin.Toggle()
                            .toggleStyle(.switch)
                    }
                }
                
                // Updates Section
                SettingsSection(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Updates",
                    subtitle: "Keep VoiceInk up to date"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VoiceInk automatically checks for updates on launch and every other day.")
                            .settingsDescription()
                        
                        Button("Check for Updates Now") {
                            updaterViewModel.checkForUpdates()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!updaterViewModel.canCheckForUpdates)
                    }
                }

                // Reset Onboarding Section
                SettingsSection(
                    icon: "arrow.counterclockwise",
                    title: "Reset Onboarding",
                    subtitle: "View the introduction again"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reset the onboarding process to view the app introduction again.")
                            .settingsDescription()
                        
                        Button("Reset Onboarding") {
                            showResetOnboardingAlert = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }

                // Data Management Section
                SettingsSection(
                    icon: "arrow.up.arrow.down.circle",
                    title: "Data Management",
                    subtitle: "Import or export your settings"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export your custom prompts, power modes, word replacements, keyboard shortcuts, and app preferences to a backup file. API keys are not included in the export.")
                            .settingsDescription()

                        HStack(spacing: 12) {
                            Button {
                                ImportExportService.shared.importSettings(
                                    enhancementService: enhancementService, 
                                    whisperPrompt: whisperState.whisperPrompt, 
                                    hotkeyManager: hotkeyManager, 
                                    menuBarManager: menuBarManager, 
                                    mediaController: MediaController.shared, 
                                    soundManager: SoundManager.shared,
                                    whisperState: whisperState
                                )
                            } label: {
                                Label("Import Settings...", systemImage: "arrow.down.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)

                            Button {
                                ImportExportService.shared.exportSettings(
                                    enhancementService: enhancementService, 
                                    whisperPrompt: whisperState.whisperPrompt, 
                                    hotkeyManager: hotkeyManager, 
                                    menuBarManager: menuBarManager, 
                                    mediaController: MediaController.shared, 
                                    soundManager: SoundManager.shared,
                                    whisperState: whisperState
                                )
                            } label: {
                                Label("Export Settings...", systemImage: "arrow.up.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            // Initialize custom cancel shortcut state from stored preferences
            isCustomCancelEnabled = KeyboardShortcuts.getShortcut(for: .cancelRecorder) != nil
        }
        .alert("Reset Onboarding", isPresented: $showResetOnboardingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                // Defer state change to avoid layout issues while alert dismisses
                DispatchQueue.main.async {
                    hasCompletedOnboarding = false
                }
            }
        } message: {
            Text("Are you sure you want to reset the onboarding? You'll see the introduction screens again the next time you launch the app.")
        }
    }
    
    @ViewBuilder
    private func hotkeyView(
        title: String,
        binding: Binding<HotkeyManager.HotkeyOption>,
        shortcutName: KeyboardShortcuts.Name,
        isRemovable: Bool = false,
        onRemove: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            Menu {
                ForEach(HotkeyManager.HotkeyOption.allCases, id: \.self) { option in
                    Button(action: {
                        binding.wrappedValue = option
                    }) {
                        HStack {
                            Text(option.displayName)
                            if binding.wrappedValue == option {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(binding.wrappedValue.displayName)
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            
            if binding.wrappedValue == .custom {
                KeyboardShortcuts.Recorder(for: shortcutName)
                    .controlSize(.small)
            }
            
            Spacer()
            
            if isRemovable {
                Button(action: {
                    onRemove?()
                }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let content: Content
    var showWarning: Bool = false
    
    init(icon: String, title: String, subtitle: String, showWarning: Bool = false, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.showWarning = showWarning
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(showWarning ? .red : .accentColor)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(showWarning ? .red : .secondary)
                }
                
                if showWarning {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .help("Permission required for VoiceInk to function properly")
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: showWarning, useAccentGradientWhenSelected: true))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(showWarning ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
}

// Add this extension for consistent description text styling
extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}



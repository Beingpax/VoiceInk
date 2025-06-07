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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var showResetOnboardingAlert = false
    @State private var currentShortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Keyboard Shortcuts Section first
                SettingsSection(
                    icon: currentShortcut != nil ? "keyboard" : "keyboard.badge.exclamationmark",
                    title: "Keyboard Shortcuts",
                    subtitle: currentShortcut != nil ? "Shortcut configured" : "Shortcut required",
                    showWarning: currentShortcut == nil
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        if currentShortcut == nil {
                            Text("⚠️ Please set a keyboard shortcut to use VoiceInk")
                                .foregroundColor(.orange)
                                .font(.subheadline)
                        }
                        
                        HStack(alignment: .center, spacing: 16) {
                            if let shortcut = currentShortcut {
                                KeyboardShortcutView(shortcut: shortcut)
                            } else {
                                Text("Not Set")
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                            
                            Button(action: {
                                KeyboardShortcuts.reset(.toggleMiniRecorder)
                                currentShortcut = nil
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Reset Shortcut")
                        }
                        
                        KeyboardShortcuts.Recorder("Change Shortcut:", name: .toggleMiniRecorder) { newShortcut in
                            currentShortcut = newShortcut
                            hotkeyManager.updateShortcutStatus()
                        }
                        .controlSize(.large)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Enable Push-to-Talk", isOn: $hotkeyManager.isPushToTalkEnabled)
                                .toggleStyle(.switch)
                            
                            if hotkeyManager.isPushToTalkEnabled {
                                if currentShortcut == nil {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("Please set a keyboard shortcut first to use Push-to-Talk")
                                            .settingsDescription()
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.vertical, 4)
                                }
                            
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Choose Push-to-Talk Key")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                    
                                    PushToTalkKeySelector(selectedKey: $hotkeyManager.pushToTalkKey)
                                        .padding(.vertical, 4)
                                    
                                    Text("Quick tap the key once to start hands-free recording (tap again to stop).\nPress and hold the key for push-to-talk (release to stop recording).")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
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
                
                // Audio Cleanup Section
                SettingsSection(
                    icon: "trash.circle",
                    title: "Audio Cleanup",
                    subtitle: "Manage recording storage"
                ) {
                    AudioCleanupSettingsView()
                }

                // Cloud Transcription Settings Section
                SettingsSection(
                    icon: "icloud.and.arrow.up", // Example icon
                    title: "Cloud Transcription",
                    subtitle: "Configure cloud API key"
                ) {
                    NavigationLink(destination: CloudServiceSettingsView()) {
                        Text("Configure API Key")
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .alert("Reset Onboarding", isPresented: $showResetOnboardingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                hasCompletedOnboarding = false
            }
        } message: {
            Text("Are you sure you want to reset the onboarding? You'll see the introduction screens again the next time you launch the app.")
        }
    }
    
    private func getPushToTalkDescription() -> String {
        switch hotkeyManager.pushToTalkKey {
        case .rightOption:
            return "Using Right Option (⌥) key to quickly start recording. Release to stop."
        case .leftOption:
            return "Using Left Option (⌥) key to quickly start recording. Release to stop."
        case .leftControl:
            return "Using Left Control (⌃) key to quickly start recording. Release to stop."
        case .rightControl:
            return "Using Right Control (⌃) key to quickly start recording. Release to stop."
        case .fn:
            return "Using Function (Fn) key to quickly start recording. Release to stop."
        case .rightCommand:
            return "Using Right Command (⌘) key to quickly start recording. Release to stop."
        case .rightShift:
            return "Using Right Shift (⇧) key to quickly start recording. Release to stop."
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
        )
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

struct PushToTalkKeySelector: View {
    @Binding var selectedKey: HotkeyManager.PushToTalkKey
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(HotkeyManager.PushToTalkKey.allCases, id: \.self) { key in
                Button(action: {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        selectedKey = key
                    }
                }) {
                    SelectableKeyCapView(
                        text: getKeySymbol(for: key),
                        subtext: getKeyText(for: key),
                        isSelected: selectedKey == key
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func getKeySymbol(for key: HotkeyManager.PushToTalkKey) -> String {
        switch key {
        case .rightOption: return "⌥"
        case .leftOption: return "⌥"
        case .leftControl: return "⌃"
        case .rightControl: return "⌃"
        case .fn: return "Fn"
        case .rightCommand: return "⌘"
        case .rightShift: return "⇧"
        }
    }
    
    private func getKeyText(for key: HotkeyManager.PushToTalkKey) -> String {
        switch key {
        case .rightOption: return "Right Option"
        case .leftOption: return "Left Option"
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        case .fn: return "Function"
        case .rightCommand: return "Right Command"
        case .rightShift: return "Right Shift"
        }
    }
}

struct SelectableKeyCapView: View {
    let text: String
    let subtext: String
    let isSelected: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var keyColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.accentColor.opacity(0.3) : Color.accentColor.opacity(0.2)
        }
        return colorScheme == .dark ? Color(white: 0.2) : .white
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(text)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(width: 44, height: 44)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(keyColor)
                        
                        // Highlight overlay
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                        
                        // Key surface highlight
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.1 : 0.4),
                                        Color.white.opacity(0)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.2),
                    radius: 2,
                    x: 0,
                    y: 1
                )
            
            Text(subtext)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

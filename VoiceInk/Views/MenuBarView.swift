import SwiftUI
import LaunchAtLogin

struct MenuBarView: View {
    @EnvironmentObject var engine: VoiceInkEngine
    @EnvironmentObject var recorderUIManager: RecorderUIManager
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var whisperModelManager: WhisperModelManager
    @EnvironmentObject var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @ObservedObject private var modeManager = ModeManager.shared
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var menuRefreshTrigger = false
    @State private var isHovered = false
    
    var body: some View {
        VStack {
            Button("Toggle Recorder") {
                recorderUIManager.handleToggleMiniRecorder()
            }

            Divider()

            Menu {
                ForEach(modeManager.enabledConfigurations) { config in
                    Button {
                        modeManager.setActiveConfiguration(config)
                    } label: {
                        HStack {
                            Text("\(config.emoji) \(config.name)")
                            if modeManager.currentEffectiveConfiguration?.id == config.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if modeManager.enabledConfigurations.isEmpty {
                    Text("No modes available")
                        .foregroundColor(.secondary)
                }

                Divider()

                Button("Manage Modes") {
                    menuBarManager.openMainWindowAndNavigate(to: "Modes")
                }

                Button("Manage Models") {
                    menuBarManager.openMainWindowAndNavigate(to: "AI Models")
                }
            } label: {
                HStack {
                    let activeMode = modeManager.currentEffectiveConfiguration
                    Text("Mode: \(activeMode.map { "\($0.emoji) \($0.name)" } ?? "None")")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
            }

            Menu {
                ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                    Button {
                        audioDeviceManager.selectDeviceAndSwitchToCustomMode(id: device.id)
                    } label: {
                        HStack {
                            Text(device.name)
                            if audioDeviceManager.getCurrentDevice() == device.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if audioDeviceManager.availableDevices.isEmpty {
                    Text("No devices available")
                        .foregroundColor(.secondary)
                }
            } label: {
                HStack {
                    Text("Audio Input")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
            }

            Menu("Additional") {
                Button {
                    modeManager.updateCurrentEffectiveConfiguration { config in
                        config.useClipboardContext.toggle()
                    }
                    menuRefreshTrigger.toggle()
                } label: {
                    HStack {
                        Text("Clipboard Context")
                        Spacer()
                        if modeManager.currentEffectiveConfiguration?.useClipboardContext == true {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    modeManager.updateCurrentEffectiveConfiguration { config in
                        config.useScreenCapture.toggle()
                    }
                    menuRefreshTrigger.toggle()
                } label: {
                    HStack {
                        Text("Context Awareness")
                        Spacer()
                        if modeManager.currentEffectiveConfiguration?.useScreenCapture == true {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .id("additional-menu-\(menuRefreshTrigger)")
            
            Divider()

            Button("Retry Last Transcription") {
                LastTranscriptionService.retryLastTranscription(
                    from: engine.modelContext,
                    transcriptionModelManager: transcriptionModelManager,
                    serviceRegistry: engine.serviceRegistry,
                    enhancementService: enhancementService
                )
            }

            Button("Copy Last Transcription") {
                LastTranscriptionService.copyLastTranscription(from: engine.modelContext)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            
            Button("History") {
                menuBarManager.openHistoryWindow()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            
            Button("Settings") {
                menuBarManager.openMainWindowAndNavigate(to: "Settings")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Button(menuBarManager.isMenuBarOnly ? "Show Dock Icon" : "Hide Dock Icon") {
                menuBarManager.toggleMenuBarOnly()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            
            Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                .onChange(of: launchAtLoginEnabled) { oldValue, newValue in
                    LaunchAtLogin.isEnabled = newValue
                }
            
            Divider()
            
            Button("Check for Updates") {
                updaterViewModel.checkForUpdates()
            }
            .disabled(!updaterViewModel.canCheckForUpdates)
            
            Button("Help and Support") {
                EmailSupport.openSupportEmail()
            }
            
            Divider()

            Button("Quit VoiceInk") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

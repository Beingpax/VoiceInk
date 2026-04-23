import SwiftUI
import LaunchAtLogin

struct MenuBarView: View {
    @EnvironmentObject var engine: VoiceInkEngine
    @EnvironmentObject var recorderUIManager: RecorderUIManager
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var whisperModelManager: WhisperModelManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var isHovered = false

    private var enhancementProviders: [AIProvider] {
        aiService.connectedProviders.filter { $0 != .elevenLabs && $0 != .deepgram }
    }

    private var enhancementMenuLabel: String {
        guard enhancementService.isEnhancementEnabled else {
            return "AI Model: Off"
        }
        let provider = aiService.selectedProvider
        let model = aiService.currentModel
        if model.isEmpty {
            return "AI Model: \(provider.rawValue)"
        }
        return "AI Model: \(provider.rawValue) / \(model)"
    }
    
    var body: some View {
        VStack {
            Button("Open VoiceInk") {
                menuBarManager.focusMainWindow()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Toggle Recorder") {
                recorderUIManager.handleToggleMiniRecorder()
            }

            Divider()

            Menu {
                ForEach(transcriptionModelManager.usableModels, id: \.id) { model in
                    Button {
                        Task {
                            transcriptionModelManager.setDefaultTranscriptionModel(model)
                        }
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if transcriptionModelManager.currentTranscriptionModel?.id == model.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Button("Manage Models") {
                    menuBarManager.openMainWindowAndNavigate(to: "AI Models")
                }
            } label: {
                HStack {
                    Text("Transcription Model: \(transcriptionModelManager.currentTranscriptionModel?.displayName ?? "None")")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
            }
            
            Divider()
            
            Toggle("AI Enhancement", isOn: $enhancementService.isEnhancementEnabled)

            Menu {
                if enhancementProviders.isEmpty {
                    Text("No providers connected")
                } else {
                    ForEach(enhancementProviders, id: \.self) { provider in
                        let models = aiService.availableModels(for: provider)
                        if models.isEmpty {
                            Button {
                                if aiService.selectedProvider != provider {
                                    aiService.selectedProvider = provider
                                }
                            } label: {
                                HStack {
                                    Text(provider.rawValue)
                                    if aiService.selectedProvider == provider {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } else {
                            Menu {
                                ForEach(models, id: \.self) { model in
                                    Button {
                                        if aiService.selectedProvider != provider {
                                            aiService.selectedProvider = provider
                                        }
                                        aiService.selectModel(model)
                                    } label: {
                                        HStack {
                                            Text(model)
                                            if aiService.selectedProvider == provider && aiService.currentModel == model {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(provider.rawValue)
                                    if aiService.selectedProvider == provider {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()

                Button("Manage Enhancement") {
                    menuBarManager.openMainWindowAndNavigate(to: "Enhancement")
                }
            } label: {
                HStack {
                    Text(enhancementMenuLabel)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
            }
            .disabled(!enhancementService.isEnhancementEnabled)

            LanguageSelectionView(transcriptionModelManager: transcriptionModelManager, displayMode: .menuItem, whisperPrompt: whisperModelManager.whisperPrompt)

            Divider()

            Button("Copy Last Transcription") {
                LastTranscriptionService.copyLastTranscription(from: engine.modelContext)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Settings") {
                menuBarManager.openMainWindowAndNavigate(to: "Settings")
            }
            .keyboardShortcut(",", modifiers: .command)

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
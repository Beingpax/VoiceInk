import SwiftUI
import LaunchAtLogin

struct MenuBarView: View {
    @EnvironmentObject var whisperState: WhisperState
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var menuRefreshTrigger = false  // Added to force menu updates
    @State private var isHovered = false
    @AppStorage("enableAIEnhancementFeatures") private var enableAIEnhancementFeatures = false
    
    var body: some View {
        VStack {
            Menu {
                ForEach(whisperState.usableModels, id: \.id) { model in
                    Button {
                        Task {
                            await whisperState.setDefaultTranscriptionModel(model)
                        }
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if whisperState.currentTranscriptionModel?.id == model.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                Divider()
                
                if enableAIEnhancementFeatures {
                    Button("Manage Models") {
                        menuBarManager.openMainWindowAndNavigate(to: "AI Models")
                    }
                }
            } label: {
                HStack {
                    Text("Transcription Model: \(whisperState.currentTranscriptionModel?.displayName ?? "None")")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
            }
            
            Divider()
            
            if enableAIEnhancementFeatures {
                Toggle("AI Enhancement", isOn: $enhancementService.isEnhancementEnabled)
                
                Menu {
                    ForEach(enhancementService.allPrompts) { prompt in
                        Button {
                            enhancementService.setActivePrompt(prompt)
                        } label: {
                            HStack {
                                Image(systemName: prompt.icon.rawValue)
                                    .foregroundColor(.accentColor)
                                Text(prompt.title)
                                if enhancementService.selectedPromptId == prompt.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Prompt: \(enhancementService.activePrompt?.title ?? "None")")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                }
                .disabled(!enhancementService.isEnhancementEnabled)
                
                Menu {
                    ForEach(aiService.connectedProviders, id: \.self) { provider in
                        Button {
                            aiService.selectedProvider = provider
                        } label: {
                            HStack {
                                Text(provider.rawValue)
                                if aiService.selectedProvider == provider {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    
                    if aiService.connectedProviders.isEmpty {
                        Text("No providers connected")
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    Button("Manage AI Providers") {
                        menuBarManager.openMainWindowAndNavigate(to: "Enhancement")
                    }
                } label: {
                    HStack {
                        Text("AI Provider: \(aiService.selectedProvider.rawValue)")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                }
                .disabled(!enhancementService.isEnhancementEnabled)
                
                Menu {
                    ForEach(aiService.availableModels, id: \.self) { model in
                        Button {
                            aiService.selectModel(model)
                        } label: {
                            HStack {
                                Text(model)
                                if aiService.currentModel == model {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    
                    if aiService.availableModels.isEmpty {
                        Text("No models available")
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    Button("Manage AI Models") {
                        menuBarManager.openMainWindowAndNavigate(to: "Enhancement")
                    }
                } label: {
                    HStack {
                        Text("AI Model: \(aiService.currentModel)")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                }
                .disabled(!enhancementService.isEnhancementEnabled)
                
                LanguageSelectionView(whisperState: whisperState, displayMode: .menuItem, whisperPrompt: whisperState.whisperPrompt)
                
                Menu("Additional") {
                    Button {
                        enhancementService.useClipboardContext.toggle()
                        menuRefreshTrigger.toggle()
                    } label: {
                        HStack {
                            Text("Clipboard Context")
                            Spacer()
                            if enhancementService.useClipboardContext {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!enhancementService.isEnhancementEnabled)
                    
                    Button {
                        enhancementService.useScreenCaptureContext.toggle()
                        menuRefreshTrigger.toggle()
                    } label: {
                        HStack {
                            Text("Context Awareness")
                            Spacer()
                            if enhancementService.useScreenCaptureContext {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!enhancementService.isEnhancementEnabled)
                }
                .id("additional-menu-\(menuRefreshTrigger)")
            }
            
            Divider()
            
            Button("Retry Last Transcription") {
                LastTranscriptionService.retryLastTranscription(from: whisperState.modelContext, whisperState: whisperState)
            }
            
            Button("Copy Last Transcription") {
                LastTranscriptionService.copyLastTranscription(from: whisperState.modelContext)
            }
            
            Button("History") {
                menuBarManager.openMainWindowAndNavigate(to: "History")
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            
            Button("Settings") {
                menuBarManager.openMainWindowAndNavigate(to: "Settings")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Button(menuBarManager.isMenuBarOnly ? "Show Dock Icon" : "Hide Dock Icon") {
                menuBarManager.toggleMenuBarOnly()
            }
            
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

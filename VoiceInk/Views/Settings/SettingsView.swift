import SwiftUI
import Cocoa
import Carbon.HIToolbox
import LaunchAtLogin
import AVFoundation

struct RadarGraphicView: View {
    @State private var rotateDegree = 0.0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.15), lineWidth: 1)
                .frame(width: 80, height: 80)
            Circle()
                .stroke(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 60, height: 60)
            Circle()
                .stroke(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.04), lineWidth: 1)
                .frame(width: 40, height: 40)
            
            // Radar sweep
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.4), .clear]),
                        center: .center
                    )
                )
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(rotateDegree))
                .onAppear {
                    withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                        rotateDegree = 360
                    }
                }
            
            // Central pulsing dot
            Circle()
                .fill(Color(red: 0.36, green: 0.28, blue: 0.88))
                .frame(width: 6, height: 6)
                .shadow(color: Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.5), radius: 4)
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject private var recorderUIManager: RecorderUIManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @StateObject private var deviceManager = AudioDeviceManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0
    @AppStorage(PasteMethod.userDefaultsKey) private var pasteMethodRawValue = PasteMethod.standard.rawValue
    @AppStorage("IDERoutingMode") private var ideRoutingMode = IDERoutingMode.activeApp.rawValue

    @State private var showResetOnboardingAlert = false
    @State private var hasCancelRecordingShortcut = ShortcutStore.shortcut(for: .cancelRecorder) != nil
    @State private var cancelRecordingShortcutRecorderResetID = 0

    // Expansion states
    @State private var isMiddleClickExpanded = false
    @State private var isSoundFeedbackExpanded = false
    @State private var isMuteSystemExpanded = false
    @State private var isRestoreClipboardExpanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Centered Premium Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.1))
                            .frame(width: 56, height: 56)
                        Image(systemName: "gearshape")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                    }
                    .padding(.top, 24)

                    Text("System Settings")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                    
                    Text("Customize shortcuts, audio behaviors, visual alerts, and system integration")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 450)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)

                VStack(spacing: 16) {
                    // MARK: - Shortcuts Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "keyboard")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            Text("Shortcuts")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        }
                        
                        Divider().opacity(0.5)

                        // Primary Shortcut Block
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Primary Shortcut")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                Text("Trigger start/stop recording globally")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.secondary)
                            }
                            
                            Spacer()
                            
                            shortcutModePicker(binding: $recordingShortcutManager.primaryRecordingShortcutMode)
                            
                            ShortcutRecorder(action: .primaryRecording) {
                                recordingShortcutManager.primaryRecordingShortcut = .custom
                                recordingShortcutManager.updateShortcutStatus()
                            }
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color(red: 0.98, green: 0.98, blue: 0.99))
                        .cornerRadius(8)

                        // Secondary Shortcut Block
                        if recordingShortcutManager.secondaryRecordingShortcut != .none {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Secondary Shortcut")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                    Text("Alternative global key sequence")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color.secondary)
                                }
                                
                                Spacer()
                                
                                shortcutModePicker(binding: $recordingShortcutManager.secondaryRecordingShortcutMode)
                                
                                ShortcutRecorder(action: .secondaryRecording) {
                                    recordingShortcutManager.secondaryRecordingShortcut = .custom
                                    recordingShortcutManager.updateShortcutStatus()
                                }
                                .controlSize(.small)
                                
                                Button {
                                    withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .none }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(red: 0.98, green: 0.98, blue: 0.99))
                            .cornerRadius(8)
                        } else {
                            // Centered button with dashed border
                            Button {
                                withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .custom }
                            } label: {
                                HStack {
                                    Spacer()
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Add Second Shortcut")
                                        .font(.system(size: 12, weight: .bold))
                                    Spacer()
                                }
                                .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)

                    // MARK: - Additional Shortcuts Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "command")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            Text("Additional Shortcuts")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        }
                        
                        Divider().opacity(0.5)

                        VStack(spacing: 10) {
                            // Row 1
                            HStack {
                                Text("Paste Last Transcription (Original)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                Spacer()
                                ShortcutRecorder(action: .pasteLastTranscription) {
                                    recordingShortcutManager.updateShortcutStatus()
                                }
                                .controlSize(.small)
                            }
                            
                            // Row 2
                            HStack {
                                Text("Paste Last Transcription (Enhanced)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                Spacer()
                                ShortcutRecorder(action: .pasteLastEnhancement) {
                                    recordingShortcutManager.updateShortcutStatus()
                                }
                                .controlSize(.small)
                            }

                            // Row 3
                            HStack {
                                Text("Retry Last Transcription")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                Spacer()
                                ShortcutRecorder(action: .retryLastTranscription) {
                                    recordingShortcutManager.updateShortcutStatus()
                                }
                                .controlSize(.small)
                            }

                            // Row 4
                            HStack {
                                Text("Cancel Recording")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                Spacer()
                                HStack(spacing: 8) {
                                    ShortcutRecorder(
                                        action: .cancelRecorder,
                                        defaultShortcut: Self.defaultCancelRecordingShortcut
                                    ) {
                                        hasCancelRecordingShortcut = true
                                    }
                                    .id(cancelRecordingShortcutRecorderResetID)
                                    .controlSize(.small)

                                    Button {
                                        ShortcutStore.setShortcut(nil, for: .cancelRecorder)
                                        hasCancelRecordingShortcut = false
                                        cancelRecordingShortcutRecorderResetID += 1
                                    } label: {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Reset to default")
                                }
                            }
                        }
                        
                        Divider().opacity(0.3)

                        // Middle Click
                        ExpandableSettingsRow(
                            isExpanded: $isMiddleClickExpanded,
                            isEnabled: $recordingShortcutManager.isMiddleClickToggleEnabled,
                            label: "Middle-Click Recording"
                        ) {
                            HStack {
                                Text("Activation Delay")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                                HStack(spacing: 6) {
                                    TextField("", value: $recordingShortcutManager.middleClickActivationDelay, formatter: {
                                        let formatter = NumberFormatter()
                                        formatter.minimum = 0
                                        return formatter
                                    }())
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                                    .frame(width: 60)
                                    Text("ms")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)

                    // MARK: - Recording Feedback Card (with Radar on the right)
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "waveform")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                                Text("Recording Feedback")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                            }
                            
                            Divider().opacity(0.5)

                            VStack(spacing: 12) {
                                // Sound Feedback row
                                ExpandableSettingsRow(
                                    isExpanded: $isSoundFeedbackExpanded,
                                    isEnabled: $soundManager.isEnabled,
                                    label: "Sound Feedback"
                                ) {
                                    CustomSoundSettingsView()
                                        .padding(.horizontal, 4)
                                }

                                Divider().opacity(0.3)

                                // Mute Audio
                                ExpandableSettingsRow(
                                    isExpanded: $isMuteSystemExpanded,
                                    isEnabled: $mediaController.isSystemMuteEnabled,
                                    label: "Mute Audio While Recording"
                                ) {
                                    HStack {
                                        Text("Resume Delay")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Picker("", selection: $mediaController.audioResumptionDelay) {
                                            Text("0s").tag(0.0)
                                            Text("1s").tag(1.0)
                                            Text("2s").tag(2.0)
                                            Text("3s").tag(3.0)
                                            Text("4s").tag(4.0)
                                            Text("5s").tag(5.0)
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                        .fixedSize()
                                    }
                                }

                                Divider().opacity(0.3)

                                // Restore Clipboard
                                ExpandableSettingsRow(
                                    isExpanded: $isRestoreClipboardExpanded,
                                    isEnabled: $restoreClipboardAfterPaste,
                                    label: "Keep Clipboard Content",
                                    infoMessage: "VoiceInk temporarily uses the clipboard to paste transcription. When enabled, it restores your previous clipboard content after the selected delay."
                                ) {
                                    HStack {
                                        Text("Restore Delay")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Picker("", selection: $clipboardRestoreDelay) {
                                            Text("250ms").tag(0.25)
                                            Text("500ms").tag(0.5)
                                            Text("1s").tag(1.0)
                                            Text("2s").tag(2.0)
                                            Text("3s").tag(3.0)
                                            Text("4s").tag(4.0)
                                            Text("5s").tag(5.0)
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                        .fixedSize()
                                    }
                                }

                                Divider().opacity(0.3)

                                // Paste Method Picker
                                HStack {
                                    HStack(spacing: 4) {
                                        Text("Paste Method")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                        InfoTip("Default uses simulated Cmd+V key events. AppleScript can help when custom keyboard layouts do not paste correctly.")
                                    }
                                    Spacer()
                                    Picker(selection: $pasteMethodRawValue) {
                                        ForEach(PasteMethod.allCases) { method in
                                            Text(method.displayName).tag(method.rawValue)
                                        }
                                    } label: {
                                        EmptyView()
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .fixedSize()
                                    .onChange(of: pasteMethodRawValue) { _, newValue in
                                        guard let method = PasteMethod(rawValue: newValue) else {
                                            pasteMethodRawValue = PasteMethod.standard.rawValue
                                            return
                                        }
                                        PasteMethod.setCurrent(method)
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Beautiful Animating Radar Feedback Graphic on the right
                        VStack {
                            Spacer()
                            RadarGraphicView()
                                .padding(.top, 40)
                                .padding(.trailing, 10)
                            Spacer()
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)

                    // MARK: - Power Mode Card
                    PowerModeSection()

                    // MARK: - Voice for AI Agents (MCP) Section Card
                    MCPAgentSection()

                    // MARK: - Interface & Routing Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "macwindow")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            Text("Interface & Routing")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        }
                        
                        Divider().opacity(0.5)

                        HStack {
                            Text("Recorder Style")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                            Spacer()
                            Picker("Recorder Style", selection: $recorderUIManager.recorderType) {
                                Text("Notch").tag("notch")
                                Text("Mini").tag("mini")
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }

                        Divider().opacity(0.3)

                        HStack {
                            HStack(spacing: 4) {
                                Text("Default Output Route")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                InfoTip("Directs transcription outputs to specific developer environments by automatically focusing the target application.")
                            }
                            Spacer()
                            Picker(selection: $ideRoutingMode) {
                                ForEach(IDERoutingMode.allCases) { route in
                                    Text(route.displayName).tag(route.rawValue)
                                }
                            } label: {
                                EmptyView()
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)

                    // MARK: - Experimental Section Card
                    ExperimentalSection()

                    // MARK: - General Section Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "gear")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            Text("General Options")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        }
                        
                        Divider().opacity(0.5)

                        VStack(spacing: 12) {
                            Toggle("Hide Dock Icon", isOn: $menuBarManager.isMenuBarOnly)
                            
                            Divider().opacity(0.3)

                            LaunchAtLogin.Toggle("Launch at Login")
                            
                            Divider().opacity(0.3)

                            Toggle("Auto-check Updates", isOn: Binding(
                                get: { updaterViewModel.automaticallyChecksForUpdates },
                                set: { updaterViewModel.setAutomaticallyChecksForUpdates($0) }
                            ))
                            
                            Divider().opacity(0.3)

                            Toggle("Show Announcements", isOn: $enableAnnouncements)
                                .onChange(of: enableAnnouncements) { _, newValue in
                                    if newValue {
                                        AnnouncementsService.shared.start()
                                    } else {
                                        AnnouncementsService.shared.stop()
                                    }
                                }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.36, green: 0.28, blue: 0.88)))

                        Divider().opacity(0.5)

                        HStack(spacing: 12) {
                            Button("Check for Updates") {
                                updaterViewModel.checkForUpdates()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(updaterViewModel.canCheckForUpdates ? Color(red: 0.36, green: 0.28, blue: 0.88) : Color.gray.opacity(0.4))
                            .cornerRadius(8)
                            .disabled(!updaterViewModel.canCheckForUpdates)

                            Button("Reset Onboarding") {
                                showResetOnboardingAlert = true
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.1))
                            .cornerRadius(8)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)

                    // MARK: - Privacy & Audio Cleanup Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            Text("Privacy & Storage")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        }
                        
                        Divider().opacity(0.5)

                        AudioCleanupSettingsView()

                        Text("Control how VoiceInk handles your transcription data and audio recordings.")
                            .font(.system(size: 10))
                            .foregroundColor(Color.secondary)
                            .padding(.top, 4)
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)

                    // MARK: - Backup & Restore Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "arrow.clockwise.icloud")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            Text("Backup & Configuration")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        }
                        
                        Divider().opacity(0.5)

                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Export Settings")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                Text("Save backup file")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Export") {
                                ImportExportService.shared.exportSettings(
                                    enhancementService: enhancementService,
                                    recordingShortcutManager: recordingShortcutManager,
                                    menuBarManager: menuBarManager,
                                    mediaController: mediaController,
                                    playbackController: playbackController,
                                    soundManager: soundManager,
                                    recorderUIManager: recorderUIManager,
                                    modelContext: modelContext
                                )
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.36, green: 0.28, blue: 0.88))
                            .cornerRadius(6)
                        }

                        Divider().opacity(0.3)

                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Import Settings")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                Text("Restore from backup file")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Import") {
                                ImportExportService.shared.importSettings(
                                    enhancementService: enhancementService,
                                    recordingShortcutManager: recordingShortcutManager,
                                    menuBarManager: menuBarManager,
                                    mediaController: mediaController,
                                    playbackController: playbackController,
                                    soundManager: soundManager,
                                    recorderUIManager: recorderUIManager,
                                    modelContext: modelContext,
                                    transcriptionModelManager: transcriptionModelManager
                                )
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)

                    // MARK: - Diagnostics Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "waveform.and.magnifyingglass")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            Text("Diagnostics")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        }
                        
                        Divider().opacity(0.5)

                        DiagnosticsSettingsView()
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
        .alert("Reset Onboarding", isPresented: $showResetOnboardingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                DispatchQueue.main.async {
                    hasCompletedOnboarding = false
                }
            }
        } message: {
            Text("You'll see the introduction screens again the next time you launch the app.")
        }
    }

    private static let defaultCancelRecordingShortcut = Shortcut.key(
        keyCode: UInt16(kVK_Escape),
        modifierFlags: []
    )

    @ViewBuilder
    private func shortcutModePicker(binding: Binding<RecordingShortcutManager.Mode>) -> some View {
        Picker("", selection: binding) {
            ForEach(RecordingShortcutManager.Mode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

// MARK: - Expandable Settings Row (entire row clickable)

struct ExpandableSettingsRow<Content: View>: View {
    @Binding var isExpanded: Bool
    @Binding var isEnabled: Bool
    let label: String
    var infoMessage: String? = nil
    var infoURL: String? = nil
    @ViewBuilder let content: () -> Content

    @State private var isHandlingToggleChange = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Toggle(isOn: $isEnabled) {
                    HStack(spacing: 4) {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        if let message = infoMessage {
                            if let url = infoURL {
                                InfoTip(message, learnMoreURL: url)
                            } else {
                                InfoTip(message)
                            }
                        }
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.36, green: 0.28, blue: 0.88)))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isEnabled && isExpanded ? 90 : 0))
                    .opacity(isEnabled ? 1 : 0.4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isHandlingToggleChange else { return }
                if isEnabled {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }

            if isEnabled && isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.top, 12)
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onChange(of: isEnabled) { _, newValue in
            isHandlingToggleChange = true
            if newValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            } else {
                isExpanded = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isHandlingToggleChange = false
            }
        }
    }
}

// MARK: - Power Mode Section

struct PowerModeSection: View {
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @AppStorage("powerModeUIFlag") private var powerModeUIFlag = false
    @AppStorage("powerModePersistConfig") private var powerModePersistSettings = false
    @State private var showDisableAlert = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                Text("Power Mode")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
            }
            
            Divider().opacity(0.5)

            ExpandableSettingsRow(
                isExpanded: $isExpanded,
                isEnabled: toggleBinding,
                label: "Enable Power Mode",
                infoMessage: "Apply custom settings based on active app or website.",
                infoURL: "https://tryvoiceink.com/docs/power-mode"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $powerModePersistSettings) {
                        HStack(spacing: 4) {
                            Text("Persist Configured Preferences")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            InfoTip("When enabled, Power Mode preferences stay active after you stop recording instead of reverting to your original preferences.")
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.36, green: 0.28, blue: 0.88)))
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)
        .alert("Power Mode Still Active", isPresented: $showDisableAlert) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Disable or remove your Power Modes first.")
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { powerModeUIFlag },
            set: { newValue in
                if newValue {
                    powerModeUIFlag = true
                    NotificationCenter.default.post(name: .powerModeShortcutAvailabilityDidChange, object: nil)
                } else if powerModeManager.configurations.allSatisfy({ !$0.isEnabled }) {
                    powerModeUIFlag = false
                    NotificationCenter.default.post(name: .powerModeShortcutAvailabilityDidChange, object: nil)
                } else {
                    showDisableAlert = true
                }
            }
        )
    }
}

// MARK: - Experimental Section

struct ExperimentalSection: View {
    @ObservedObject private var playbackController = PlaybackController.shared
    @ObservedObject private var mediaController = MediaController.shared
    @State private var isPauseMediaExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "flask")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                Text("Experimental Features")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
            }
            
            Divider().opacity(0.5)

            ExpandableSettingsRow(
                isExpanded: $isPauseMediaExpanded,
                isEnabled: $playbackController.isPauseMediaEnabled,
                label: "Pause Media While Recording",
                infoMessage: "Pauses playing media when recording starts and resumes when done."
            ) {
                HStack {
                    Text("Resume Delay")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $mediaController.audioResumptionDelay) {
                        Text("0s").tag(0.0)
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                        Text("3s").tag(3.0)
                        Text("4s").tag(4.0)
                        Text("5s").tag(5.0)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Voice for AI Agents (MCP) Section

struct MCPAgentSection: View {
    @AppStorage("enableMCPServer") private var enableMCPServer = true
    @AppStorage("mcpServerPort") private var mcpServerPort = 51089
    @AppStorage("speakAIQuestionsAloud") private var speakAIQuestionsAloud = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "cpu")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                Text("Voice for AI Agents (MCP)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
            }
            
            Divider().opacity(0.5)

            ExpandableSettingsRow(
                isExpanded: $isExpanded,
                isEnabled: Binding(
                    get: { enableMCPServer },
                    set: { newValue in
                        enableMCPServer = newValue
                        if newValue {
                            MCPServerService.shared.start(port: mcpServerPort)
                        } else {
                            MCPServerService.shared.stop()
                        }
                    }
                ),
                label: "Voice for AI Agents (MCP)",
                infoMessage: "Allows AI coding tools like Claude Code, Codex, and Cursor to prompt you via voice dictation.",
                infoURL: "https://spokenly.app/docs/macos/voice-for-agents"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Server Port")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("Port", value: Binding(
                            get: { mcpServerPort },
                            set: { newValue in
                                mcpServerPort = newValue
                                if enableMCPServer {
                                    MCPServerService.shared.start(port: newValue)
                                }
                            }
                        ), formatter: NumberFormatter())
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .frame(width: 80)
                    }

                    Divider().opacity(0.3)

                    Toggle(isOn: $speakAIQuestionsAloud) {
                        HStack(spacing: 4) {
                            Text("Speak AI questions aloud")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            InfoTip("Reads agent questions out loud using text-to-speech before starting the voice dictation recording.")
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.36, green: 0.28, blue: 0.88)))
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)
    }
}

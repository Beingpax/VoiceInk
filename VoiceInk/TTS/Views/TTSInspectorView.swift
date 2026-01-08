import SwiftUI
import AppKit

struct TTSInspectorView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var isVisible: Bool
    
    // Track expanded state of sections
    @State private var isVoiceExpanded = true
    @State private var isAudioExpanded = true
    @State private var isExportExpanded = false
    @State private var isCostExpanded = false
    @State private var isSystemExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Tickwick Settings", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .help("Hide Tickwick Settings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Voice Configuration
                    DisclosureGroup(
                        isExpanded: $isVoiceExpanded,
                        content: {
                            VStack(spacing: 16) {
                                ProviderSelectionView()
                                VoiceSelectionView()
                                VoiceStyleControlsView()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        },
                        label: {
                            InspectorSectionHeader(title: "Voice Configuration", icon: "person.wave.2", isExpanded: isVoiceExpanded)
                        }
                    )
                    
                    Divider()
                    
                    // Audio & Playback
                    DisclosureGroup(
                        isExpanded: $isAudioExpanded,
                        content: {
                            VStack(spacing: 16) {
                                AudioSettingsView()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        },
                        label: {
                            InspectorSectionHeader(title: "Audio & Playback", icon: "speaker.wave.2", isExpanded: isAudioExpanded)
                        }
                    )
                    
                    Divider()
                    
                    // Export Settings
                    DisclosureGroup(
                        isExpanded: $isExportExpanded,
                        content: {
                            VStack(spacing: 16) {
                                ExportSettingsView()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        },
                        label: {
                            InspectorSectionHeader(title: "Export", icon: "square.and.arrow.down", isExpanded: isExportExpanded)
                        }
                    )
                    
                    Divider()
                    
                    // Cost & Usage
                    DisclosureGroup(
                        isExpanded: $isCostExpanded,
                        content: {
                            VStack(spacing: 16) {
                                CostView()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        },
                        label: {
                            InspectorSectionHeader(title: "Cost & Usage", icon: "dollarsign.circle", isExpanded: isCostExpanded)
                        }
                    )
                    
                    Divider()
                    
                    // System / Batch
                    DisclosureGroup(
                        isExpanded: $isSystemExpanded,
                        content: {
                            VStack(spacing: 16) {
                                SystemSettingsView()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        },
                        label: {
                            InspectorSectionHeader(title: "System", icon: "gear", isExpanded: isSystemExpanded)
                        }
                    )

                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Subviews

private struct InspectorSectionHeader: View {
    let title: String
    let icon: String
    let isExpanded: Bool
    
    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

private struct ProviderSelectionView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("", selection: $settings.selectedProvider) {
                ForEach(TTSProviderType.allCases, id: \.self) { provider in
                    Label(provider.displayName, systemImage: provider.icon)
                        .tag(provider)
                }
            }
            .labelsHidden()
            .onChange(of: settings.selectedProvider) {
                settings.updateAvailableVoices()
            }
            
            let profile = ProviderCostProfile.profile(for: settings.selectedProvider)
            Text(profile.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VoiceSelectionView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var preview: TTSVoicePreviewViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Voice")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !settings.availableVoices.isEmpty {
                    Button {
                        if preview.isPreviewPlaying {
                            preview.stopPreview()
                        } else if let voice = settings.selectedVoice {
                            preview.previewVoice(voice)
                        }
                    } label: {
                        Image(systemName: preview.isPreviewPlaying ? "stop.fill" : "play.circle")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Preview selected voice")
                }
            }
            
            Picker("", selection: $settings.selectedVoice) {
                Text("Default").tag(nil as Voice?)
                ForEach(settings.availableVoices) { voice in
                    Text(voice.name).tag(voice as Voice?)
                }
            }
            .labelsHidden()
            
            if let voice = settings.selectedVoice {
                HStack(spacing: 8) {
                    Text(voice.language)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    
                    if !preview.canPreview(voice) {
                        Image(systemName: "key.slash")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .help("API Key required for preview")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VoiceStyleControlsView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if settings.hasActiveStyleControls {
                Divider()
                
                HStack {
                    Text("Style Controls")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Reset") {
                        settings.resetStyleControls()
                    }
                    .controlSize(.small)
                    .disabled(!settings.canResetStyleControls)
                }
                
                ForEach(settings.activeStyleControls) { control in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(control.label)
                                .font(.caption)
                            Spacer()
                            Text(control.formattedValue(for: settings.currentStyleValue(for: control)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let step = control.step {
                            Slider(value: settings.binding(for: control), in: control.range, step: step)
                        } else {
                            Slider(value: settings.binding(for: control), in: control.range)
                        }
                    }
                }
            }
            
            if settings.selectedProvider == .elevenLabs {
                Divider()
                ElevenLabsPromptingView()
            }
        }
    }
}

private struct AudioSettingsView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var playback: TTSPlaybackViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Speed
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Playback Speed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(playback.playbackSpeed, specifier: "%.2g")×")
                        .font(.caption)
                }
                
                HStack {
                    Image(systemName: "tortoise")
                        .font(.caption2)
                    Slider(value: $playback.playbackSpeed, in: 0.5...2.0, step: 0.25) { editing in
                        if !editing {
                            playback.applyPlaybackSpeed(save: true)
                        }
                    }
                    Image(systemName: "hare")
                        .font(.caption2)
                }
            }
            
            // Volume
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Volume")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(playback.volume * 100))%")
                        .font(.caption)
                }
                
                HStack {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                    Slider(value: $playback.volume, in: 0...1) { editing in
                        if !editing {
                            playback.applyPlaybackVolume(save: true)
                        }
                    }
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                }
            }
            
            Divider()
            
            Toggle(isOn: $playback.isLoopEnabled) {
                Text("Loop Playback")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .onChange(of: playback.isLoopEnabled) {
                settings.saveSettings()
            }
        }
    }
}

private struct ExportSettingsView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var importExport: TTSImportExportViewModel
    @State private var selectedTranscriptFormat: TranscriptFormat = .srt
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio Format")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $settings.selectedFormat) {
                    ForEach(settings.supportedFormats, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                
                if let help = settings.exportFormatHelpText {
                    Text(help)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Transcript Export")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Picker("", selection: $selectedTranscriptFormat) {
                        Text("SRT").tag(TranscriptFormat.srt)
                        Text("VTT").tag(TranscriptFormat.vtt)
                    }
                    .frame(width: 80)
                    .labelsHidden()
                    
                    Button {
                        importExport.exportTranscript(format: selectedTranscriptFormat)
                    } label: {
                        Label("Export File", systemImage: "doc.text")
                    }
                    .disabled(viewModel.currentTranscript == nil)
                }
                
                if viewModel.currentTranscript == nil {
                    Text("Generate speech to create a transcript.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

private struct CostView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Estimated Cost")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.costEstimate.summary)
                        .font(.title2)
                        .fontWeight(.medium)
                }
                Spacer()
                Button {
                    viewModel.objectWillChange.send()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh estimate")
            }
            
            if let detail = viewModel.costEstimate.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            
            Text("Character Count: \(viewModel.effectiveCharacterCount)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct SystemSettingsView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { settings.notificationsEnabled },
                set: { settings.setNotificationsEnabled($0) }
            )) {
                VStack(alignment: .leading) {
                    Text("Batch Notifications")
                    Text("Notify when background jobs complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }
}

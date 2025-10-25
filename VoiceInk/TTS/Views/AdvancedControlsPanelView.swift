import SwiftUI

struct AdvancedControlsPanelView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Advanced Controls")
                .font(.headline)
                .padding(.bottom, 4)
            
            Divider()
            
            // Speed Control
            VStack(alignment: .leading, spacing: 8) {
                Label("Speed", systemImage: "speedometer")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Button(action: {
                        viewModel.playbackSpeed = max(0.5, viewModel.playbackSpeed - 0.25)
                    }) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Decrease speed")
                    
                    Picker("", selection: $viewModel.playbackSpeed) {
                        Text("0.5×").tag(0.5)
                        Text("0.75×").tag(0.75)
                        Text("1.0×").tag(1.0)
                        Text("1.25×").tag(1.25)
                        Text("1.5×").tag(1.5)
                        Text("1.75×").tag(1.75)
                        Text("2.0×").tag(2.0)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 80)
                    .onChange(of: viewModel.playbackSpeed) {
                        viewModel.applyPlaybackSpeed(save: true)
                    }
                    
                    Button(action: {
                        viewModel.playbackSpeed = min(2.0, viewModel.playbackSpeed + 0.25)
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Increase speed")
                }
            }
            
            Divider()
            
            // Volume Control
            VStack(alignment: .leading, spacing: 8) {
                Label("Volume", systemImage: volumeIcon)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Slider(value: $viewModel.volume, in: 0...1) { editing in
                        if !editing {
                            viewModel.applyPlaybackVolume(save: true)
                        }
                    }
                    .onChange(of: viewModel.volume) {
                        viewModel.applyPlaybackVolume()
                    }
                    .frame(width: 150)
                    
                    Text("\(Int(viewModel.volume * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    
                    Button(action: {
                        if viewModel.volume > 0 {
                            viewModel.volume = 0
                        } else {
                            viewModel.volume = 0.75
                        }
                        viewModel.applyPlaybackVolume(save: true)
                    }) {
                        Image(systemName: viewModel.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle mute")
                }
            }
            
            Divider()

            // Loop Control
            HStack {
                Toggle(isOn: $viewModel.isLoopEnabled) {
                    Label("Loop Playback", systemImage: "repeat")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)
                .onChange(of: viewModel.isLoopEnabled) {
                    viewModel.saveSettings()
                }
            }

            Divider()

            // Export Format
            VStack(alignment: .leading, spacing: 8) {
                Label("Export Format", systemImage: "square.and.arrow.down")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Export Format", selection: $viewModel.selectedFormat) {
                    ForEach(viewModel.supportedFormats, id: \.self) { format in
                        Text(format.displayName)
                            .tag(format)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 160)

                if let helpText = viewModel.exportFormatHelpText {
                    Text(helpText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Audio Status
            if viewModel.audioData != nil {
                Divider()

                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text("Audio Ready")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Spacer()
                    if viewModel.duration > 0 {
                        Text(formatDuration(viewModel.duration))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding()
        .frame(width: 280)
    }
    
    private var volumeIcon: String {
        if viewModel.volume == 0 {
            return "speaker.slash"
        } else if viewModel.volume < 0.33 {
            return "speaker"
        } else if viewModel.volume < 0.66 {
            return "speaker.wave.1"
        } else {
            return "speaker.wave.2"
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Preview
struct AdvancedControlsPanelView_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedControlsPanelView()
            .environmentObject(TTSViewModel())
    }
}

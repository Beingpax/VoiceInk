import SwiftUI
import UniformTypeIdentifiers

struct CustomSoundSettingsView: View {
    @StateObject private var customSoundManager = CustomSoundManager.shared
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        Group {
            LabeledContent("Start Sound") {
                soundControls(for: .start)
            }

            LabeledContent("Stop Sound") {
                soundControls(for: .stop)
            }
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    @ViewBuilder
    private func soundControls(for type: CustomSoundManager.SoundType) -> some View {
        let isCustom = type == .start ? customSoundManager.isUsingCustomStartSound : customSoundManager.isUsingCustomStopSound
        let fileName = customSoundManager.getSoundDisplayName(for: type)

        HStack(spacing: 8) {
            Text(isCustom ? (fileName ?? "Custom") : "Default")
                .foregroundStyle(.secondary)
                .frame(maxWidth: 100, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                if type == .start {
                    SoundManager.shared.playStartSound()
                } else {
                    SoundManager.shared.playStopSound()
                }
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Test")

            Button {
                selectSound(for: type)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Choose")

            if isCustom {
                Button {
                    customSoundManager.resetSoundToDefault(for: type)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Reset")
            }
        }
    }

    private func selectSound(for type: CustomSoundManager.SoundType) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(type.rawValue.capitalized) Sound"
        panel.message = "Select an audio file"
        panel.allowedContentTypes = [
            UTType.audio,
            UTType.mp3,
            UTType.wav,
            UTType.aiff
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let result = customSoundManager.setCustomSound(url: url, for: type)
            if case .failure(let error) = result {
                alertTitle = "Invalid Audio File"
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
}

#Preview {
    CustomSoundSettingsView()
        .frame(width: 400)
        .padding()
}

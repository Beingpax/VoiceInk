import SwiftUI
import UniformTypeIdentifiers

struct CustomSoundSettingsView: View {
    @StateObject private var customSoundManager = CustomSoundManager.shared
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private enum SoundMenuSelection: Hashable {
        case builtIn(CustomSoundManager.BuiltInSound)
        case custom
    }

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
            Picker("Sound", selection: soundSelectionBinding(for: type)) {
                ForEach(CustomSoundManager.BuiltInSound.allCases) { sound in
                    Text(sound.displayName).tag(SoundMenuSelection.builtIn(sound))
                }

                if isCustom || fileName != nil {
                    Text("Custom: \(fileName ?? "Custom")").tag(SoundMenuSelection.custom)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 116, alignment: .trailing)
            .fixedSize()
            .help("Select sound")

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

            if !customSoundManager.isDefaultSelection(for: type) {
                Button {
                    if isCustom {
                        customSoundManager.resetSoundToDefault(for: type)
                    } else {
                        customSoundManager.selectBuiltInSound(type.defaultBuiltInSound, for: type)
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Reset")
            }
        }
    }

    private func soundSelectionBinding(for type: CustomSoundManager.SoundType) -> Binding<SoundMenuSelection> {
        Binding(
            get: {
                let isCustom = type == .start ? customSoundManager.isUsingCustomStartSound : customSoundManager.isUsingCustomStopSound
                if isCustom {
                    return .custom
                }

                return .builtIn(customSoundManager.selectedBuiltInSound(for: type))
            },
            set: { selection in
                switch selection {
                case .builtIn(let sound):
                    customSoundManager.selectBuiltInSound(sound, for: type)
                case .custom:
                    customSoundManager.useCustomSound(for: type)
                }
            }
        )
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

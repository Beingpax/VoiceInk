import SwiftUI

struct ModelSettingsView: View {
    @ObservedObject var whisperPrompt: WhisperPrompt
    @AppStorage("SelectedLanguage") private var selectedLanguage: String = "en"
    @AppStorage("IsTextFormattingEnabled") private var isTextFormattingEnabled = true
    @AppStorage("IsVADEnabled") private var isVADEnabled = true
    @AppStorage("AppendTrailingSpace") private var appendTrailingSpace = true
    @AppStorage("PrewarmModelOnWake") private var prewarmModelOnWake = true
    @AppStorage("showLiveTextPreview") private var showLiveTextPreview = true
    @State private var customPrompt: String = ""
    @State private var isEditing: Bool = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if isEditing {
                        TextEditor(text: $customPrompt)
                            .font(.system(size: 12))
                            .frame(minHeight: 40, maxHeight: 80)
                            .fixedSize(horizontal: false, vertical: true)
                            .scrollContentBackground(.hidden)

                        Button("Save") {
                            whisperPrompt.setCustomPrompt(customPrompt, for: selectedLanguage)
                            isEditing = false
                        }
                    } else {
                        Text(whisperPrompt.getLanguagePrompt(for: selectedLanguage))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Edit") {
                            customPrompt = whisperPrompt.getLanguagePrompt(for: selectedLanguage)
                            isEditing = true
                        }
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Output Format")
                    InfoTip(
                        "Only supported for local Whisper models. Unlike GPT, Voice Models(whisper) follows the style of your prompt rather than instructions. Use examples of your desired output format instead of commands.",
                        learnMoreURL: "https://cookbook.openai.com/examples/whisper_prompting_guide#comparison-with-gpt-prompting"
                    )
                }
            }

            Section {
                Toggle(isOn: $appendTrailingSpace) {
                    Text("Add Space After Paste")
                }
                .toggleStyle(.switch)

                Toggle(isOn: $isTextFormattingEnabled) {
                    HStack(spacing: 4) {
                        Text("Automatic text formatting")
                        InfoTip("Apply intelligent text formatting to break large block of text into paragraphs.")
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $isVADEnabled) {
                    HStack(spacing: 4) {
                        Text("Voice Activity Detection (VAD)")
                        InfoTip("Detect speech segments and filter out silence to improve accuracy of local models.")
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $prewarmModelOnWake) {
                    HStack(spacing: 4) {
                        Text("Prewarm model (Experimental)")
                        InfoTip("Turn this on if transcriptions with local models are taking longer than expected. Runs silent background transcription on app launch and wake to trigger optimization.")
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $showLiveTextPreview) {
                    HStack(spacing: 4) {
                        Text("Show Live Text Preview")
                        InfoTip("Displays the live transcript preview in the recorder while speaking. Only applies when using real-time streaming models.")
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Transcription")
            }

            Section {
                FillerWordsSettingsView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: selectedLanguage) { oldValue, newValue in
            if isEditing {
                customPrompt = whisperPrompt.getLanguagePrompt(for: selectedLanguage)
            }
        }
    }
}

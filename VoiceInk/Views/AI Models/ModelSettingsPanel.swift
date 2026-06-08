import SwiftUI

struct ModelSettingsPanel: View {
    @State private var selectedTab: ModelSettingsTab = .transcription

    var body: some View {
        VStack(spacing: 0) {
            ModelSettingsTabBar(selection: $selectedTab)

            switch selectedTab {
            case .transcription:
                TranscriptionModelSettingsView()
            case .enhancement:
                EnhancementModelSettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private enum ModelSettingsTab: String, CaseIterable, Identifiable {
    case transcription = "Transcription"
    case enhancement = "Enhancement"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .transcription:
            return "captions.bubble.fill"
        case .enhancement:
            return "sparkles"
        }
    }
}

private struct ModelSettingsTabBar: View {
    @Binding var selection: ModelSettingsTab

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ModelSettingsTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)

                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: selection == tab ? .semibold : .medium))
                    }
                    .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        AppMaterialCardBackground(isSelected: selection == tab, cornerRadius: 22)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct TranscriptionModelSettingsView: View {
    var body: some View {
        Form {
            FillerWordsSettingsSection()

            AdvancedModelSettingsSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EnhancementModelSettingsView: View {
    @AppStorage("SkipShortEnhancement") private var isSkipShortEnhancementEnabled = true
    @AppStorage("ShortEnhancementWordThreshold") private var shortEnhancementWordThreshold = 3
    @AppStorage("EnhancementTimeoutSeconds") private var enhancementTimeoutSeconds = 7
    @AppStorage("EnhancementRetryOnTimeout") private var retryOnTimeout = true
    @State private var isShortEnhancementExpanded = false

    var body: some View {
        Form {
            Section {
                ExpandableSettingsRow(
                    isExpanded: $isShortEnhancementExpanded,
                    isEnabled: $isSkipShortEnhancementEnabled,
                    label: "Skip short transcriptions",
                    infoMessage: "Automatically skip AI enhancement when the transcription has very few words. Short phrases like \"yes\", \"thank you\", or quick commands don't benefit from enhancement."
                ) {
                    Picker("Minimum words", selection: $shortEnhancementWordThreshold) {
                        ForEach(1...15, id: \.self) { count in
                            Text("\(count) \(count == 1 ? "word" : "words")").tag(count)
                        }
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Enhancement Settings")
            }

            Section {
                Picker("Timeout duration", selection: $enhancementTimeoutSeconds) {
                    ForEach([3, 5, 7, 10, 15, 20, 30, 40, 50, 60], id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                .pickerStyle(.menu)

                Picker("On timeout", selection: $retryOnTimeout) {
                    Text("Fail immediately").tag(false)
                    Text("Retry").tag(true)
                }
                .pickerStyle(.menu)
            } header: {
                HStack(spacing: 4) {
                    Text("Request Timeout")
                    InfoTip("Set how long to wait for the AI provider to respond. If no response is received within this duration, you can either fail immediately and paste the original transcription, or retry the request up to 3 attempts.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AdvancedModelSettingsSection: View {
    @AppStorage("IsVADEnabled") private var isVADEnabled = true
    @AppStorage("AppendTrailingSpace") private var appendTrailingSpace = true
    @AppStorage("PrewarmModelOnWake") private var prewarmModelOnWake = true

    var body: some View {
        Section {
            Toggle(isOn: $appendTrailingSpace) {
                HStack(spacing: 4) {
                    Text("Add Space After Paste")
                    InfoTip("Add a trailing space after pasted transcription output.")
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
        } header: {
            Text("Advanced")
        }
    }
}

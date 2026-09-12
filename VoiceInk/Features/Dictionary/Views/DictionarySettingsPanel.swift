import SwiftUI

struct DictionarySettingsPanel: View {
    let onDismiss: () -> Void
    @AppStorage(AutoLearnSettings.isEnabledKey) private var isAutoLearnDictionaryEnabled = true
    @AppStorage(AutoLearnSettings.reviewScheduleKey)
    private var reviewScheduleRawValue = AutoLearnReviewSchedule.immediately.rawValue
    @State private var pendingCorrectionCount = 0

    var body: some View {
        VStack(spacing: 0) {
            panelHeader

            Form {
                Section {
                    LabeledContent("Quick Add to Dictionary") {
                        ShortcutRecorder(action: .quickAddToDictionary)
                            .controlSize(.small)
                    }
                } header: {
                    Text("Shortcut")
                }

                Section {
                    Toggle("Auto-Learn Dictionary", isOn: $isAutoLearnDictionaryEnabled)
                        .onChange(of: isAutoLearnDictionaryEnabled) { _, isEnabled in
                            Task {
                                await AutoLearnService.shared.settingDidChange(isEnabled: isEnabled)
                            }
                        }

                    if isAutoLearnDictionaryEnabled {
                        AutoLearnModelSelectionView()

                        LabeledContent {
                            Picker("", selection: $reviewScheduleRawValue) {
                                ForEach(AutoLearnReviewSchedule.allCases) { schedule in
                                    Text(schedule.title).tag(schedule.rawValue)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: reviewScheduleRawValue) { _, _ in
                                Task {
                                    await AutoLearnService.shared.reviewScheduleDidChange()
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Review corrections")
                                InfoTip(
                                    "Choose when saved corrections are sent to your AI provider. Manual review keeps them local until you select Review Now."
                                )
                            }
                        }

                        LabeledContent("Pending corrections") {
                            Text("\(pendingCorrectionCount)")
                                .foregroundStyle(.secondary)
                        }

                        Button("Review Now") {
                            Task {
                                await AutoLearnService.shared.reviewPendingNow()
                            }
                        }
                        .disabled(pendingCorrectionCount == 0)
                    }
                } header: {
                    AutoLearnSectionHeader()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await refreshPendingCorrectionCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .autoLearnQueueDidChange)) { _ in
            Task {
                await refreshPendingCorrectionCount()
            }
        }
    }

    private var panelHeader: some View {
        AppPanelHeader(title: "Dictionary Settings", onClose: onDismiss)
    }

    @MainActor
    private func refreshPendingCorrectionCount() async {
        pendingCorrectionCount = (try? await AutoLearnService.shared.pendingReviewCount()) ?? 0
    }
}

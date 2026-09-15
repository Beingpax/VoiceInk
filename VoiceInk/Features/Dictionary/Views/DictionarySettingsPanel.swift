import SwiftUI

struct DictionarySettingsPanel: View {
    let onDismiss: () -> Void
    let onReviewNow: () -> Void
    @AppStorage(AutoLearnSettings.isEnabledKey) private var isAutoLearnDictionaryEnabled = true
    @AppStorage(AutoLearnSettings.reviewScheduleKey)
    private var reviewScheduleRawValue = AutoLearnReviewSchedule.immediately.rawValue
    @State private var pendingCorrectionCount = 0

    var body: some View {
        QuickPanelScaffold {
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

                        LabeledContent("Corrections to review") {
                            Text("\(pendingCorrectionCount)")
                                .foregroundStyle(.secondary)
                        }

                        Button("Review Now") {
                            onReviewNow()
                        }
                        .disabled(pendingCorrectionCount == 0)
                    }
                } header: {
                    AutoLearnSectionHeader()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 68, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } header: {
            panelHeader
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
        .onReceive(
            NotificationCenter.default.publisher(for: .autoLearnReviewProposalsDidChange)
        ) { _ in
            Task {
                await refreshPendingCorrectionCount()
            }
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 12) {
            Text("Dictionary Settings")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            AppIconButton(
                systemName: "xmark",
                help: "Close",
                size: 28,
                iconSize: 14,
                cornerRadius: AppTheme.Radius.control,
                action: onDismiss
            )
        }
        .padding(.horizontal, 20)
        .frame(height: QuickPanelMetrics.headerHeight)
    }

    @MainActor
    private func refreshPendingCorrectionCount() async {
        let pending = (try? await AutoLearnService.shared.outstandingReviewCount()) ?? 0
        let proposals = (try? await AutoLearnService.shared.reviewProposalCount()) ?? 0
        pendingCorrectionCount = pending + proposals
    }
}

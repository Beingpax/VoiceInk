import SwiftUI

private struct DictionaryTransferAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct DictionarySettingsPanel: View {
    @Environment(\.modelContext) private var modelContext

    let onDismiss: () -> Void
    let onReviewNow: () -> Void
    @AppStorage(AutoLearnSettings.isEnabledKey) private var isAutoLearnDictionaryEnabled = true
    @AppStorage(AutoLearnSettings.reviewScheduleKey)
    private var reviewScheduleRawValue = AutoLearnReviewSchedule.immediately.rawValue
    @State private var pendingCorrectionCount = 0
    @State private var pendingImport: DictionaryImportPayload?
    @State private var transferAlert: DictionaryTransferAlert?

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

                Section {
                    LabeledContent("Export Dictionary") {
                        Button("Export") {
                            exportDictionary()
                        }
                    }

                    LabeledContent("Import Dictionary") {
                        Button("Import") {
                            chooseDictionaryFile()
                        }
                    }
                } header: {
                    Text("Dictionary Data")
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
        .sheet(item: $pendingImport) { payload in
            DictionaryImportPreviewSheet(
                payload: payload,
                onCancel: {
                    pendingImport = nil
                },
                onImported: { _ in
                    pendingImport = nil
                }
            )
        }
        .alert(item: $transferAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text("OK"))
            )
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

    @MainActor
    private func exportDictionary() {
        do {
            let archive = try DictionaryImportExportService.makeArchive(modelContext: modelContext)
            let data = try DictionaryImportExportService.encodeArchive(archive)
            guard let url = try DictionaryFilePanelService.saveDictionaryData(data) else {
                return
            }
            showTransferAlert(
                title: String(localized: "Dictionary Exported"),
                message: String(
                    format: String(localized: "Vocabulary and word replacements were exported to %@."),
                    url.lastPathComponent
                )
            )
        } catch {
            showTransferAlert(
                title: String(localized: "Export Failed"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func chooseDictionaryFile() {
        do {
            guard let data = try DictionaryFilePanelService.chooseDictionaryData() else {
                return
            }
            pendingImport = try DictionaryImportExportService.decodeArchiveData(data)
        } catch {
            showTransferAlert(
                title: String(localized: "Import Failed"),
                message: error.localizedDescription
            )
        }
    }

    private func showTransferAlert(title: String, message: String) {
        transferAlert = DictionaryTransferAlert(title: title, message: message)
    }
}

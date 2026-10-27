import SwiftUI

struct AutoLearnSectionHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Auto Learn")
            InfoTip(
                "Offers word replacements on your Mac. Add a suggestion to keep it, or dismiss it.",
                learnMoreURL: "https://tryvoiceink.com/docs/auto-learn-dictionary"
            )
            .accessibilityLabel("Learn about Dictionary Auto Learn")
        }
    }
}

private struct DictionaryTransferAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct DictionarySettingsPanel: View {
    @Environment(\.modelContext) private var modelContext

    let onDismiss: () -> Void
    @AppStorage(VocabularyCorrectionSettings.isEnabledKey) private var isVocabularyCorrectionEnabled = true
    @AppStorage(AutoLearnSettings.isEnabledKey) private var isAutoLearnDictionaryEnabled = true
    @AppStorage(AutoLearnSettings.minimumCorrectionsKey) private var minimumCorrections = 1
    @AppStorage(AutoLearnSettings.hasFailureKey) private var hasAutoLearnFailure = false
    @AppStorage(AutoLearnSettings.failureMessageKey) private var autoLearnFailureMessage = ""
    @State private var pendingImport: DictionaryImportPayload?
    @State private var transferAlert: DictionaryTransferAlert?
    @State private var dataHealth = AutoLearnDataHealth()
    @State private var isCheckingData = false
    @State private var needsDataCheck = false
    @State private var isRepairingData = false
    @State private var showRepairConfirmation = false
    @State private var repairError: String?

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
                    Toggle("Automatic Vocabulary Correction", isOn: $isVocabularyCorrectionEnabled)
                } header: {
                    HStack(spacing: 4) {
                        Text("Vocabulary")
                        InfoTip("Locally corrects words using your vocabulary and names on screen with similar spelling or sound.")
                            .accessibilityLabel("Learn about Vocabulary Correction")
                    }
                }

                Section {
                    Toggle("Auto-Learn Dictionary", isOn: $isAutoLearnDictionaryEnabled)
                        .onChange(of: isAutoLearnDictionaryEnabled) { _, isEnabled in
                            Task {
                                await AutoLearnService.shared.settingDidChange(isEnabled: isEnabled)
                                await checkAutoLearnData()
                            }
                        }

                    if isAutoLearnDictionaryEnabled {
                        LabeledContent {
                            Picker("Suggest after", selection: Binding(
                                get: { AutoLearnSettings.clampedMinimumCorrections(minimumCorrections) },
                                set: { minimumCorrections = $0 }
                            )) {
                                Text("1 correction").tag(1)
                                Text("2 corrections").tag(2)
                                Text("3 corrections").tag(3)
                            }
                            .labelsHidden()
                            .onChange(of: minimumCorrections) { _, _ in
                                Task { await AutoLearnService.shared.suggestionThresholdDidChange() }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Suggest after")
                                InfoTip("Increase this number to show fewer suggestions. A suggestion appears only after you make the same correction this many times.")
                            }
                        }
                    }

                    if dataHealth.needsRepair {
                        Label("Auto-Learn data needs repair.", systemImage: "exclamationmark.triangle")
                        Button("Repair Auto-Learn") { showRepairConfirmation = true }
                            .disabled(isCheckingData || isRepairingData)
                        if isRepairingData {
                            ProgressView().controlSize(.small)
                                .accessibilityLabel("Repairing Auto-Learn")
                        }
                    } else if isAutoLearnDictionaryEnabled, hasAutoLearnFailure, repairError == nil {
                        Text(autoLearnFailureMessage.isEmpty
                            ? String(localized: "Auto-Learn is unavailable.") : autoLearnFailureMessage)
                            .foregroundStyle(.secondary)
                    }
                    if let repairError {
                        Text(repairError).foregroundStyle(.red)
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
        .task { await checkAutoLearnData() }
        .onChange(of: hasAutoLearnFailure) { _, failed in
            if failed { Task { await checkAutoLearnData() } }
        }
        .onChange(of: autoLearnFailureMessage) { _, _ in
            Task { await checkAutoLearnData() }
        }
        .alert("Repair Auto-Learn?", isPresented: $showRepairConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Repair", role: .destructive) {
                Task { await repairAutoLearnData() }
            }
        } message: {
            if dataHealth.resetsDismissals {
                Text("Repair backs up damaged Auto-Learn data and resets it. Saved dictionary entries are kept. Previously dismissed suggestions may appear again.")
            } else {
                Text("Repair backs up damaged Auto-Learn data and resets it. Saved dictionary entries are kept.")
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

    @MainActor
    private func checkAutoLearnData() async {
        guard !isRepairingData else { return }
        if isCheckingData {
            needsDataCheck = true
            return
        }
        isCheckingData = true
        defer { isCheckingData = false }
        repeat {
            needsDataCheck = false
            do {
                dataHealth = try await AutoLearnService.shared.checkDataHealth()
                repairError = nil
            } catch {
                dataHealth = AutoLearnDataHealth()
                repairError = error.localizedDescription
            }
        } while needsDataCheck && !Task.isCancelled
    }

    @MainActor
    private func repairAutoLearnData() async {
        guard !isRepairingData else { return }
        isRepairingData = true
        repairError = nil
        do {
            try await AutoLearnService.shared.repairData()
            isRepairingData = false
            await checkAutoLearnData()
        } catch {
            isRepairingData = false
            repairError = error.localizedDescription
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

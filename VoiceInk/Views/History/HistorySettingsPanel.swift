import SwiftData
import SwiftUI

struct HistorySettingsPanel: View {
    @Environment(\.modelContext) private var modelContext

    let onClose: () -> Void

    @AppStorage(CleanupSettingsKeys.isTranscriptionCleanupEnabled) private var isTranscriptionCleanupEnabled = false
    @AppStorage(CleanupSettingsKeys.transcriptionRetentionMinutes) private var transcriptionRetentionMinutes = 24 * 60
    @AppStorage(CleanupSettingsKeys.isAudioCleanupEnabled) private var isAudioCleanupEnabled = false
    @AppStorage(CleanupSettingsKeys.audioRetentionPeriod) private var audioRetentionPeriod = 7

    @State private var isPerformingAudioCleanup = false
    @State private var isShowingAudioConfirmation = false
    @State private var cleanupInfo: (fileCount: Int, totalSize: Int64, transcriptions: [Transcription]) = (0, 0, [])
    @State private var showAudioCleanupResult = false
    @State private var audioCleanupResult: (deletedCount: Int, errorCount: Int) = (0, 0)
    @State private var showTranscriptCleanupResult = false
    @State private var transcriptCleanupResult = TranscriptionCleanupResult(
        deletedCount: 0,
        audioFileErrorCount: 0,
        errorMessage: nil
    )
    @State private var isPerformingTranscriptCleanup = false
    @State private var showEnableTranscriptCleanupConfirmation = false
    @State private var showManualTranscriptCleanupConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "History Settings", onClose: onClose)

            Form {
                Section {
                    Toggle("Auto-delete Transcript History", isOn: transcriptCleanupEnabledBinding)
                        .disabled(isPerformingTranscriptCleanup)

                    if isTranscriptionCleanupEnabled {
                        Picker("Delete After", selection: $transcriptionRetentionMinutes) {
                            Text("Immediately").tag(0)
                            Text("1 hour").tag(60)
                            Text("1 day").tag(24 * 60)
                            Text("3 days").tag(3 * 24 * 60)
                            Text("7 days").tag(7 * 24 * 60)
                        }
                        .disabled(isPerformingTranscriptCleanup)

                        Button {
                            showManualTranscriptCleanupConfirmation = true
                        } label: {
                            Text(isPerformingTranscriptCleanup ? "Deleting Transcript History..." : "Run Cleanup Now")
                        }
                        .disabled(isPerformingTranscriptCleanup)
                    }
                } header: {
                    sectionHeader(
                        "Transcript History",
                        tip: "Delete transcript history and related audio files after the retention period."
                    )
                }

                if !isTranscriptionCleanupEnabled {
                    Section {
                        Toggle("Auto-delete Audio Files", isOn: $isAudioCleanupEnabled)

                        if isAudioCleanupEnabled {
                            Picker("Keep Audio For", selection: $audioRetentionPeriod) {
                                Text("1 day").tag(1)
                                Text("3 days").tag(3)
                                Text("7 days").tag(7)
                                Text("14 days").tag(14)
                                Text("30 days").tag(30)
                            }

                            Button {
                                analyzeAudioCleanup()
                            } label: {
                                Text(isPerformingAudioCleanup ? "Analyzing..." : "Run Cleanup Now")
                            }
                            .disabled(isPerformingAudioCleanup)
                        }
                    } header: {
                        sectionHeader(
                            "Audio Files",
                            tip: "Delete old recordings while keeping transcript history."
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Transcript Cleanup", isPresented: $showTranscriptCleanupResult) {
            Button("Done", role: .cancel) {}
        } message: {
            if let errorMessage = transcriptCleanupResult.errorMessage {
                Text(errorMessage)
            } else if transcriptCleanupResult.audioFileErrorCount > 0 {
                Text(partialTranscriptCleanupMessage)
            } else if transcriptCleanupResult.deletedCount == 0 {
                Text("No transcripts were old enough to delete.")
            } else {
                Text(successfulTranscriptCleanupMessage)
            }
        }
        .alert("Enable Transcript Auto-Delete?", isPresented: $showEnableTranscriptCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Enable Auto-Delete", role: .destructive) {
                enableTranscriptCleanup()
            }
        } message: {
            Text("Existing transcripts older than the selected retention period and their saved audio files will be permanently deleted. This action cannot be undone.")
        }
        .alert("Delete Old Transcript History?", isPresented: $showManualTranscriptCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Old Transcripts", role: .destructive) {
                runTranscriptCleanup()
            }
        } message: {
            Text("This will permanently delete transcripts older than the selected retention period and their saved audio files. This action cannot be undone.")
        }
        .alert("Audio Cleanup", isPresented: $isShowingAudioConfirmation) {
            Button("Cancel", role: .cancel) {}

            if cleanupInfo.fileCount > 0 {
                Button(String(localized: "Delete \(cleanupInfo.fileCount) Files"), role: .destructive) {
                    runAudioCleanup()
                }
            }
        } message: {
            if cleanupInfo.fileCount > 0 {
                Text(
                    String(
                        localized:
                            "This will delete \(cleanupInfo.fileCount) audio files (\(AudioCleanupManager.shared.formatFileSize(cleanupInfo.totalSize)))."
                    ))
            } else {
                Text(String(localized: "No audio files found older than \(audioRetentionPeriod) days."))
            }
        }
        .alert("Cleanup Complete", isPresented: $showAudioCleanupResult) {
            Button("OK", role: .cancel) {}
        } message: {
            if audioCleanupResult.errorCount > 0 {
                Text(
                    String(
                        format: String(localized: "Deleted files: %lld. Failed: %lld."),
                        Int64(audioCleanupResult.deletedCount), Int64(audioCleanupResult.errorCount)))
            } else {
                Text(String(localized: "Deleted \(audioCleanupResult.deletedCount) audio files."))
            }
        }
        .onChange(of: isAudioCleanupEnabled) { _, newValue in
            guard !isTranscriptionCleanupEnabled else {
                if newValue {
                    isAudioCleanupEnabled = false
                }
                AudioCleanupManager.shared.stopAutomaticCleanup()
                return
            }

            if newValue {
                AudioCleanupManager.shared.startAutomaticCleanup(modelContext: modelContext)
            } else {
                AudioCleanupManager.shared.stopAutomaticCleanup()
            }
        }
    }

    private var transcriptCleanupEnabledBinding: Binding<Bool> {
        Binding(
            get: { isTranscriptionCleanupEnabled },
            set: { newValue in
                if newValue {
                    showEnableTranscriptCleanupConfirmation = true
                } else {
                    isTranscriptionCleanupEnabled = false
                    if isAudioCleanupEnabled {
                        AudioCleanupManager.shared.startAutomaticCleanup(modelContext: modelContext)
                    }
                }
            }
        )
    }

    private func enableTranscriptCleanup() {
        isAudioCleanupEnabled = false
        AudioCleanupManager.shared.stopAutomaticCleanup()
        isTranscriptionCleanupEnabled = true
        runTranscriptCleanup()
    }

    private var successfulTranscriptCleanupMessage: String {
        if transcriptCleanupResult.deletedCount == 1 {
            return String(localized: "Deleted 1 transcript.")
        }
        return String(
            localized: "Deleted \(transcriptCleanupResult.deletedCount) transcripts."
        )
    }

    private var partialTranscriptCleanupMessage: String {
        if transcriptCleanupResult.deletedCount == 1 && transcriptCleanupResult.audioFileErrorCount == 1 {
            return String(
                localized:
                    "Deleted 1 transcript, but couldn't delete its saved audio file. Try again or export logs from Settings."
            )
        }
        return String(
            localized:
                "Deleted \(transcriptCleanupResult.deletedCount) transcripts, but couldn't delete \(transcriptCleanupResult.audioFileErrorCount) saved audio files. Try again or export logs from Settings."
        )
    }

    private func runTranscriptCleanup() {
        isPerformingTranscriptCleanup = true
        Task { @MainActor in
            transcriptCleanupResult = await TranscriptionAutoCleanupService.shared.runManualCleanup(
                modelContext: modelContext
            )
            isPerformingTranscriptCleanup = false
            showTranscriptCleanupResult = true
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, tip: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(title)

            InfoTip(message: tip, iconSize: .small, iconColor: .secondary, width: 260)
        }
    }

    private func analyzeAudioCleanup() {
        Task {
            await MainActor.run { isPerformingAudioCleanup = true }
            let info = await AudioCleanupManager.shared.getCleanupInfo(modelContext: modelContext)
            await MainActor.run {
                cleanupInfo = info
                isPerformingAudioCleanup = false
                isShowingAudioConfirmation = true
            }
        }
    }

    private func runAudioCleanup() {
        Task {
            await MainActor.run { isPerformingAudioCleanup = true }
            let result = await AudioCleanupManager.shared.runCleanupForTranscriptions(
                modelContext: modelContext,
                transcriptions: cleanupInfo.transcriptions
            )
            await MainActor.run {
                audioCleanupResult = result
                isPerformingAudioCleanup = false
                showAudioCleanupResult = true
            }
        }
    }
}

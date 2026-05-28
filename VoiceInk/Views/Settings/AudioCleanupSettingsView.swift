import SwiftUI
import SwiftData

struct AudioCleanupSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // Audio cleanup settings
    @AppStorage("IsTranscriptionCleanupEnabled") private var isTranscriptionCleanupEnabled = false
    @AppStorage("TranscriptionRetentionMinutes") private var transcriptionRetentionMinutes = 24 * 60
    @AppStorage("IsAudioCleanupEnabled") private var isAudioCleanupEnabled = false
    @AppStorage("AudioRetentionPeriod") private var audioRetentionPeriod = 7
    @State private var isPerformingCleanup = false
    @State private var isShowingConfirmation = false
    @State private var cleanupInfo: (fileCount: Int, totalSize: Int64, transcriptions: [Transcription]) = (0, 0, [])
    @State private var showResultAlert = false
    @State private var cleanupResult: (deletedCount: Int, errorCount: Int) = (0, 0)
    @State private var showTranscriptCleanupResult = false

    // Expansion states - collapsed by default
    @State private var isTranscriptExpanded = false
    @State private var isAudioExpanded = false

    var body: some View {
        Group {
            ExpandableSettingsRow(
                isExpanded: $isTranscriptExpanded,
                isEnabled: $isTranscriptionCleanupEnabled,
                label: "Auto-delete Transcripts",
                infoMessage: "Automatically delete transcript history based on the retention period you set."
            ) {
                transcriptCleanupControls
            }
            .alert("Transcript Cleanup", isPresented: $showTranscriptCleanupResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Cleanup complete.")
            }
            .onChange(of: isTranscriptionCleanupEnabled) { _, newValue in
                if newValue {
                    AudioCleanupManager.shared.stopAutomaticCleanup()
                } else if isAudioCleanupEnabled {
                    AudioCleanupManager.shared.startAutomaticCleanup(modelContext: modelContext)
                }
            }

            if !isTranscriptionCleanupEnabled {
                ExpandableSettingsRow(
                    isExpanded: $isAudioExpanded,
                    isEnabled: $isAudioCleanupEnabled,
                    label: "Auto-delete Audio Files",
                    infoMessage: "Automatically delete audio recordings while keeping text transcripts intact."
                ) {
                    audioCleanupControls
                }
                .alert("Audio Cleanup", isPresented: $isShowingConfirmation) {
                    Button("Cancel", role: .cancel) { }

                    if cleanupInfo.fileCount > 0 {
                        Button("Delete \(cleanupInfo.fileCount) Files", role: .destructive) {
                            Task {
                                await MainActor.run { isPerformingCleanup = true }
                                let result = await AudioCleanupManager.shared.runCleanupForTranscriptions(
                                    modelContext: modelContext,
                                    transcriptions: cleanupInfo.transcriptions
                                )
                                await MainActor.run {
                                    cleanupResult = result
                                    isPerformingCleanup = false
                                    showResultAlert = true
                                }
                            }
                        }
                    }
                } message: {
                    if cleanupInfo.fileCount > 0 {
                        Text("This will delete \(cleanupInfo.fileCount) audio files (\(AudioCleanupManager.shared.formatFileSize(cleanupInfo.totalSize))).")
                    } else {
                        Text("No audio files found older than \(audioRetentionPeriod) day\(audioRetentionPeriod > 1 ? "s" : "").")
                    }
                }
                .alert("Cleanup Complete", isPresented: $showResultAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    if cleanupResult.errorCount > 0 {
                        Text("Deleted \(cleanupResult.deletedCount) files. Failed: \(cleanupResult.errorCount).")
                    } else {
                        Text("Deleted \(cleanupResult.deletedCount) audio files.")
                    }
                }
            }
        }
    }

    private var transcriptCleanupControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Delete After", selection: $transcriptionRetentionMinutes) {
                Text("Immediately").tag(0)
                Text("1 hour").tag(60)
                Text("1 day").tag(24 * 60)
                Text("3 days").tag(3 * 24 * 60)
                Text("7 days").tag(7 * 24 * 60)
            }

            Button("Run Cleanup Now") {
                Task {
                    await TranscriptionAutoCleanupService.shared.runManualCleanup(modelContext: modelContext)
                    await MainActor.run {
                        showTranscriptCleanupResult = true
                    }
                }
            }
        }
    }

    private var audioCleanupControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Keep Audio For", selection: $audioRetentionPeriod) {
                Text("1 day").tag(1)
                Text("3 days").tag(3)
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
            }

            Button(isPerformingCleanup ? "Analyzing..." : "Run Cleanup Now") {
                Task {
                    await MainActor.run { isPerformingCleanup = true }
                    let info = await AudioCleanupManager.shared.getCleanupInfo(modelContext: modelContext)
                    await MainActor.run {
                        cleanupInfo = info
                        isPerformingCleanup = false
                        isShowingConfirmation = true
                    }
                }
            }
            .disabled(isPerformingCleanup)
        }
    }
}

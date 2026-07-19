import SwiftData
import SwiftUI

// The review UI for ADR-0009's golden eval set. VoiceInk already saves every recording's
// audio, so this is a browse-and-verify tool over existing Transcriptions, not a recorder:
// pick a candidate, listen, correct the ground-truth text if VoiceInk got it wrong, assign it
// to the train or held-out eval split, save. Deliberately does not pre-fill from flagged
// transcriptions or otherwise auto-suggest a split — ADR-0009 calls that out explicitly as a
// tempting shortcut that undermines the measurement.
struct GoldenEvalSetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transcription.timestamp, order: .reverse) private var allTranscriptions: [Transcription]

    @State private var selectedTranscription: Transcription?
    @State private var groundTruthText: String = ""
    @State private var selectedSplit: GoldenEvalSplit = .eval
    @State private var existingEntry: GoldenEvalEntry?
    @State private var counts = GoldenEvalSetService.SplitCounts(train: 0, eval: 0)
    @State private var errorMessage: String?

    private var candidates: [Transcription] {
        allTranscriptions.filter { GoldenEvalSetView.hasAudioFile($0) }
    }

    static func hasAudioFile(_ transcription: Transcription) -> Bool {
        guard let urlString = transcription.audioFileURL, let url = URL(string: urlString) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    var body: some View {
        NavigationSplitView {
            List(candidates, selection: $selectedTranscription) { transcription in
                candidateRow(transcription).tag(transcription)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let transcription = selectedTranscription {
                reviewPanel(for: transcription)
                    .id(transcription.id)
            } else {
                ContentUnavailableView(
                    "Select a Recording",
                    systemImage: "checklist",
                    description: Text("Pick a recording on the left to review it for the golden eval set.")
                )
            }
        }
        .navigationTitle("Golden Eval Set")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Train: \(counts.train) · Eval: \(counts.eval)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear(perform: refreshCounts)
        .onChange(of: selectedTranscription) { _, newValue in
            loadEntry(for: newValue)
        }
    }

    private func candidateRow(_ transcription: Transcription) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text(transcription.enhancedText ?? transcription.text)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            Spacer()
            if let split = splitBadge(for: transcription) {
                Text(split == .train ? "Train" : "Eval")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(split == .train ? AppTheme.Status.infoStrong : AppTheme.Status.positive)
                    )
                    .foregroundColor(.white)
            }
        }
    }

    private func splitBadge(for transcription: Transcription) -> GoldenEvalSplit? {
        try? GoldenEvalSetService.entry(for: transcription.id, in: modelContext)?.split
    }

    private func reviewPanel(for transcription: Transcription) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let urlString = transcription.audioFileURL, let url = URL(string: urlString) {
                    AudioPlayerView(url: url, transcription: transcription)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("VoiceInk's transcript")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(transcription.enhancedText ?? transcription.text)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .fill(AppTheme.Surface.subtle)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ground truth (edit if VoiceInk got it wrong)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextEditor(text: $groundTruthText)
                        .font(.system(size: 13))
                        .frame(minHeight: 100)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .fill(AppTheme.Surface.materialCard)
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                        .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
                                }
                        )
                }

                Picker("Split", selection: $selectedSplit) {
                    Text("Held-out Eval").tag(GoldenEvalSplit.eval)
                    Text("Train").tag(GoldenEvalSplit.train)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack {
                    Button(existingEntry == nil ? "Add to Golden Eval Set" : "Update Entry") {
                        save(for: transcription)
                    }
                    .buttonStyle(.borderedProminent)

                    if existingEntry != nil {
                        Button("Remove", role: .destructive) {
                            remove(for: transcription)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Status.error)
                }
            }
            .padding(20)
        }
    }

    private func loadEntry(for transcription: Transcription?) {
        errorMessage = nil
        guard let transcription else {
            existingEntry = nil
            groundTruthText = ""
            return
        }

        do {
            let entry = try GoldenEvalSetService.entry(for: transcription.id, in: modelContext)
            existingEntry = entry
            groundTruthText = entry?.groundTruthText ?? (transcription.enhancedText ?? transcription.text)
            selectedSplit = entry?.split ?? .eval
        } catch {
            errorMessage = String(localized: "Failed to load existing entry")
        }
    }

    private func save(for transcription: Transcription) {
        do {
            existingEntry = try GoldenEvalSetService.save(
                transcriptionId: transcription.id,
                groundTruthText: groundTruthText,
                split: selectedSplit,
                in: modelContext
            )
            errorMessage = nil
            refreshCounts()
        } catch {
            errorMessage = String(localized: "Failed to save entry")
        }
    }

    private func remove(for transcription: Transcription) {
        do {
            try GoldenEvalSetService.remove(transcriptionId: transcription.id, in: modelContext)
            existingEntry = nil
            errorMessage = nil
            refreshCounts()
        } catch {
            errorMessage = String(localized: "Failed to remove entry")
        }
    }

    private func refreshCounts() {
        counts = (try? GoldenEvalSetService.splitCounts(in: modelContext)) ?? GoldenEvalSetService.SplitCounts(
            train: 0, eval: 0)
    }
}

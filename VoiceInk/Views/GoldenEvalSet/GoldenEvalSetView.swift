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
    @EnvironmentObject private var engine: VoiceInkEngine
    @Query(sort: \Transcription.timestamp, order: .reverse) private var allTranscriptions: [Transcription]

    @State private var selectedTranscription: Transcription?
    @State private var groundTruthText: String = ""
    @State private var selectedSplit: GoldenEvalSplit = .eval
    @State private var existingEntry: GoldenEvalEntry?
    @State private var counts = GoldenEvalSetService.SplitCounts(train: 0, eval: 0)
    @State private var errorMessage: String?

    @State private var isShowingBaselineSheet = false
    @State private var isRunningBaseline = false
    @State private var baselineSummaries: [WERBaselineHarness.ModelSummary] = []
    @State private var baselineError: String?

    // The two candidates in ADR-0009's bake-off. Matched by displayName against the live
    // registry rather than hardcoded model structs, so this stays correct if model metadata
    // (size/speed/accuracy) changes upstream.
    private static let baselineModelDisplayNames = ["Large v3", "Parakeet V3"]

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
            ToolbarItem(placement: .primaryAction) {
                Button("Run Baseline Evaluation") {
                    isShowingBaselineSheet = true
                }
                .disabled(counts.eval == 0)
            }
        }
        .onAppear(perform: refreshCounts)
        .onChange(of: selectedTranscription) { _, newValue in
            loadEntry(for: newValue)
        }
        .sheet(isPresented: $isShowingBaselineSheet) {
            baselineEvaluationSheet
        }
    }

    private var baselineEvaluationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Baseline WER Evaluation")
                .font(.system(size: 15, weight: .semibold))

            Text(
                "Runs every held-out eval-split recording (\(counts.eval)) through \(Self.baselineModelDisplayNames.joined(separator: " and ")), scoring each against its verified ground truth. Requires both models' weights to already be downloaded."
            )
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if isRunningBaseline {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Evaluating…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            if let baselineError {
                Text(baselineError)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Status.error)
            }

            if !baselineSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(baselineSummaries, id: \.modelDisplayName) { summary in
                        HStack {
                            Text(summary.modelDisplayName)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(String(format: "%.1f%% WER", summary.meanWordErrorRate * 100))
                                .font(.system(size: 13, weight: .semibold))
                            Text("(\(summary.evaluatedCount) evaluated, \(summary.failedCount) failed)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .fill(AppTheme.Surface.subtle)
                        )
                    }
                }
            }

            HStack {
                Button(baselineSummaries.isEmpty ? "Run Now" : "Run Again") {
                    runBaselineEvaluation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunningBaseline)

                Button("Close") {
                    isShowingBaselineSheet = false
                }
            }
        }
        .padding(20)
        .frame(minWidth: 480)
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

    @MainActor
    private func runBaselineEvaluation() {
        baselineError = nil
        isRunningBaseline = true

        Task { @MainActor in
            defer { isRunningBaseline = false }

            do {
                let evalRawValue = GoldenEvalSplit.eval.rawValue
                let evalEntries = try modelContext.fetch(
                    FetchDescriptor<GoldenEvalEntry>(
                        predicate: #Predicate<GoldenEvalEntry> { $0.splitRawValue == evalRawValue }))

                var evalCandidates: [WERBaselineHarness.Candidate] = []
                for entry in evalEntries {
                    let transcriptionId = entry.transcriptionId
                    var descriptor = FetchDescriptor<Transcription>(
                        predicate: #Predicate<Transcription> { $0.id == transcriptionId })
                    descriptor.fetchLimit = 1
                    guard let transcription = try modelContext.fetch(descriptor).first,
                        let urlString = transcription.audioFileURL,
                        let url = URL(string: urlString)
                    else { continue }

                    evalCandidates.append(
                        WERBaselineHarness.Candidate(
                            entryId: entry.id, referenceText: entry.groundTruthText, audioURL: url))
                }

                guard !evalCandidates.isEmpty else {
                    baselineError = String(localized: "No eval-split entries with a valid audio file were found.")
                    return
                }

                let models = Self.baselineModelDisplayNames.compactMap { name in
                    TranscriptionModelRegistry.models.first { $0.displayName == name }
                }

                guard !models.isEmpty else {
                    baselineError = String(localized: "Could not find the baseline models in the model registry.")
                    return
                }

                let transcriber = TranscriptionServiceRegistryTranscriber(registry: engine.serviceRegistry)
                let runLabel = "baseline-\(Int(Date().timeIntervalSince1970))"

                baselineSummaries = await WERBaselineHarness.run(
                    candidates: evalCandidates,
                    models: models,
                    runLabel: runLabel,
                    transcriber: transcriber,
                    in: modelContext
                )
            } catch {
                baselineError = String(localized: "Failed to run baseline evaluation.")
            }
        }
    }
}

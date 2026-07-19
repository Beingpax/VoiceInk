import SwiftData
import SwiftUI

struct TranscriptionDetailView: View {
    let transcription: Transcription
    var onInfoTap: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var groundTruthText: String = ""
    @State private var goldenEvalEntry: GoldenEvalEntry?
    @State private var goldenEvalErrorMessage: String?

    private var hasAudioFile: Bool {
        if let urlString = transcription.audioFileURL,
            let url = URL(string: urlString),
            FileManager.default.fileExists(atPath: url.path)
        {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 16) {
                    MessageBubble(
                        label: "Original",
                        text: transcription.text,
                        isEnhanced: false,
                        transcriptionId: transcription.id
                    )

                    if let enhancedText = transcription.enhancedText {
                        MessageBubble(
                            label: "Enhanced",
                            text: enhancedText,
                            isEnhanced: true,
                            transcriptionId: transcription.id
                        )
                    }

                    if hasAudioFile {
                        goldenEvalSetSection
                    }
                }
                .padding(16)
            }

            if hasAudioFile, let urlString = transcription.audioFileURL,
                let url = URL(string: urlString)
            {
                VStack(spacing: 0) {
                    Divider()

                    AudioPlayerView(url: url, transcription: transcription, onInfoTap: onInfoTap)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .fill(AppTheme.Surface.materialCard)
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                        .strokeBorder(AppTheme.Border.card, lineWidth: 1)
                                }
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 12)
        .onAppear(perform: loadGoldenEvalEntry)
    }

    // Inline golden eval set panel (ADR-0009, PRD.md "Golden eval set / WER tooling UI
    // integration") — folded into the existing detail view rather than a separate window.
    // No train/eval/control picker: GoldenEvalSetService.verify categorizes automatically
    // based on whether groundTruthText differs from VoiceInk's original transcript.
    private var goldenEvalSetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Golden Eval Set")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if let goldenEvalEntry {
                    Text(splitLabel(goldenEvalEntry.split))
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(splitColor(goldenEvalEntry.split)))
                        .foregroundColor(.white)
                }
            }

            Text("Ground truth (edit if VoiceInk got it wrong, then mark verified)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            TextEditor(text: $groundTruthText)
                .font(.system(size: 13))
                .frame(minHeight: 80)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .fill(AppTheme.Surface.materialCard)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
                        }
                )

            HStack {
                Button(goldenEvalEntry == nil ? "Mark Verified" : "Update") {
                    verifyGoldenEval()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if goldenEvalEntry != nil {
                    Button("Remove", role: .destructive) {
                        removeGoldenEval()
                    }
                    .controlSize(.small)
                }

                if let goldenEvalErrorMessage {
                    Text(goldenEvalErrorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Status.error)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Surface.subtle)
        )
    }

    private func splitLabel(_ split: GoldenEvalSplit) -> String {
        switch split {
        case .control: return "Control"
        case .train: return "Train"
        case .eval: return "Eval"
        }
    }

    private func splitColor(_ split: GoldenEvalSplit) -> Color {
        switch split {
        case .control: return AppTheme.Data.purple
        case .train: return AppTheme.Status.infoStrong
        case .eval: return AppTheme.Status.positive
        }
    }

    private func loadGoldenEvalEntry() {
        goldenEvalErrorMessage = nil
        do {
            let entry = try GoldenEvalSetService.entry(for: transcription.id, in: modelContext)
            goldenEvalEntry = entry
            groundTruthText = entry?.groundTruthText ?? (transcription.enhancedText ?? transcription.text)
        } catch {
            goldenEvalErrorMessage = String(localized: "Failed to load golden eval entry")
        }
    }

    private func verifyGoldenEval() {
        do {
            goldenEvalEntry = try GoldenEvalSetService.verify(
                transcriptionId: transcription.id,
                originalText: transcription.enhancedText ?? transcription.text,
                groundTruthText: groundTruthText,
                in: modelContext
            )
            goldenEvalErrorMessage = nil
        } catch {
            goldenEvalErrorMessage = String(localized: "Failed to save golden eval entry")
        }
    }

    private func removeGoldenEval() {
        do {
            try GoldenEvalSetService.remove(transcriptionId: transcription.id, in: modelContext)
            goldenEvalEntry = nil
            goldenEvalErrorMessage = nil
        } catch {
            goldenEvalErrorMessage = String(localized: "Failed to remove golden eval entry")
        }
    }
}

private struct MessageBubble: View {
    let label: LocalizedStringKey
    let text: String
    let isEnhanced: Bool
    let transcriptionId: UUID

    var body: some View {
        HStack(alignment: .bottom) {
            if isEnhanced { Spacer(minLength: 60) }

            VStack(alignment: isEnhanced ? .leading : .trailing, spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AppTheme.Text.muted)
                    .padding(.horizontal, 12)

                ScrollView {
                    MarkdownContentView(
                        text,
                        fontSize: 14,
                        foregroundColor: AppTheme.Text.primary,
                        alignment: isEnhanced ? .leading : .trailing
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 350)
                .background {
                    if isEnhanced {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .fill(AppTheme.Surface.subtle)
                            .overlay {
                                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                    .strokeBorder(AppTheme.Border.tint, lineWidth: 1)
                            }
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .fill(AppTheme.Surface.materialCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                    .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
                            )
                    }
                }
                .hoverCopyButton(
                    textToCopy: text, transcriptionId: transcriptionId, telemetrySource: "hover_button")
            }

            if !isEnhanced { Spacer(minLength: 60) }
        }
    }

}

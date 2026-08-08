import SwiftUI

/// What was just delivered, offered back for a few seconds so a bad take can be recovered.
///
/// The peek *follows* the paste rather than gating it — the text lands immediately and this is an
/// undo affordance, not a confirmation step. Before this, a transcript that went into the wrong
/// app or came back mangled could only be fixed by dictating the whole thing again.
struct RecorderResultPeek: Equatable, Identifiable {
    let id = UUID()
    let pastedText: String
    let originalText: String
    let hasEnhancement: Bool
    let duration: TimeInterval
    let modeName: String?
    /// The app the text was pasted into. Clicking a peek button makes the recorder panel key,
    /// which pulls focus away — without restoring it first, Cmd+Z lands on the panel instead of
    /// the editor and Undo silently does nothing.
    let targetBundleIdentifier: String?
    /// Dictionary terms that actually fired on this transcript. Confirms the dictionary is doing
    /// something — previously replacements ran invisibly.
    var appliedVocabularyTerms: [String] = []

    var wordCount: Int {
        pastedText.split(whereSeparator: \.isWhitespace).count
    }

    /// Only worth offering the original when enhancement actually changed something.
    var canShowOriginal: Bool {
        hasEnhancement && originalText != pastedText && !originalText.isEmpty
    }
}

struct RecorderResultPeekView: View {
    let peek: RecorderResultPeek
    let onUndo: () -> Void
    let onRetry: () -> Void
    let onShowOriginal: () -> Void
    let onDismiss: () -> Void
    /// Hovering pauses the auto-dismiss countdown — reading it should not cost you the chance to act.
    let onHoverChange: (Bool) -> Void

    @State private var showingOriginal = false

    private var displayedText: String {
        showingOriginal ? peek.originalText : peek.pastedText
    }

    private var summary: String {
        var parts: [String] = [peek.duration.formatTiming()]
        parts.append(
            String(
                format: String(localized: "%lld words"),
                Int64(peek.wordCount)
            )
        )
        if let modeName = peek.modeName {
            parts.append(modeName)
        }
        if !peek.appliedVocabularyTerms.isEmpty {
            parts.append(
                String(
                    format: String(localized: "%lld dictionary terms"),
                    Int64(peek.appliedVocabularyTerms.count)
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayedText)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Recorder.labelSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text(summary)
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Recorder.labelTertiary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if peek.canShowOriginal {
                    PeekButton(
                        title: showingOriginal ? "Enhanced" : "Original",
                        isPrimary: false
                    ) {
                        showingOriginal.toggle()
                        onShowOriginal()
                    }
                }

                PeekButton(title: "Retry", isPrimary: false, action: onRetry)
                PeekButton(title: "Undo", isPrimary: true, action: onUndo)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onHover(perform: onHoverChange)
        .onExitCommand(perform: onDismiss)
    }
}

private struct PeekButton: View {
    let title: LocalizedStringKey
    var isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isPrimary ? .semibold : .medium))
                .foregroundStyle(
                    isPrimary ? Color.black.opacity(0.85) : AppTheme.Recorder.labelSecondary
                )
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(
                    Capsule().fill(
                        isPrimary ? AppTheme.Recorder.sendEnabled : AppTheme.Recorder.controlFill
                    )
                )
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

import SwiftUI

/// What the ambient light is saying, when light alone cannot say it.
///
/// Four things genuinely need words: an instruction you must act on, a decision about what leaves
/// your machine, how long a wait has left to run, and a result you might want to take back.
/// Everything else the glow already covers.
enum AmbientCaptionKind: Equatable {
    case problem(String)
    case context(String)
    case countdown(Int)
    case result(RecorderResultPeek)
    /// The take as it is being transcribed. Unlike the others this is continuous rather than an
    /// announcement, so it holds the slot for as long as the take runs.
    case liveTranscript(String)
    /// Where the wait is up to. `remaining` is nil when this model has no history to predict from.
    case processing(title: LocalizedStringKey, remaining: TimeInterval?, basis: String?)

    var isInteractive: Bool {
        if case .result = self { return true }
        if case .countdown = self { return true }
        return false
    }
}

/// The panel for ambient mode — deliberately not a panel.
///
/// A capsule with a border and a fill would just be the mini recorder wearing a glow, and would
/// undo the entire premise: ambient exists so there is no chrome sitting on top of your work. So
/// this has **no container at all**. It is illuminated text hanging under the notch, lit by the
/// same light the border is made of — as though the halo condensed enough to be read.
///
/// Three rules keep it from drifting back into being a panel:
///   * no fill, no border, no shadow — only a soft bloom behind the glyphs
///   * it inherits the ambient state colour rather than owning one
///   * it grows out of the notch, so it reads as the light thickening rather than a window opening
struct AmbientCaption: View {
    let kind: AmbientCaptionKind
    let tint: Color
    var palette = AmbientPalette(isLight: false)
    let onUndo: () -> Void
    let onRetry: () -> Void
    let onKeepRecording: () -> Void

    @State private var showingOriginal = false

    var body: some View {
        VStack(spacing: 7) {
            content
        }
        .ambientTextBloom(tint: tint, fill: palette.bloomFill, opacity: palette.isLight ? 0.82 : 0.55)
        .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .problem(let message):
            captionText(message, weight: .medium)

        case .context(let message):
            captionText(message, weight: .regular)

        case .liveTranscript(let transcript):
            AmbientLiveTranscript(text: transcript, tint: tint, palette: palette)

        case .processing(let title, let remaining, let basis):
            processing(title: title, remaining: remaining, basis: basis)

        case .countdown(let seconds):
            captionText(
                String(format: String(localized: "Silent — stopping in %lld"), Int64(seconds)),
                weight: .medium
            )
            AmbientTextButton(title: "Keep recording", tint: tint, action: onKeepRecording)

        case .result(let peek):
            result(peek)
        }
    }

    // MARK: - Processing

    /// The number is the point. An indeterminate spinner and a predicted wait cost the same amount
    /// of screen, and only one of them lets you decide whether to sit and watch it.
    @ViewBuilder
    private func processing(
        title: LocalizedStringKey, remaining: TimeInterval?, basis: String?
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.textPrimary)

            if let remaining, remaining > 0.4 {
                Text(String(format: String(localized: "~%@ left"), remaining.formatTiming()))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
        }
        .shadow(color: palette.textShadow, radius: 2, y: 1)
        .shadow(color: tint.opacity(0.45), radius: 9)

        // Provenance, so the estimate is attributable rather than mysterious.
        if let basis {
            Text(basis)
                .font(.system(size: 9.5))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Result

    /// The moment the take lands is the one moment there is something to say about it, so this is
    /// the one caption allowed to be more than a line. It also sits under the finished waveform,
    /// which is what stops it reading as a stray tooltip once the light has stopped moving.
    @ViewBuilder
    private func result(_ peek: RecorderResultPeek) -> some View {
        Text(showingOriginal ? peek.originalText : peek.pastedText)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(palette.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .frame(maxWidth: 560)
            .shadow(color: palette.textShadow, radius: 2, y: 1)
            .shadow(color: tint.opacity(0.4), radius: 9)

        Text(summary(for: peek))
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)

        HStack(spacing: 16) {
            AmbientTextButton(title: "Undo", tint: tint, action: onUndo)
            AmbientTextButton(title: "Retry", tint: tint, action: onRetry)

            // Only offered when enhancement actually changed something — otherwise it toggles
            // between two identical strings and teaches the user the control is broken.
            if peek.canShowOriginal {
                AmbientTextButton(
                    title: showingOriginal ? "Show enhanced" : "Show original",
                    tint: tint,
                    weight: .medium
                ) {
                    showingOriginal.toggle()
                }
            }
        }
    }

    /// Everything already recorded about the take and never shown here: how long it ran, how much
    /// came back, which mode produced it, and whether the dictionary fired.
    private func summary(for peek: RecorderResultPeek) -> String {
        var parts: [String] = [
            peek.duration.formatTiming(),
            String(format: String(localized: "%lld words"), Int64(peek.wordCount)),
        ]
        if let modeName = peek.modeName {
            parts.append(modeName)
        }
        if peek.hasEnhancement {
            parts.append(String(localized: "enhanced"))
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

    private func captionText(_ message: String, weight: Font.Weight) -> some View {
        Text(message)
            .font(.system(size: 12.5, weight: weight))
            .foregroundStyle(palette.textPrimary)
            .shadow(color: palette.textShadow, radius: 2, y: 1)
            .shadow(color: tint.opacity(0.6), radius: 10)
            .lineLimit(1)
    }
}

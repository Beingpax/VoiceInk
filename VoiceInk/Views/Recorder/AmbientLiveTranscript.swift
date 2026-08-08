import SwiftUI

/// The live transcript, for a surface that has no panel to put it in.
///
/// The mini and notch recorders scroll it inside a bordered box. That is the one thing ambient mode
/// cannot do, so this reaches for the property the rest of the design already runs on: age. The
/// crest fades older audio outward from the notch; the transcript fades older *words* the same way.
///
/// **Legibility is the hard part.** The first version glowed the whole line and let old words drop
/// to 10% white, and over a bright window it turned to fog. Two rules fixed it, and both are worth
/// keeping: the text needs a *dark* shadow before it needs a coloured one, because it sits over
/// arbitrary content and contrast is what makes glyphs sharp; and the fade has a floor, because a
/// word too dim to read is worse than no word at all — it still occupies the line and the eye still
/// tries.
///
/// Structure comes from three tiers rather than a smooth ramp: the word being spoken carries the
/// state colour, the recent tail is white, and older words recede to a readable grey. That reads as
/// a sentence assembling itself, and it tells you at a glance where the machine currently is.
struct AmbientLiveTranscript: View {
    let text: String
    let tint: Color
    var palette = AmbientPalette(isLight: false)

    /// Past this the tail is not being read anyway, and the line starts competing with the work
    /// underneath it.
    private let visibleWords = 16

    var body: some View {
        Text(tiered)
            .font(.system(size: 13.5, weight: .medium))
            .lineLimit(1)
            // Words leaving on the left are already at the fade floor, so the cut is never seen.
            .truncationMode(.head)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 760)
            // Dark first and tight — this is the one doing the work of making the glyphs readable.
            .shadow(color: palette.textShadow, radius: 2, y: 1)
            .shadow(color: palette.textShadow.opacity(0.5), radius: 6)
            // Then a restrained amount of the state colour, so the line still belongs to the light.
            .shadow(color: tint.opacity(0.3), radius: 7)
            .animation(.easeOut(duration: 0.16), value: text)
    }

    /// Per-word brightness as an attributed run, so the line still measures, wraps and truncates
    /// like ordinary text — an HStack of `Text` views does none of that.
    private var tiered: AttributedString {
        let words = text.split(whereSeparator: \.isWhitespace).suffix(visibleWords)
        guard !words.isEmpty else { return AttributedString() }

        var line = AttributedString()
        let newest = words.count - 1
        for (index, word) in words.enumerated() {
            var run = AttributedString(index == 0 ? String(word) : " " + String(word))

            if index == newest {
                run.foregroundColor = tint
            } else {
                let age = Double(index) / Double(max(newest, 1))
                let floor = palette.transcriptFadeFloor
                run.foregroundColor = palette.textPrimary.opacity(
                    floor + (1 - floor) * pow(age, 1.2))
            }
            line.append(run)
        }
        return line
    }
}

import SwiftUI

/// The live transcript, for a surface that has no panel to put it in.
///
/// The mini and notch recorders scroll it inside a bordered box. That is the one thing ambient mode
/// cannot do, so this reaches for the property the rest of the design already runs on: age. The
/// crest fades older audio outward from the notch; the transcript fades older *words* the same way.
/// The word being spoken is at full brightness, and everything behind it dims toward nothing.
///
/// The effect is that the sentence appears to be condensing out of the light as you say it, which
/// is the same claim the caption makes — that the glow thickened enough to be read.
///
/// Truncation is from the head. Words leaving on the left are already almost invisible by the time
/// they are cut, so the line never appears to jump.
struct AmbientLiveTranscript: View {
    let text: String
    let tint: Color

    /// Past this the tail is unreadable at a glance anyway, and the line starts competing with the
    /// work underneath it.
    private let visibleWords = 18

    var body: some View {
        Text(faded)
            .font(.system(size: 13, weight: .regular))
            .lineLimit(1)
            .truncationMode(.head)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 720)
            // One shadow for the whole line rather than per word: the glow is the light the text
            // is made of, and it should not flicker as words change brightness.
            .shadow(color: tint.opacity(0.55), radius: 11)
            .animation(.easeOut(duration: 0.18), value: text)
    }

    /// Per-word brightness as an attributed run, so the line still wraps, truncates and measures
    /// like ordinary text — an HStack of `Text` views does none of that.
    private var faded: AttributedString {
        let words = text.split(whereSeparator: \.isWhitespace).suffix(visibleWords)
        guard !words.isEmpty else { return AttributedString() }

        var line = AttributedString()
        for (index, word) in words.enumerated() {
            var run = AttributedString(index == 0 ? String(word) : " " + String(word))
            let age = Double(index) / Double(max(words.count - 1, 1))
            // Steep, so only the last handful of words are properly lit and the tail genuinely
            // recedes rather than sitting there as uniform grey.
            run.foregroundColor = Color.white.opacity(0.10 + 0.90 * pow(age, 1.8))
            line.append(run)
        }
        return line
    }
}

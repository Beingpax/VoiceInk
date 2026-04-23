import SwiftUI
import KeyboardShortcuts

struct EnhancementShortcutsView: View {
    var body: some View {
        VStack(spacing: 8) {
            // Toggle AI Enhancement
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 4) {
                    Text("Toggle AI Enhancement")
                        .font(.system(size: 13))

                    InfoTip(
                        "Quickly enable or disable AI enhancement while recording. Available only when VoiceInk is running and the recorder is visible.",
                        learnMoreURL: "https://tryvoiceink.com/docs/enhancement-shortcuts"
                    )
                }

                Spacer()

                KeyboardShortcuts.Recorder(for: .toggleEnhancement)
                    .controlSize(.small)
            }

            // Switch Enhancement Prompt
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 4) {
                    Text("Switch Enhancement Prompt")
                        .font(.system(size: 13))

                    InfoTip(
                        "Switch between your saved prompts using ⌘1 through ⌘0 to activate the corresponding prompt in the order they are saved. Available only when VoiceInk is running and the recorder is visible.",
                        learnMoreURL: "https://tryvoiceink.com/docs/enhancement-shortcuts"
                    )
                }

                Spacer()

                HStack(spacing: 4) {
                    KeyChip(label: "⌘")
                    KeyChip(label: "1 – 0")
                }
            }
        }
        .background(Color.clear)
    }
}

// MARK: - Supporting Views
private struct KeyChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        Color(NSColor.separatorColor).opacity(0.5),
                        lineWidth: 0.5
                    )
            )
    }
}

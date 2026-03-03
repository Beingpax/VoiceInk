import SwiftUI

struct TranscriptionDetailView: View {
    let transcription: Transcription

    private var hasAudioFile: Bool {
        if let urlString = transcription.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
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
                        isEnhanced: false
                    )

                    if let enhancedText = transcription.enhancedText {
                        MessageBubble(
                            label: "Enhanced",
                            text: enhancedText,
                            isEnhanced: true
                        )
                    }
                }
                .padding(16)
            }

            if hasAudioFile, let urlString = transcription.audioFileURL,
               let url = URL(string: urlString) {
                VStack(spacing: 0) {
                    Divider()

                    AudioPlayerView(url: url)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct MessageBubble: View {
    let label: String
    let text: String
    let isEnhanced: Bool
    @State private var justCopied = false

    var body: some View {
        HStack(alignment: .bottom) {
            if isEnhanced { Spacer(minLength: 60) }

            VStack(alignment: isEnhanced ? .leading : .trailing, spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 12)

                ScrollView {
                    Text(text)
                        .font(.system(size: 14, weight: .regular))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .frame(maxHeight: 350)
                .background {
                    if isEnhanced {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.accentColor.opacity(0.2))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                            )
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button(action: {
                        copyToClipboard(text)
                    }) {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(justCopied ? .green : .secondary)
                            .frame(width: 28, height: 28)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                    .padding(8)
                }
            }

            if !isEnhanced { Spacer(minLength: 60) }
        }
    }

    private func copyToClipboard(_ text: String) {
        let _ = ClipboardManager.copyToClipboard(text)

        withAnimation {
            justCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                justCopied = false
            }
        }
    }
}

import SwiftUI

/// Reusable component that displays transcription Details and AI Request sections.
/// Used in both the inline history side panel and the separate history window's metadata view.
struct TranscriptionInfoPanel: View {
    let transcription: Transcription

    var body: some View {
        Form {
            detailsSection
            aiRequestSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        Section {
            metadataRow(
                icon: "calendar",
                label: "Date",
                value: transcription.timestamp.formatted(date: .abbreviated, time: .shortened)
            )

            metadataRow(
                icon: "hourglass",
                label: "Duration",
                value: transcription.duration.formatTiming()
            )

            if let modelName = transcription.transcriptionModelName {
                metadataRow(
                    icon: "cpu.fill",
                    label: "Transcription Model",
                    value: modelName
                )

                if let duration = transcription.transcriptionDuration {
                    metadataRow(
                        icon: "clock.fill",
                        label: "Transcription Time",
                        value: duration.formatTiming()
                    )
                }
            }

            if let aiModel = transcription.aiEnhancementModelName {
                metadataRow(
                    icon: "sparkles",
                    label: "Enhancement Model",
                    value: aiModel
                )

                if let duration = transcription.enhancementDuration {
                    metadataRow(
                        icon: "clock.fill",
                        label: "Enhancement Time",
                        value: duration.formatTiming()
                    )
                }
            }

            if let promptName = transcription.promptName {
                metadataRow(
                    icon: "text.bubble.fill",
                    label: "Prompt",
                    value: promptName
                )
            }

            if let modeName = transcription.modeName {
                metadataRow(
                    icon: "bolt.fill",
                    label: "Mode",
                    value: modeName
                )
            }
        } header: {
            Text("Details")
        }
    }

    // MARK: - AI Request Section

    @ViewBuilder
    private var aiRequestSection: some View {
        if transcription.aiRequestSystemMessage != nil || transcription.aiRequestUserMessage != nil {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let systemMsg = transcription.aiRequestSystemMessage, !systemMsg.isEmpty {
                        requestMessageBlock(title: "System Prompt", message: systemMsg)
                    }

                    if let userMsg = transcription.aiRequestUserMessage, !userMsg.isEmpty {
                        requestMessageBlock(title: "User Message", message: userMsg)
                    }

                    aiRequestTokenEstimate
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hoverCopyButton(
                    textToCopy: fullRequestText,
                    alignment: .topTrailing,
                    padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                )
            } header: {
                Text("AI Request")
            }
        }
    }

    // MARK: - Helpers

    private var aiRequestTokenEstimate: some View {
        HStack(spacing: 6) {
            Image(systemName: "number")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Text("Around \(estimatedAIRequestTokenCount.formatted()) tokens")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        .help("Token count is estimated from the request text.")
    }

    private var estimatedAIRequestTokenCount: Int {
        EstimatedTokenCounter.count(
            in: [
                transcription.aiRequestSystemMessage,
                transcription.aiRequestUserMessage,
            ]
        ) ?? 0
    }

    private var fullRequestText: String {
        var parts: [String] = []
        if let sys = transcription.aiRequestSystemMessage, !sys.isEmpty {
            parts.append("System Prompt:\n\(sys)")
        }
        if let user = transcription.aiRequestUserMessage, !user.isEmpty {
            parts.append("User Message:\n\(user)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func requestMessageBlock(title: LocalizedStringKey, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text(message)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .lineSpacing(2)
                .textSelection(.enabled)
                .foregroundColor(.primary)
        }
    }

    private func metadataRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

}

import SwiftUI

/// Reusable component that displays transcription Details and AI Request sections.
/// Used in both the inline history sliding panel and the separate history window's metadata view.
struct TranscriptionInfoPanel: View {
    let transcription: Transcription

    var body: some View {
        Form {
            detailsSection
            aiRequestSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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

            if let powerModeValue = powerModeDisplay(
                name: transcription.powerModeName,
                emoji: transcription.powerModeEmoji
            ) {
                metadataRow(
                    icon: "bolt.fill",
                    label: "Power Mode",
                    value: powerModeValue
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
                if let systemMsg = transcription.aiRequestSystemMessage, !systemMsg.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("System Prompt")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(systemMsg)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .foregroundColor(.primary)
                    }
                }

                if let userMsg = transcription.aiRequestUserMessage, !userMsg.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("User Message")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(userMsg)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .foregroundColor(.primary)
                    }
                }
            } header: {
                HStack {
                    Text("AI Request")
                    Spacer()
                    CopyIconButton(textToCopy: fullRequestText)
                }
            }
        }
    }

    // MARK: - Helpers

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

    private func metadataRow(icon: String, label: String, value: String) -> some View {
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

    private func powerModeDisplay(name: String?, emoji: String?) -> String? {
        guard name != nil || emoji != nil else { return nil }

        switch (emoji?.trimmingCharacters(in: .whitespacesAndNewlines), name?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (.some(emojiValue), .some(nameValue)) where !emojiValue.isEmpty && !nameValue.isEmpty:
            return "\(emojiValue) \(nameValue)"
        case let (.some(emojiValue), _) where !emojiValue.isEmpty:
            return emojiValue
        case let (_, .some(nameValue)) where !nameValue.isEmpty:
            return nameValue
        default:
            return nil
        }
    }
}

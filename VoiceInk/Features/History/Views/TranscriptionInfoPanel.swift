import SwiftUI

struct TranscriptionInfoSidePanel: View {
    let transcription: Transcription
    let onClose: () -> Void

    var body: some View {
        QuickPanelScaffold {
            TranscriptionInfoPanel(transcription: transcription)
        } header: {
            header
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Info")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            AppIconButton(
                systemName: "xmark",
                help: "Close",
                size: 28,
                iconSize: 14,
                cornerRadius: AppTheme.Radius.control,
                action: onClose
            )
        }
        .padding(.horizontal, 20)
        .frame(height: QuickPanelMetrics.headerHeight)
    }
}

/// Reusable component that displays transcription details and the recorded AI request.
struct TranscriptionInfoPanel: View {
    let transcription: Transcription

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailsSection
                aiRequestSection
            }
            .padding(.horizontal, 20)
            .padding(.top, QuickPanelMetrics.topEdgeHeight)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        infoSection("Details") {
            VStack(spacing: 12) {
                TranscriptionMetadataRow(
                    icon: "calendar",
                    label: "Date",
                    value: transcription.timestamp.formatted(date: .abbreviated, time: .shortened)
                )

                TranscriptionMetadataRow(
                    icon: "hourglass",
                    label: "Duration",
                    value: transcription.duration.formatTiming()
                )

                if let modelName = transcription.transcriptionModelName {
                    TranscriptionMetadataRow(
                        icon: "cpu.fill",
                        label: "Transcription Model",
                        value: modelName
                    )

                    if let duration = transcription.transcriptionDuration {
                        TranscriptionMetadataRow(
                            icon: "clock.fill",
                            label: "Transcription Time",
                            value: duration.formatTiming()
                        )
                    }
                }

                if let aiModel = transcription.aiEnhancementModelName {
                    TranscriptionMetadataRow(
                        icon: "sparkles",
                        label: "Enhancement Model",
                        value: aiModel
                    )

                    if let duration = transcription.enhancementDuration {
                        TranscriptionMetadataRow(
                            icon: "clock.fill",
                            label: "Enhancement Time",
                            value: duration.formatTiming()
                        )
                    }
                }

                if let promptName = transcription.promptName {
                    TranscriptionMetadataRow(
                        icon: "text.bubble.fill",
                        label: "Prompt",
                        value: promptName
                    )
                }

                if let modeName = transcription.modeName {
                    TranscriptionMetadataRow(
                        icon: "bolt.fill",
                        label: "Mode",
                        value: modeName
                    )
                }
            }
        }
    }

    // MARK: - AI Request Section

    @ViewBuilder
    private var aiRequestSection: some View {
        if transcription.aiRequestSystemMessage != nil || transcription.aiRequestUserMessage != nil {
            infoSection("AI Request") {
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
            }
        }
    }

    // MARK: - Helpers

    private func infoSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)

            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HistoryCardBackground())
        }
    }

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
}

private struct TranscriptionMetadataRow: View {
    let icon: String
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)
        }
    }
}

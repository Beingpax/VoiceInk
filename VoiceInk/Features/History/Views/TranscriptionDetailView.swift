import SwiftUI

enum HistoryDetailPresentation {
    case mainWindow
    case quickPanel
}

struct TranscriptionDetailView: View {
    let transcription: Transcription
    @Binding var isInfoPresented: Bool
    let onBack: () -> Void
    let onTranscriptionUpdated: (Transcription) -> Void
    var presentation: HistoryDetailPresentation = .mainWindow
    var onPaste: (() -> Void)? = nil

    private var audioURL: URL? { transcription.availableHistoryAudioURL }
    private var playbackURL: URL? { presentation == .mainWindow ? audioURL : nil }
    private var rendersMarkdown: Bool { presentation == .mainWindow }

    private var footerHeight: CGFloat {
        QuickPanelMetrics.footerHeight
            + (playbackURL == nil ? 0 : HistoryLayout.playerHeight + HistoryLayout.playerSpacing)
    }

    var body: some View {
        QuickPanelScaffold(footerHeight: footerHeight) {
            ScrollView {
                transcriptionContent
                    .padding(.horizontal, HistoryLayout.detailInset)
                    .padding(.top, HistoryLayout.detailTopInset)
                    .padding(.bottom, footerHeight + HistoryLayout.detailBottomSpacing)
            }
            .scrollIndicators(.never)
        } header: {
            header
        } footer: {
            footer
        }
        .id(transcription.id)
        .sidePanel(isPresented: $isInfoPresented, dismissOnExitCommand: false) {
            TranscriptionInfoSidePanel(transcription: transcription) {
                isInfoPresented = false
            }
            .id(transcription.id)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to history")
            .accessibilityLabel("Back to history")

            Text("Transcription Details")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            if presentation == .quickPanel {
                HistoryWindowDragArea()
                    .frame(width: 120)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, HistoryLayout.headerInset)
        .frame(height: 52)
    }

    private var transcriptionContent: some View {
        let enhancementText = transcription.historyEnhancementDetailText

        return VStack(alignment: .leading, spacing: 12) {
            if let enhancementText {
                HistoryTranscriptionTextCard(
                    text: enhancementText,
                    title: "Enhanced",
                    surface: AppTheme.Surface.control,
                    rendersMarkdown: rendersMarkdown
                )
            }

            HistoryTranscriptionTextCard(
                text: transcription.text,
                title: enhancementText == nil ? nil : "Original",
                rendersMarkdown: rendersMarkdown
            )
        }
    }

    private var footer: some View {
        VStack(spacing: HistoryLayout.playerSpacing) {
            if let playbackURL {
                HistoryAudioPlayer(url: playbackURL)
                    .padding(.horizontal, HistoryLayout.detailInset)
            }

            HistoryDetailActionBar(
                transcription: transcription,
                audioURL: audioURL,
                isInfoPresented: isInfoPresented,
                onToggleInfo: { isInfoPresented.toggle() },
                onTranscriptionUpdated: onTranscriptionUpdated,
                onPaste: onPaste
            )
        }
        .frame(height: footerHeight)
    }
}

private struct HistoryTranscriptionTextCard: View {
    let text: String
    var title: LocalizedStringKey? = nil
    var surface = AppTheme.Surface.window
    var rendersMarkdown = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.Text.secondary)

                    Spacer()
                    copyButton
                }
            }

            HStack(alignment: .top, spacing: 12) {
                textContent
                    .frame(maxWidth: .infinity, alignment: .leading)

                if title == nil {
                    copyButton
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(HistoryCardBackground(surface: surface))
    }

    private var copyButton: some View {
        CopyIconButton(textToCopy: text, accessibilityLabel: "Copy text")
    }

    private var textContent: some View {
        Group {
            if rendersMarkdown {
                MarkdownContentView(text, fontSize: 14, foregroundColor: AppTheme.Text.primary)
            } else {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.Text.primary)
                    .textSelection(.enabled)
            }
        }
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
}

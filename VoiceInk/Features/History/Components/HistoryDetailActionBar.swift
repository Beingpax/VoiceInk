import AppKit
import SwiftData
import SwiftUI

struct HistoryDetailActionBar: View {
    let transcription: Transcription
    let audioURL: URL?
    let isInfoPresented: Bool
    let onToggleInfo: () -> Void
    let onTranscriptionUpdated: (Transcription) -> Void
    var onPaste: (() -> Void)? = nil

    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var modeManager = ModeManager.shared

    @State private var didCopy = false
    @State private var isShowingModes = false
    @State private var isShowingPrompts = false
    @State private var isWorking = false
    @State private var selectedPromptOverride: CustomPrompt?

    private var selectedMode: ModeConfig? {
        modeManager.currentEffectiveConfiguration
    }

    private var enhancementConfiguration: EnhancementRuntimeConfiguration? {
        guard let aiService = enhancementService.getAIService() else { return nil }
        return ModeRuntimeResolver.currentEnhancementConfiguration(
            mode: selectedMode,
            enhancementService: enhancementService,
            aiService: aiService
        )
    }

    private var selectedPromptTitle: String {
        selectedPromptOverride?.title
            ?? transcription.promptName
            ?? enhancementConfiguration?.prompt?.title
            ?? String(localized: "Select Prompt")
    }

    var body: some View {
        HStack(spacing: 8) {
            modeButton
            promptButton
            retryButton
            finderButton
            infoButton
            Spacer(minLength: 8)
            textActionButton
        }
        .padding(.horizontal, 10)
        .frame(height: HistoryLayout.actionBarHeight)
    }

    private var modeButton: some View {
        Button {
            isShowingModes.toggle()
        } label: {
            actionLabel(title: selectedMode?.name ?? String(localized: "Select Mode")) {
                if let selectedMode {
                    ModeIconView(
                        icon: selectedMode.icon,
                        size: selectedMode.icon.kind == .emoji ? 13 : 11,
                        color: AppTheme.Text.primary
                    )
                    .frame(width: 16)
                } else {
                    Image(systemName: "square.grid.2x2")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .popover(isPresented: $isShowingModes, arrowEdge: .bottom) {
            ModePopover(selectedModeId: selectedMode?.id) { mode in
                modeManager.setActiveConfiguration(mode)
                isShowingModes = false
                retranscribe(using: mode)
            }
        }
        .help("Select a mode and retranscribe")
    }

    private var promptButton: some View {
        Button {
            isShowingPrompts.toggle()
        } label: {
            actionLabel(title: selectedPromptTitle) {
                Image(systemName: "wand.and.stars")
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .popover(isPresented: $isShowingPrompts, arrowEdge: .bottom) {
            promptPopover
        }
        .help("Select a prompt and enhance")
    }

    private var textActionButton: some View {
        HistoryCommandButton(
            onPaste == nil ? "Copy transcription" : "Paste Text",
            systemImage: onPaste == nil ? (didCopy ? "checkmark" : "doc.on.doc") : nil,
            shortcut: onPaste == nil ? nil : "↵",
            minimumWidth: 112,
            action: performTextAction
        )
        .help(
            onPaste == nil
                ? "Copy transcription"
                : "Paste enhanced text when available, otherwise paste the original transcription"
        )
    }

    private func performTextAction() {
        if let onPaste {
            onPaste()
        } else {
            let _ = ClipboardManager.copyToClipboard(transcription.preferredHistoryText)
            didCopy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                didCopy = false
            }
        }
    }

    private var retryButton: some View {
        HistoryIconButton(
            systemName: "arrow.clockwise",
            help: "Retranscribe with the selected mode",
            isLoading: isWorking
        ) {
            guard let selectedMode else {
                showError(String(localized: "No mode selected"))
                return
            }
            retranscribe(using: selectedMode)
        }
        .disabled(isWorking || audioURL == nil)
    }

    private var finderButton: some View {
        HistoryIconButton(systemName: "folder", help: "Show recording in Finder") {
            guard let audioURL else { return }
            NSWorkspace.shared.selectFile(
                audioURL.path,
                inFileViewerRootedAtPath: audioURL.deletingLastPathComponent().path
            )
        }
        .disabled(audioURL == nil)
    }

    private var infoButton: some View {
        HistoryIconButton(
            systemName: "info.circle",
            help: isInfoPresented ? "Hide transcription info" : "Show transcription info",
            isSelected: isInfoPresented,
            action: onToggleInfo
        )
    }

    private func actionLabel<Icon: View>(title: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 7) {
            icon()
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(AppTheme.Text.muted)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppTheme.Text.secondary)
        .padding(.horizontal, 10)
        .frame(maxWidth: 140)
        .frame(height: HistoryLayout.buttonHeight)
        .clipped()
        .background(QuickPanelButtonBackground())
        .fixedSize(horizontal: true, vertical: false)
    }

    private var promptPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Prompt")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()

            ScrollView {
                let prompts = enhancementService.allPrompts
                let promptsUnavailable = enhancementConfiguration?.provider == .voiceInkRefine

                VStack(alignment: .leading, spacing: 4) {
                    if promptsUnavailable {
                        Text("Custom prompts aren't available with VoiceInk Refine. Select another mode first.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                    }

                    if prompts.isEmpty {
                        Text("No Prompts Available")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(prompts) { prompt in
                            EnhancementPromptRow(
                                prompt: prompt,
                                isSelected: enhancementConfiguration?.prompt?.id == prompt.id,
                                isDisabled: promptsUnavailable,
                                action: {
                                    isShowingPrompts = false
                                    selectedPromptOverride = prompt
                                    enhance(using: prompt)
                                }
                            )
                            .disabled(promptsUnavailable)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 230)
        .frame(maxHeight: 340)
        .padding(.vertical, 8)
        .background(AppTheme.Surface.window)
        .popoverAppAppearance()
    }

    private func retranscribe(using mode: ModeConfig) {
        guard let audioURL else {
            showError(String(localized: "Audio file is unavailable"))
            return
        }
        guard let configuration = ModeRuntimeResolver.transcriptionConfiguration(
            mode: mode,
            transcriptionModelManager: engine.transcriptionModelManager
        ) else {
            showError(String(localized: "No transcription model selected"))
            return
        }

        isWorking = true
        let service = AudioTranscriptionService(modelContext: modelContext, engine: engine)

        Task {
            do {
                let result = try await service.retranscribeAudio(
                    from: audioURL,
                    using: configuration.model,
                    mode: mode
                )
                await MainActor.run {
                    isWorking = false
                    if let failure = result.enhancementFailure {
                        NotificationManager.shared.showNotification(
                            title: EnhancementFailureFormatter.transcriptionSavedMessage(description: failure),
                            type: .warning
                        )
                    } else {
                        NotificationManager.shared.showNotification(
                            title: String(localized: "Retranscription successful"),
                            type: .success,
                            duration: 1.0
                        )
                    }
                    onTranscriptionUpdated(result.transcription)
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    showError(
                        error.localizedDescription.isEmpty
                            ? String(localized: "Retranscription failed")
                            : error.localizedDescription
                    )
                }
            }
        }
    }

    private func enhance(using prompt: CustomPrompt) {
        guard let baseConfiguration = enhancementConfiguration else {
            selectedPromptOverride = nil
            showError(String(localized: "AI Enhancement is not enabled or configured"))
            return
        }

        isWorking = true
        let configuration = baseConfiguration.replacingPrompt(prompt)

        Task {
            do {
                transcription.aiEnhancementModelName =
                    configuration.modelName ?? configuration.provider?.defaultModel
                transcription.promptName = configuration.prompt?.title
                let result = try await enhancementService.enhance(
                    transcription.text,
                    configuration: configuration
                )
                await MainActor.run {
                    transcription.enhancedText = result.text
                    transcription.aiEnhancementModelName =
                        configuration.modelName ?? configuration.provider?.defaultModel
                    transcription.promptName =
                        result.promptName ?? configuration.prompt?.title
                    transcription.enhancementDuration = result.duration
                    transcription.aiRequestSystemMessage = result.systemMessage
                    transcription.aiRequestUserMessage = result.userMessage
                    do {
                        try modelContext.save()
                    } catch {
                        modelContext.rollback()
                        selectedPromptOverride = nil
                        isWorking = false
                        showError(
                            error.localizedDescription.isEmpty
                                ? String(localized: "Could not save re-enhancement")
                                : error.localizedDescription
                        )
                        return
                    }
                    selectedPromptOverride = nil
                    isWorking = false
                    NotificationManager.shared.showNotification(
                        title: String(localized: "Re-enhancement successful"),
                        type: .success,
                        duration: 1.0
                    )
                }
            } catch {
                await MainActor.run {
                    selectedPromptOverride = nil
                    isWorking = false
                    let description = EnhancementFailureFormatter.description(for: error)
                    showError(
                        EnhancementFailureFormatter.reEnhancementMessage(description: description)
                    )
                }
            }
        }
    }

    private func showError(_ title: String) {
        NotificationManager.shared.showNotification(title: title, type: .error, duration: 3.0)
    }
}

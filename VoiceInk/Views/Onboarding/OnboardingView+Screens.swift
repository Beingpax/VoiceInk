import SwiftUI

extension OnboardingView {
    var permissionsScreen: some View {
        OnboardingStepScreen(
            stage: .permissions,
            contentMaxWidth: contentMaxWidth
        ) {
            permissionList
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Recheck",
                primaryTitle: "Continue",
                isPrimaryEnabled: requiredPermissionsGranted,
                onLeading: refreshPermissionStatuses,
                onPrimary: goToModelStep
            )
        }
    }

    var modelScreen: some View {
        OnboardingStepScreen(
            stage: .model,
            contentMaxWidth: contentMaxWidth
        ) {
            if let requiredTranscriptionModel {
                TranscriptionModelDownloadCard(
                    model: requiredTranscriptionModel,
                    isDownloaded: isTranscriptionModelDownloaded,
                    isDownloading: fluidAudioModelManager.isFluidAudioModelDownloading(requiredTranscriptionModel),
                    status: fluidAudioModelManager.downloadStatus(for: requiredTranscriptionModel),
                    onDownload: {
                        downloadTranscriptionModel(requiredTranscriptionModel)
                    }
                )
            }
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Continue",
                isPrimaryEnabled: isTranscriptionModelDownloaded,
                onLeading: goToPermissionsStep,
                onPrimary: goToAPIStep
            )
        }
    }

    var apiScreen: some View {
        OnboardingStepScreen(
            stage: .api,
            contentMaxWidth: contentMaxWidth
        ) {
            AIProviderVerificationCard(aiService: aiService)
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Continue",
                isPrimaryEnabled: requiredPermissionsGranted &&
                    isTranscriptionModelDownloaded &&
                    isSelectedAPIProviderVerified,
                onLeading: goToModelStep,
                onPrimary: goToExperienceStep
            )
        }
    }

    var experienceScreen: some View {
        OnboardingStepScreen(
            systemImage: experienceSystemImage,
            title: experienceStep.title,
            subtitle: experienceStep.subtitle,
            contentMaxWidth: contentMaxWidth,
            bottomBarMaxWidth: contentMaxWidth,
            showsHeader: true,
            contentYOffset: 42
        ) {
            OnboardingExperienceCard(
                step: experienceStep,
                shortcutAction: experienceShortcutAction,
                defaultShortcut: experienceDefaultShortcut,
                hasShortcut: hasExperienceModeShortcut,
                text: currentExperienceText,
                onShortcutChanged: refreshExperienceModeState
            )
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: isLastExperienceStep ? "Complete" : "Next",
                isPrimaryEnabled: isCurrentExperienceReady && isCurrentExperienceComplete,
                showsPrimaryButton: hasExperienceModeShortcut,
                onLeading: goToPreviousExperienceStep,
                onPrimary: advanceExperienceStep
            )
        }
        .onAppear {
            activateExperienceModeForDemo()
        }
    }

    private var experienceSystemImage: String {
        switch experienceStep.kind {
        case .dictation:
            return "text.cursor"
        case .enhance:
            return "sparkles"
        case .rewrite, .rewriteFormat:
            return "quote.bubble.fill"
        case .respond:
            return "text.bubble.fill"
        }
    }
}

private struct OnboardingExperienceCard: View {
    let step: OnboardingExperienceStep
    let shortcutAction: ShortcutAction
    let defaultShortcut: Shortcut?
    let hasShortcut: Bool
    @Binding var text: String
    let onShortcutChanged: () -> Void

    @FocusState private var isFieldFocused: Bool
    private let editorTextInset = EdgeInsets(top: 9, leading: 8, bottom: 8, trailing: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if step.kind == .respond {
                instructionPanel
            }
            samplePromptPanel
            if step.kind != .respond {
                notesSurface
            }
        }
        .padding(18)
        .fixedSize(horizontal: false, vertical: true)
        .background(AppMaterialCardBackground(cornerRadius: 14))
        .onAppear {
            focusFieldIfReady()
        }
        .onChange(of: hasShortcut) { _, _ in
            focusFieldIfReady()
        }
    }

    private var instructionPanel: some View {
        statusInstruction
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private var samplePromptPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            sampleHeaderLabel

            Text(step.sampleText)
                .font(.system(size: 15, weight: .semibold))
                .italic()
                .foregroundColor(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(AppTheme.Border.subtle)
                        .frame(width: 2)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.Surface.control.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sampleHeaderLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary.opacity(0.7))

            Text(step.sampleLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary.opacity(0.76))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var notesSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.76))
                    .frame(width: 22, height: 22)
                    .background(AppTheme.Surface.controlActive)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text("Notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.78))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .opacity(0.55)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(fieldPlaceholder)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Text.muted.opacity(0.72))
                        .padding(editorTextInset)
                        .allowsHitTesting(false)
                }

                if step.kind == .rewrite || step.kind == .rewriteFormat {
                    OnboardingLockedTextEditor(
                        text: $text,
                        isEnabled: hasShortcut
                    )
                    .padding(editorTextInset)
                } else {
                    TextEditor(text: $text)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .focused($isFieldFocused)
                        .padding(editorTextInset)
                        .disabled(!hasShortcut)
                        .allowsHitTesting(hasShortcut)
                }
            }
            .frame(height: 112)
            .overlay(alignment: .bottomLeading) {
                statusInstruction
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .background(AppTheme.Surface.control.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(fieldBorderColor, lineWidth: 1)
        )
    }

    private var fieldPlaceholder: String {
        step.fieldPlaceholder
    }

    private var inlineShortcutControl: some View {
        OnboardingShortcutSetupView(
            action: shortcutAction,
            defaultShortcut: defaultShortcut,
            onShortcutChanged: onShortcutChanged,
            showsLabel: false
        )
    }

    private var statusInstruction: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 6) {
                statusInstructionText(statusInstructionPrefix)
                inlineShortcutControl
                statusInstructionText(horizontalStatusInstructionSuffix)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    statusInstructionText(statusInstructionPrefix)
                    inlineShortcutControl
                }
                statusInstructionText(wrappedStatusInstructionSuffix)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var statusInstructionPrefix: String {
        guard hasShortcut else {
            return "Choose"
        }

        switch step.kind {
        case .rewrite, .rewriteFormat:
            return "Select all text, press"
        case .respond:
            return "Press"
        default:
            return "Press"
        }
    }

    private var horizontalStatusInstructionSuffix: String {
        guard hasShortcut else {
            return "to unlock the practice field."
        }

        switch step.kind {
        case .respond:
            return ", ask the question, then press it again."
        case .rewrite, .rewriteFormat:
            return ", speak, then press it again."
        default:
            return " and read the sample text, then press it again."
        }
    }

    private var wrappedStatusInstructionSuffix: String {
        guard hasShortcut else {
            return "to unlock the practice field."
        }

        switch step.kind {
        case .respond:
            return "Ask the question, then press it again."
        case .rewrite, .rewriteFormat:
            return "Speak, then press it again."
        default:
            return "Read the sample text, then press it again."
        }
    }

    private func statusInstructionText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.primary.opacity(0.82))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func focusFieldIfReady() {
        guard hasShortcut else {
            isFieldFocused = false
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isFieldFocused = true
        }
    }

    private var fieldBorderColor: Color {
        isFieldFocused ? Color.primary.opacity(0.24) : AppTheme.Border.subtle
    }
}

private struct OnboardingShortcutSetupView: View {
    let action: ShortcutAction
    let defaultShortcut: Shortcut?
    let onShortcutChanged: () -> Void
    var showsLabel = true

    var body: some View {
        VStack(alignment: .trailing, spacing: showsLabel ? 5 : 0) {
            if showsLabel {
                Text("Shortcut")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Text.muted)
            }

            ShortcutRecorder(
                action: action,
                defaultShortcut: defaultShortcut,
                onShortcutChanged: onShortcutChanged
            )
        }
        .fixedSize(horizontal: true, vertical: false)
        .onAppear(perform: seedDefaultShortcut)
        .onChange(of: action) { _, _ in
            seedDefaultShortcut()
            onShortcutChanged()
        }
    }

    private func seedDefaultShortcut() {
        guard let defaultShortcut else { return }

        ShortcutStore.seedShortcut(
            defaultShortcut,
            for: action,
            replacingCleared: true
        )
    }
}

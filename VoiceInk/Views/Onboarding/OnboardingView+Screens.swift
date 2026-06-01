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
                shortcutLabel: experienceShortcutLabel,
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
        case .enhance, .enhanceAgain:
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
    let shortcutLabel: String
    let defaultShortcut: Shortcut?
    let hasShortcut: Bool
    @Binding var text: String
    let onShortcutChanged: () -> Void

    @FocusState private var isFieldFocused: Bool
    private let editorTextInset = EdgeInsets(top: 9, leading: 8, bottom: 8, trailing: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            samplePanel
            if step.kind != .respond {
                notesSurface
            }
            statusRow
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

    private var samplePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.7))

                Text(step.sampleLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.76))
            }

            HStack(alignment: .center, spacing: 14) {
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

                Spacer(minLength: 12)

                OnboardingShortcutSetupView(
                    action: shortcutAction,
                    defaultShortcut: defaultShortcut,
                    onShortcutChanged: onShortcutChanged
                )
            }
        }
        .padding(14)
        .background(AppTheme.Surface.control.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .frame(height: 158)
        }
        .background(AppTheme.Surface.control.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(fieldBorderColor, lineWidth: 1)
        )
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary.opacity(0.72))

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var statusText: String {
        if !hasShortcut {
            return "Set a shortcut to unlock the practice field."
        }

        if step.kind == .rewrite || step.kind == .rewriteFormat {
            return "Select all text in the text field, press \(shortcutLabel), speak, then press it again."
        }

        if step.kind == .respond {
            return "Press \(shortcutLabel), ask the question, then press it again."
        }

        return "Press \(shortcutLabel), speak, then press it again."
    }

    private var fieldPlaceholder: String {
        hasShortcut ? step.fieldPlaceholder : "Choose a shortcut above to unlock this field."
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

    private var statusColor: Color {
        hasShortcut ? Color.primary.opacity(0.68) : AppTheme.Text.muted.opacity(0.5)
    }

    private var fieldBorderColor: Color {
        isFieldFocused ? Color.primary.opacity(0.24) : AppTheme.Border.subtle
    }
}

private struct OnboardingShortcutSetupView: View {
    let action: ShortcutAction
    let defaultShortcut: Shortcut?
    let onShortcutChanged: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text("Shortcut")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.Text.muted)

            ShortcutRecorder(
                action: action,
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

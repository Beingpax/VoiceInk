import SwiftUI

struct OnboardingExperienceCard: View {
    let step: OnboardingExperienceStep
    let shortcutAction: ShortcutAction
    let hasShortcut: Bool
    @Binding var text: String
    let onShortcutChanged: () -> Void

    @State private var isFieldFocused = false
    private let editorTextInset = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
    private let panelHeight: CGFloat = 184

    var body: some View {
        VStack(spacing: 26) {
            if step.layout == .respond {
                respondStage
            } else {
                transformStage
            }

            OnboardingExperienceInstruction(
                step: step,
                shortcutAction: shortcutAction,
                hasShortcut: hasShortcut,
                onShortcutChanged: onShortcutChanged
            )
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            focusFieldIfReady()
        }
        .onChange(of: hasShortcut) { _, _ in
            focusFieldIfReady()
        }
    }

    private var transformStage: some View {
        HStack(alignment: .center, spacing: 0) {
            sayPanel
            transformArrow
            notesPreviewPanel
        }
    }

    private var sayPanel: some View {
        panelShell(kicker: step.sampleLabel) {
            Text(step.sampleText)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(AppTheme.Text.primary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notesPreviewPanel: some View {
        VStack(spacing: 0) {
            notesToolbar

            Divider()
                .opacity(0.5)

            notesTextArea
        }
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight)
        .background(AppTheme.Surface.window.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(fieldBorderColor, lineWidth: 1)
        )
        .opacity(hasShortcut ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.18), value: hasShortcut)
    }

    private var notesToolbar: some View {
        HStack(spacing: 8) {
            trafficLights

            Image(systemName: "note.text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.Text.secondary)

            Text("Notes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.Text.primary)

            Spacer(minLength: 0)

            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.Text.muted)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(AppTheme.Surface.control.opacity(0.48))
    }

    private var trafficLights: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(AppTheme.Status.error.opacity(0.78))
            Circle()
                .fill(AppTheme.Status.warningStrong.opacity(0.78))
            Circle()
                .fill(AppTheme.Status.positive.opacity(0.78))
        }
        .frame(width: 42, height: 10)
    }

    private var notesTextArea: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(step.fieldPlaceholder)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.Text.muted)
                    .padding(editorTextInset)
                    .allowsHitTesting(false)
            }

            editor
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var transformArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(AppTheme.Text.muted)
            .frame(width: 46)
    }

    private var respondStage: some View {
        panelShell(kicker: step.sampleLabel, height: 150) {
            Text(step.sampleText)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(AppTheme.Text.primary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 460)
    }

    private func panelShell<Content: View>(
        kicker: String,
        height: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kicker)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundColor(AppTheme.Text.muted)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height ?? panelHeight)
        .background(AppTheme.Surface.control.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var editor: some View {
        OnboardingLockedTextEditor(
            text: $text,
            isEnabled: hasShortcut,
            isFocused: $isFieldFocused
        )
        .padding(editorTextInset)
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
        isFieldFocused ? AppTheme.Accent.border : AppTheme.Border.subtle
    }
}

private struct OnboardingExperienceInstruction: View {
    let step: OnboardingExperienceStep
    let shortcutAction: ShortcutAction
    let hasShortcut: Bool
    let onShortcutChanged: () -> Void

    var body: some View {
        line
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var line: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                instructionText(prefix)
                shortcutControl
                instructionText(horizontalSuffix)
            }

            VStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    instructionText(prefix)
                    shortcutControl
                }
                instructionText(wrappedSuffix)
            }
        }
    }

    private var shortcutControl: some View {
        OnboardingShortcutSetupView(
            action: shortcutAction,
            onShortcutChanged: onShortcutChanged
        )
    }

    private func instructionText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(AppTheme.Text.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var prefix: String {
        guard hasShortcut else {
            return "Choose"
        }

        return step.configuredInstructionPrefix
    }

    private var horizontalSuffix: String {
        guard hasShortcut else {
            return "to get started."
        }

        return step.configuredHorizontalInstructionSuffix
    }

    private var wrappedSuffix: String {
        guard hasShortcut else {
            return "to get started."
        }

        return step.configuredWrappedInstructionSuffix
    }
}

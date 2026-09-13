import AppKit
import SwiftData
import SwiftUI

// MARK: - Manager

@MainActor
final class DictionaryQuickAddManager {
    static let shared = DictionaryQuickAddManager()
    private init() {}

    private var panel: PersistentQuickPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible == true }

    func toggle(modelContainer: ModelContainer) {
        isVisible ? hide() : show(modelContainer: modelContainer)
    }

    func show(modelContainer: ModelContainer) {
        guard !isVisible else { return }

        previousApp = NSWorkspace.shared.frontmostApplication

        let initialSize = NSSize(width: 500, height: DictionaryQuickAddView.Mode.vocabulary.panelHeight)
        let newPanel = PersistentQuickPanel(
            size: initialSize,
            positionDefaultsKey: "VoiceInkDictionaryQuickAddOrigin",
            defaultVerticalOffset: 60
        )
        newPanel.onEscape = { [weak self] in
            self?.hide()
        }
        newPanel.onDismissRequest = { [weak self] in
            self?.hide(restorePreviousApplication: false)
        }

        let view = DictionaryQuickAddView(
            onDismiss: { [weak self] in self?.hide() },
            onResize: { [weak self] height in
                self?.panel?.resizeKeepingTopEdge(to: NSSize(width: 500, height: height))
            }
        )
        .modelContainer(modelContainer)

        let controller = NSHostingController(rootView: AnyView(view))
        newPanel.contentView = controller.view
        hostingController = controller
        panel = newPanel
        newPanel.makeKeyAndOrderFront(nil)
    }

    func hide(restorePreviousApplication: Bool = true) {
        guard isVisible else { return }
        panel?.persistPosition()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        hostingController = nil
        if restorePreviousApplication {
            previousApp?.activate()
        }
        previousApp = nil
    }
}

// MARK: - View

struct DictionaryQuickAddView: View {
    enum Mode: CaseIterable {
        case vocabulary, replacement

        var label: LocalizedStringKey {
            switch self {
            case .vocabulary: return "Vocabulary"
            case .replacement: return "Word Replacement"
            }
        }

        var icon: String {
            switch self {
            case .vocabulary: return "character.book.closed.fill"
            case .replacement: return "arrow.2.squarepath"
            }
        }

        var panelHeight: CGFloat {
            switch self {
            case .vocabulary: return 160
            case .replacement: return 184
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var vocabularyWords: [VocabularyWord]
    @Query private var wordReplacements: [WordReplacement]

    @State private var mode: Mode = .vocabulary
    @State private var wordInput = ""
    @State private var originalInput = ""
    @State private var replacementInput = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case word, original, replacement }

    let onDismiss: () -> Void
    let onResize: (CGFloat) -> Void

    var body: some View {
        QuickPanelScaffold {
            VStack(spacing: 0) {
                inputArea
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(AppTheme.Status.error)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
            }
            .padding(.top, 52)
            .padding(.bottom, 52)
        } header: {
            modeBar
        } footer: {
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.Border.tint, lineWidth: 0.5)
        )
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onAppear {
            DispatchQueue.main.async { focusedField = .word }
        }
        .onChange(of: mode) { _, newMode in
            wordInput = ""
            originalInput = ""
            replacementInput = ""
            errorMessage = nil
            DispatchQueue.main.async {
                focusedField = newMode == .vocabulary ? .word : .original
            }
            onResize(newMode.panelHeight)
        }
        .onChange(of: errorMessage) { _, newError in
            let height = mode.panelHeight + (newError != nil ? 24 : 0)
            onResize(height)
        }
    }

    // MARK: - Mode Bar

    private var modeBar: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { mode = m }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: m.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(m.label)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(mode == m ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(mode == m ? AppTheme.Selection.fill : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()

            QuickPanelEscapeButton(
                help: "Dismiss",
                action: onDismiss
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - Input Area

    @ViewBuilder
    private var inputArea: some View {
        if mode == .vocabulary {
            vocabularyInput
        } else {
            replacementInputView
        }
    }

    private var vocabularyInput: some View {
        HStack(spacing: 11) {
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField("", text: $wordInput, prompt: Text("e.g. Prakash, VoiceInk").foregroundColor(.secondary))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($focusedField, equals: .word)
                .onSubmit { submitVocabulary() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var replacementInputView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Replace")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                TextField("", text: $originalInput, prompt: Text("e.g. my email, my mail").foregroundColor(.secondary))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                    .focused($focusedField, equals: .original)
                    .onSubmit { focusedField = .replacement }
            }

            HStack(spacing: 10) {
                Text("With")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                TextField(
                    "", text: $replacementInput,
                    prompt: Text("e.g. support@tryvoiceink.com").foregroundColor(.secondary)
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($focusedField, equals: .replacement)
                .onSubmit { submitReplacement() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            Spacer()

            Button(action: submitCurrentInput) {
                HStack(spacing: 7) {
                    Text("Add Now")
                    Text("↵")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Text.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(AppTheme.Surface.controlActive, in: RoundedRectangle(cornerRadius: 5))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.Text.secondary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .fixedSize(horizontal: true, vertical: false)
                .background(QuickPanelButtonBackground())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitCurrentInput)
            .help("Add Now")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    // MARK: - Actions

    private var canSubmitCurrentInput: Bool {
        switch mode {
        case .vocabulary:
            return !wordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .replacement:
            return !originalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !replacementInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submitCurrentInput() {
        switch mode {
        case .vocabulary:
            submitVocabulary()
        case .replacement:
            submitReplacement()
        }
    }

    private func submitVocabulary() {
        let input = wordInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if let error = DictionaryService.addVocabularyWords(
            input, existing: Array(vocabularyWords), context: modelContext)
        {
            errorMessage = error
            return
        }
        onDismiss()
    }

    private func submitReplacement() {
        let original = originalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !replacement.isEmpty else { return }
        if let error = DictionaryService.addWordReplacement(
            original: original, replacement: replacement, existing: Array(wordReplacements), context: modelContext)
        {
            errorMessage = error
            return
        }
        onDismiss()
    }
}

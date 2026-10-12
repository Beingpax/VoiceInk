import AppKit
import SwiftUI

struct OnboardingLockedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let isEnabled: Bool
    var isFocused: Binding<Bool>? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = LockedTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = AppTheme.NativeText.primary
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? LockedTextView else { return }

        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
        }

        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        textView.locksManualEditing = true

        syncFocus(for: textView, in: scrollView)
    }

    private func syncFocus(for textView: LockedTextView, in scrollView: NSScrollView) {
        guard let isFocused else { return }

        if isFocused.wrappedValue, isEnabled {
            DispatchQueue.main.async {
                guard let window = scrollView.window,
                    window.firstResponder !== textView
                else {
                    return
                }

                window.makeFirstResponder(textView)
            }
        } else if !isFocused.wrappedValue {
            DispatchQueue.main.async {
                guard let window = scrollView.window,
                    window.firstResponder === textView
                else {
                    return
                }

                window.makeFirstResponder(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: OnboardingLockedTextEditor

        init(_ parent: OnboardingLockedTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused?.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused?.wrappedValue = false
        }
    }
}

private final class LockedTextView: NSTextView {
    var locksManualEditing = false
    private var isApplyingPaste = false

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard !locksManualEditing || isApplyingPaste else { return }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func paste(_ sender: Any?) {
        guard isEditable else { return }

        isApplyingPaste = true
        super.paste(sender)
        isApplyingPaste = false
    }

    override func cut(_ sender: Any?) {
        guard !locksManualEditing else { return }
        super.cut(sender)
    }

    override func delete(_ sender: Any?) {
        guard !locksManualEditing else { return }
        super.delete(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        guard !locksManualEditing else { return }
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        guard !locksManualEditing else { return }
        super.deleteForward(sender)
    }

    override func insertNewline(_ sender: Any?) {
        guard !locksManualEditing else { return }
        super.insertNewline(sender)
    }
}

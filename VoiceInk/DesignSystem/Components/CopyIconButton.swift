import SwiftUI

struct CopyIconButton: View {
    let textToCopy: String
    var accessibilityLabel: LocalizedStringResource = "Copy"
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(copied ? AppTheme.Status.positive : AppTheme.Selection.foreground)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .fill(AppTheme.Surface.window.opacity(0.92))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                                .strokeBorder(AppTheme.Border.card, lineWidth: 1)
                        }
                )
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }

    private func copy() {
        let _ = ClipboardManager.copyToClipboard(textToCopy)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}

extension View {
    func hoverCopyButton(
        textToCopy: String,
        accessibilityLabel: LocalizedStringResource = "Copy",
        alignment: Alignment = .bottomTrailing,
        padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 8)
    ) -> some View {
        modifier(
            HoverCopyButtonModifier(
                textToCopy: textToCopy,
                accessibilityLabel: accessibilityLabel,
                alignment: alignment,
                padding: padding
            )
        )
    }
}

private struct HoverCopyButtonModifier: ViewModifier {
    let textToCopy: String
    let accessibilityLabel: LocalizedStringResource
    let alignment: Alignment
    let padding: EdgeInsets

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if isHovering {
                    CopyIconButton(textToCopy: textToCopy, accessibilityLabel: accessibilityLabel)
                        .padding(padding)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
    }
}

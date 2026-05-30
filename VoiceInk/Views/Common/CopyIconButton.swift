import SwiftUI

struct CopyIconButton: View {
    let textToCopy: String
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(copied ? AppTheme.Status.success : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    AppCardBackground(isSelected: false, cornerRadius: AppTheme.Radius.control)
                )
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
    }

    private func copy() {
        let _ = ClipboardManager.copyToClipboard(textToCopy)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}

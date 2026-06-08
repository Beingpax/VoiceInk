import SwiftUI

struct AddIconButton: View {
    let helpText: String
    var size: CGFloat = 18
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: size))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isDisabled ? .tertiary : .secondary)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .disabled(isDisabled)
    }
}

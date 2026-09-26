import SwiftUI

struct DictionaryPill<Label: View>: View {
    private let label: Label
    private let onRemove: (() -> Void)?
    private let removeHelp: LocalizedStringKey
    private let removeAccessibilityLabel: LocalizedStringKey?

    init(
        onRemove: (() -> Void)?,
        removeHelp: LocalizedStringKey,
        removeAccessibilityLabel: LocalizedStringKey? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.onRemove = onRemove
        self.removeHelp = removeHelp
        self.removeAccessibilityLabel = removeAccessibilityLabel
    }

    var body: some View {
        HStack(spacing: 5) {
            label
                .font(.system(size: 12))

            removeButton
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(AppTheme.Surface.subtle))
        .overlay(
            Capsule()
                .stroke(AppTheme.Border.subtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var removeButton: some View {
        if let onRemove {
            let button = Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Text.primary)
            }
            .buttonStyle(.borderless)
            .help(removeHelp)

            if let removeAccessibilityLabel {
                button.accessibilityLabel(removeAccessibilityLabel)
            } else {
                button
            }
        }
    }
}

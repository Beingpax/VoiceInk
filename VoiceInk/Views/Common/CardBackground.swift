import SwiftUI

struct CardBackground: View {
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.secondary.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.75) : Color(NSColor.separatorColor).opacity(0.28),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
    }
}

struct PrimaryCardBackground: View {
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 12

    static let fillColor = Color(NSColor.windowBackgroundColor).opacity(0.25)

    static func borderColor(isSelected: Bool) -> Color {
        isSelected ? Color.accentColor.opacity(0.75) : Color(NSColor.separatorColor).opacity(0.4)
    }

    static func borderWidth(isSelected: Bool) -> CGFloat {
        isSelected ? 1.5 : 1
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Self.fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        Self.borderColor(isSelected: isSelected),
                        lineWidth: Self.borderWidth(isSelected: isSelected)
                    )
            )
    }
}

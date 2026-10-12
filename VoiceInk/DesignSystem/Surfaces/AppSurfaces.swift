import SwiftUI

struct AppCardBackground: View {
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(AppTheme.Surface.card)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isSelected ? AppTheme.Selection.border : AppTheme.Border.subtle,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
    }
}

struct AppMaterialCardBackground: View {
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 12

    static let fill = AppTheme.Surface.materialCard

    static func border(for isSelected: Bool) -> Color {
        isSelected ? AppTheme.Selection.border : AppTheme.Border.card
    }

    static func lineWidth(for isSelected: Bool) -> CGFloat {
        isSelected ? 1.5 : 1
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Self.fill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        Self.border(for: isSelected),
                        lineWidth: Self.lineWidth(for: isSelected)
                    )
            )
    }
}

struct MetricTintBackground: View {
    let color: Color
    var cornerRadius: CGFloat = AppTheme.Radius.card

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: color.opacity(0.15), location: 0),
                        .init(color: AppTheme.Surface.window.opacity(0.1), location: 0.6),
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                AppTheme.Border.subtle,
                                AppTheme.Border.subtle.opacity(0.4),
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, y: 3)
    }
}

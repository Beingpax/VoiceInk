import SwiftUI

struct DashboardInsightCardBackground: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    var cornerRadius: CGFloat = DashboardLayout.cardCornerRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(AppTheme.Insights.card)
            .overlay {
                if colorSchemeContrast == .increased {
                    shape
                        .strokeBorder(AppTheme.Insights.border, lineWidth: 1)
                }
            }
    }
}

extension View {
    func dashboardInsightCardStyle(
        padding: CGFloat = 22,
        alignment: Alignment = .leading
    ) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: alignment)
            .background(DashboardInsightCardBackground())
    }
}

struct DashboardInsightRowBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppTheme.Insights.elevated)
    }
}

struct DashboardInsightButtonStyle: ButtonStyle {
    var isSelected = false
    var isQuiet = false

    func makeBody(configuration: Configuration) -> some View {
        DashboardInsightButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: isSelected,
            isQuiet: isQuiet
        )
    }
}

private struct DashboardInsightButtonBody<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let isSelected: Bool
    let isQuiet: Bool

    private var backgroundColor: Color {
        if isSelected {
            return AppTheme.Insights.selection
        }
        return isQuiet ? .clear : AppTheme.Insights.elevated
    }

    private var opacity: Double {
        guard isEnabled else { return 0.45 }
        return isPressed ? 0.8 : 1
    }

    var body: some View {
        label
            .foregroundStyle(isSelected ? AppTheme.Insights.selectionText : AppTheme.Text.primary)
            .background {
                Capsule()
                    .fill(backgroundColor)
                    .overlay {
                        if isHovered || isPressed {
                            Capsule().fill(AppTheme.Insights.hover)
                        }
                    }
            }
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(AppTheme.Insights.productivity.opacity(0.4), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .opacity(opacity)
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
    }
}

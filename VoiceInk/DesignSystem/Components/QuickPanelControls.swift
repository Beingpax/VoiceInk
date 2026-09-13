import SwiftUI

enum QuickPanelEdge {
    case top
    case bottom
}

enum QuickPanelMetrics {
    static let headerHeight: CGFloat = 56
    static let footerHeight: CGFloat = 48
    static let fadeLength: CGFloat = 16

    static let topEdgeHeight = headerHeight + fadeLength
    static let bottomEdgeHeight = footerHeight + fadeLength
}

/// Places scrollable panel content beneath a floating material header and an
/// optional footer. Callers retain ownership of their content and scroll insets.
struct QuickPanelScaffold<Content: View, Header: View, Footer: View>: View {
    private let content: Content
    private let header: Header
    private let footer: Footer?

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        ZStack {
            content

            VStack(spacing: 0) {
                QuickPanelScrollEdge(edge: .top) {
                    header
                }

                Spacer(minLength: 0)

                if let footer {
                    QuickPanelScrollEdge(edge: .bottom) {
                        footer
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension QuickPanelScaffold where Footer == EmptyView {
    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header
    ) {
        self.content = content()
        self.header = header()
        self.footer = nil
    }
}

struct QuickPanelScrollEdge<Content: View>: View {
    let edge: QuickPanelEdge
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: edge == .top ? .top : .bottom) {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .mask(edgeMask)
                .allowsHitTesting(false)

            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.30)
                .mask(emphasisMask)
                .allowsHitTesting(false)

            content()
                .padding(edge == .top ? .top : .bottom, 8)
        }
        .frame(
            height: edge == .top
                ? QuickPanelMetrics.topEdgeHeight
                : QuickPanelMetrics.bottomEdgeHeight
        )
    }

    private var edgeMask: some View {
        LinearGradient(
            stops: edge == .top
                ? [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.92), location: 0.60),
                    .init(color: .clear, location: 1),
                ]
                : [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.92), location: 0.40),
                    .init(color: .black, location: 1),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var emphasisMask: some View {
        LinearGradient(
            stops: edge == .top
                ? [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.88), location: 0.58),
                    .init(color: .clear, location: 1),
                ]
                : [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.88), location: 0.42),
                    .init(color: .black, location: 1),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct QuickPanelButtonBackground: View {
    var isSelected = false

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
            .fill(AppTheme.Surface.control)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .fill(AppTheme.Selection.fill)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppTheme.Selection.border : AppTheme.Border.card,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
    }
}

struct QuickPanelEscapeButton: View {
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("esc")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Text.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(AppTheme.Surface.controlActive, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel("Escape")
        .accessibilityHint(help)
    }
}

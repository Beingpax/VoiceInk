import Foundation
import SwiftUI

struct AppIconButton: View {
    let systemName: String
    let help: LocalizedStringResource
    var size: CGFloat = 40
    var iconSize: CGFloat = 18
    var cornerRadius: CGFloat = AppTheme.Radius.pill
    var isDisabled = false
    let action: () -> Void

    init(
        systemName: String,
        help: LocalizedStringResource,
        size: CGFloat = 40,
        iconSize: CGFloat = 18,
        cornerRadius: CGFloat = AppTheme.Radius.pill,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.help = help
        self.size = size
        self.iconSize = iconSize
        self.cornerRadius = cornerRadius
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(isDisabled ? .secondary.opacity(0.45) : .primary.opacity(0.7))
                .frame(width: size, height: size)
                .background(
                    AppCardBackground(isSelected: false, cornerRadius: cornerRadius)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

enum AppActionButtonKind: Equatable {
    case secondary
    case primary
    case destructive
}

struct AppActionButton: View {
    let title: LocalizedStringKey
    var kind: AppActionButtonKind = .secondary
    var minWidth: CGFloat?
    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        kind: AppActionButtonKind = .secondary,
        minWidth: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.minWidth = minWidth
        self.action = action
    }

    var body: some View {
        Button(role: kind == .destructive ? .destructive : nil, action: action) {
            Text(title)
                .frame(minWidth: minWidth)
        }
        .buttonStyle(AppActionButtonStyle(kind: kind))
    }
}

private struct AppActionButtonStyle: ButtonStyle {
    let kind: AppActionButtonKind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
    }

    private var foregroundColor: Color {
        switch kind {
        case .secondary: AppTheme.Action.secondaryForeground
        case .primary: AppTheme.Action.primaryForeground
        case .destructive: AppTheme.Action.destructiveForeground
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .secondary: AppTheme.Surface.control
        case .primary: AppTheme.Action.primaryFill
        case .destructive: AppTheme.Action.destructiveFill
        }
    }

    private var borderColor: Color {
        switch kind {
        case .secondary: AppTheme.Border.control
        case .primary: AppTheme.Accent.border
        case .destructive: Color.white.opacity(0.14)
        }
    }
}

struct AppPanelHeader: View {
    let title: LocalizedStringKey
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()

            AppIconButton(
                systemName: "xmark",
                help: "Close",
                size: 28,
                iconSize: 14,
                cornerRadius: AppTheme.Radius.control,
                action: onClose
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
        .zIndex(1)
    }
}

struct AppScreenHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var infoMessage: LocalizedStringKey?
    var infoURL: String?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)

                if let infoMessage {
                    if let infoURL {
                        InfoTip(infoMessage, learnMoreURL: infoURL)
                    } else {
                        InfoTip(infoMessage)
                    }
                }
            }

            Spacer()

            trailing()
        }
        .frame(height: 40)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }
}

extension AppScreenHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, infoMessage: LocalizedStringKey? = nil, infoURL: String? = nil) {
        self.title = title
        self.infoMessage = infoMessage
        self.infoURL = infoURL
        self.trailing = { EmptyView() }
    }
}

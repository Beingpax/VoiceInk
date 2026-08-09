import SwiftUI

enum AppSidebarLayout {
    static let minimumWidth: CGFloat = 200
    static let idealWidth: CGFloat = 220
    static let maximumWidth: CGFloat = 280
}

struct AppSidebar: View {
    @Binding var selectedView: ViewType

    var body: some View {
        // A real List rather than a VStack: this is what gives the app keyboard navigation
        // between destinations, and what lets detail views host .searchable and .toolbar.
        List(selection: $selectedView) {
            Section {
                ForEach(ViewType.primaryItems) { viewType in
                    SidebarItemLabel(viewType: viewType, isSelected: selectedView == viewType)
                        .tag(viewType)
                }
            }

            Section {
                ForEach(ViewType.secondaryItems) { viewType in
                    SidebarItemLabel(viewType: viewType, isSelected: selectedView == viewType)
                        .tag(viewType)
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 38)
        .onAppear {
            ViewType.assertSidebarItemsCoverAllCases()
        }
    }
}

private extension ViewType {
    var title: LocalizedStringKey {
        switch self {
        case .transcribeAudio:
            return "Transcribe"
        default:
            return LocalizedStringKey(rawValue)
        }
    }

    static let primaryItems: [ViewType] = [
        .dashboard,
        .modes,
        .transcribeAudio,
        .history,
        .dictionary,
        .models,
        .audio,
    ]

    static let secondaryItems: [ViewType] = [
        .settings,
        .license,
    ]

    static func assertSidebarItemsCoverAllCases() {
        #if DEBUG
            let sidebarItems = primaryItems + secondaryItems
            assert(Set(sidebarItems) == Set(allCases) && sidebarItems.count == allCases.count)
        #endif
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .transcribeAudio: return "waveform.path"
        case .history: return "doc.text.fill"
        case .models: return "cpu"
        case .modes: return "sparkles.square.fill.on.square"
        case .audio: return "mic.fill"
        case .dictionary: return "text.book.closed.fill"
        case .settings: return "gearshape.fill"
        case .license: return "checkmark.seal.fill"
        }
    }

    var sidebarIconStyle: SidebarIconStyle {
        switch self {
        case .dashboard:
            return .init(background: AppTheme.Sidebar.dashboard)
        case .modes:
            return .init(background: AppTheme.Sidebar.modes)
        case .models:
            return .init(background: AppTheme.Sidebar.models)
        case .audio:
            return .init(background: AppTheme.Sidebar.audio)
        case .dictionary:
            return .init(background: AppTheme.Sidebar.dictionary)
        case .history:
            return .init(background: AppTheme.Sidebar.history)
        case .transcribeAudio:
            return .init(background: AppTheme.Sidebar.transcribeAudio)
        case .settings:
            return .init(background: AppTheme.Sidebar.fallback)
        case .license:
            return .init(background: AppTheme.Sidebar.license)
        }
    }
}

private struct SidebarIconStyle {
    let background: Color
    var foreground: Color = .white
}

/// The row content. Selection highlight comes from the enclosing `List`, so this only draws the
/// icon tile and title — that keeps VoiceInk's colored-tile identity while inheriting native
/// selection, hover and keyboard behaviour.
private struct SidebarItemLabel: View {
    let viewType: ViewType
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            SidebarIconTile(
                systemName: viewType.icon,
                style: viewType.sidebarIconStyle
            )

            Text(viewType.title)
                .font(AppTheme.Typography.label.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .help(viewType.title)
        .accessibilityLabel(viewType.title)
    }
}

private struct SidebarIconTile: View {
    let systemName: String
    let style: SidebarIconStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(style.background)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 11)
                        .blendMode(.screen)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 1.2, y: 1)

            Image(systemName: systemName)
                .font(.system(size: 14.5, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(style.foreground)
                .shadow(color: Color.black.opacity(0.16), radius: 0.5, y: 0.5)
        }
        .frame(width: 24, height: 24)
    }
}

import OSLog
import SwiftUI

enum ViewType: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case modes = "Modes"
    case models = "AI Models"
    case transcribeAudio = "Transcribe Audio"
    case history = "History"
    case audio = "Audio"
    case dictionary = "Dictionary"
    case settings = "Settings"
    case license = "VoiceInk Pro"

    var id: String { rawValue }
}

@Observable
final class MainWindowNavigation {
    @MainActor static let shared = MainWindowNavigation()

    var selectedView: ViewType = .dashboard

    private init() {}

    func navigate(to destination: String) {
        guard let viewType = ViewType(rawValue: destination) else {
            return
        }

        navigate(to: viewType)
    }

    func navigate(to destination: ViewType) {
        selectedView = destination
    }
}

struct ContentView: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ContentView")
    private static let detailBackgroundTintOpacity = 0.50
    @Environment(MainWindowNavigation.self) private var navigation
    @State private var isCommandPalettePresented = false

    var body: some View {
        @Bindable var navigation = navigation

        return NavigationSplitView {
            AppSidebar(selectedView: $navigation.selectedView)
                .navigationSplitViewColumnWidth(
                    min: AppSidebarLayout.minimumWidth,
                    ideal: AppSidebarLayout.idealWidth,
                    max: AppSidebarLayout.maximumWidth
                )
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: AppWindowLayout.minimumWidth, minHeight: AppWindowLayout.minimumHeight)
        .overlay {
            if isCommandPalettePresented {
                commandPaletteOverlay
            }
        }
        .background {
            // Invisible shortcut host: gives ⌘K a home without putting a button in the UI.
            Button("Command Palette") {
                isCommandPalettePresented = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .onAppear {
            logger.notice("ContentView appeared")
        }
        .onDisappear {
            logger.notice("ContentView disappeared")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = notification.userInfo?["destination"] as? String {
                logger.notice("navigateToDestination received: \(destination, privacy: .public)")
                navigation.navigate(to: destination)
            }
        }
    }

    private var commandPaletteOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { isCommandPalettePresented = false }

            CommandPaletteView(isPresented: $isCommandPalettePresented)
                .padding(.top, 90)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        .animation(AppTheme.Motion.quick, value: isCommandPalettePresented)
    }

    @ViewBuilder
    private var detailContent: some View {
        detailView(for: navigation.selectedView)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(detailBackground)
    }

    private var detailBackground: some View {
        ZStack {
            VisualEffectView(
                material: .sidebar,
                blendingMode: .behindWindow
            )

            AppTheme.Surface.window
                .opacity(Self.detailBackgroundTintOpacity)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private func detailView(for viewType: ViewType) -> some View {
        switch viewType {
        case .dashboard:
            DashboardView()
        case .models:
            ModelManagementView()
        case .transcribeAudio:
            AudioTranscribeView()
        case .history:
            InlineHistoryView()
        case .audio:
            AudioSetupView()
        case .dictionary:
            DictionarySettingsView()
        case .modes:
            ModeView()
        case .settings:
            SettingsView()
        case .license:
            LicenseManagementView()
        }
    }
}

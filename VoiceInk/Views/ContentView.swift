import SwiftUI
import OSLog

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

struct ContentView: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ContentView")
    private static let detailBackgroundTintOpacity = 0.50
    @State private var selectedView: ViewType = .dashboard

    var body: some View {
        HStack(spacing: 0) {
            AppSidebar(selectedView: $selectedView)

            detailContent
        }
        .frame(width: 950)
        .frame(minHeight: 730)
        .onAppear {
            logger.notice("ContentView appeared")
        }
        .onDisappear {
            logger.notice("ContentView disappeared")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = notification.userInfo?["destination"] as? String,
               let viewType = ViewType.allCases.first(where: { $0.rawValue == destination }) {
                logger.notice("navigateToDestination received: \(destination, privacy: .public)")
                selectedView = viewType
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        detailView(for: selectedView)
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

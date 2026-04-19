import SwiftUI
import SwiftData
import KeyboardShortcuts
import OSLog

enum ViewType: String, CaseIterable, Identifiable {
    case history = "History"
    case statistics = "Statistics"
    case models = "AI Models"
    case enhancement = "Enhancement"
    case powerMode = "Power Mode"
    case permissions = "Permissions"
    case audioInput = "Audio Input"
    case dictionary = "Dictionary"
    case settings = "Settings"
    case license = "VoiceInk Pro"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .statistics: return "chart.bar.xaxis"
        case .models: return "brain"
        case .enhancement: return "wand.and.stars"
        case .powerMode: return "bolt.square"
        case .permissions: return "lock.shield"
        case .audioInput: return "mic"
        case .dictionary: return "character.book.closed"
        case .settings: return "gearshape"
        case .license: return "checkmark.seal"
        }
    }
}

private struct SidebarSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [ViewType]
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

struct ContentView: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ContentView")
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @AppStorage("powerModeUIFlag") private var powerModeUIFlag = false
    @State private var selectedView: ViewType? = .history
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    private var sidebarSections: [SidebarSection] {
        let enhancementItems: [ViewType] = powerModeUIFlag
            ? [.enhancement, .powerMode]
            : [.enhancement]

        return [
            SidebarSection(title: "Transcription", items: [.history, .statistics, .models, .audioInput, .dictionary]),
            SidebarSection(title: "Enhancement", items: enhancementItems),
            SidebarSection(title: "App", items: [.permissions, .settings]),
            SidebarSection(title: "Account", items: [.license])
        ]
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedView) {
                ForEach(sidebarSections) { section in
                    Section(section.title) {
                        ForEach(section.items) { viewType in
                            NavigationLink(value: viewType) {
                                Label(viewType.rawValue, systemImage: viewType.icon)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("VoiceInk")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            if let selectedView = selectedView {
                detailView(for: selectedView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(selectedView.rawValue)
            } else {
                Text("Select a view")
                    .foregroundColor(.secondary)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 880, minHeight: 730)
        .onAppear {
            logger.notice("ContentView appeared")
        }
        .onDisappear {
            logger.notice("ContentView disappeared")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = notification.userInfo?["destination"] as? String {
                logger.notice("navigateToDestination received: \(destination, privacy: .public)")
                switch destination {
                case "Settings":
                    selectedView = .settings
                case "AI Models":
                    selectedView = .models
                case "VoiceInk Pro":
                    selectedView = .license
                case "History":
                    selectedView = .history
                case "Permissions":
                    selectedView = .permissions
                case "Enhancement":
                    selectedView = .enhancement
                case "Power Mode":
                    selectedView = .powerMode
                default:
                    break
                }
            }
        }
    }
    
    @ViewBuilder
    private func detailView(for viewType: ViewType) -> some View {
        switch viewType {
        case .history:
            InlineHistoryView()
        case .statistics:
            StatisticsView()
        case .models:
            ModelManagementView()
        case .enhancement:
            EnhancementSettingsView()
        case .audioInput:
            AudioInputSettingsView()
        case .dictionary:
            DictionarySettingsView(whisperPrompt: whisperModelManager.whisperPrompt)
        case .powerMode:
            PowerModeView()
        case .settings:
            SettingsView()
        case .license:
            LicenseManagementView()
        case .permissions:
            PermissionsView()
        }
    }
}


import SwiftUI
import SwiftData
import OSLog

// ViewType enum with all cases mapped to high-fidelity mockup icons
enum ViewType: String, CaseIterable, Identifiable {
    case metrics = "Dashboard"
    case transcribeAudio = "Transcribe Audio"
    case history = "History"
    case models = "AI Models"
    case enhancement = "Enhancement"
    case powerMode = "Power Mode"
    case permissions = "Permissions"
    case audioInput = "Audio Input"
    case dictionary = "Dictionary"
    case visualSettings = "Visual Settings"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .metrics: return "squares.grid.2x2"
        case .transcribeAudio: return "waveform.circle"
        case .history: return "doc.text"
        case .models: return "brain.head.profile"
        case .enhancement: return "wand.and.stars"
        case .powerMode: return "sparkles.square.fill.on.square"
        case .permissions: return "shield"
        case .audioInput: return "mic"
        case .dictionary: return "character.book.closed"
        case .visualSettings: return "paintpalette"
        case .settings: return "gearshape"
        }
    }
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
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @AppStorage("powerModeUIFlag") private var powerModeUIFlag = false
    @State private var selectedView: ViewType? = .metrics
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    private var visibleViewTypes: [ViewType] {
        ViewType.allCases.filter { viewType in
            if viewType == .powerMode {
                return powerModeUIFlag
            }
            return true
        }
    }

    var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // App Header
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(red: 0.54, green: 0.12, blue: 0.92), Color(red: 0.28, green: 0.58, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))

                        Text("VoiceInk")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                    // Sidebar Navigation Links
                    ForEach(visibleViewTypes) { viewType in
                        Button(action: {
                            selectedView = viewType
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: viewType.icon)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(selectedView == viewType ? Color(red: 0.36, green: 0.28, blue: 0.88) : Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.65))
                                    .frame(width: 20, height: 20)

                                Text(viewType.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(selectedView == viewType ? Color(red: 0.12, green: 0.12, blue: 0.18) : Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.8))

                                Spacer()

                                if selectedView == viewType {
                                    Circle()
                                        .fill(Color(red: 0.36, green: 0.28, blue: 0.88))
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 16)
                            .background(
                                selectedView == viewType ?
                                LinearGradient(
                                    colors: [Color(red: 0.93, green: 0.91, blue: 0.99), Color(red: 0.95, green: 0.94, blue: 0.99)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) : nil
                            )
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 12)
                    }
                }
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.98))
            .navigationSplitViewColumnWidth(min: 220, ideal: 230, max: 250)
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
        .frame(width: 950)
        .frame(minHeight: 730)
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
                case "Visual Settings":
                    selectedView = .visualSettings
                case "AI Models":
                    selectedView = .models
                case "History":
                    selectedView = .history
                case "Enhancement":
                    selectedView = .enhancement
                case "Power Mode":
                    selectedView = .powerMode
                case "Transcribe Audio":
                    selectedView = .transcribeAudio
                case "Permissions":
                    selectedView = .permissions
                case "Audio Input":
                    selectedView = .audioInput
                case "Dictionary":
                    selectedView = .dictionary
                case "VoiceInk Pro":
                    selectedView = .settings
                default:
                    break
                }
            }
        }
    }
    
    @ViewBuilder
    private func detailView(for viewType: ViewType) -> some View {
        switch viewType {
        case .metrics:
            MetricsView()
        case .visualSettings:
            VisualSettingsView()
        case .settings:
            SettingsView()
        case .history:
            InlineHistoryView()
        case .models:
            ModelManagementView()
        case .enhancement:
            EnhancementSettingsView()
        case .powerMode:
            PowerModeView()
        case .transcribeAudio:
            AudioTranscribeView()
        case .permissions:
            PermissionsView()
        case .audioInput:
            AudioInputSettingsView()
        case .dictionary:
            DictionarySettingsView(whisperPrompt: whisperModelManager.whisperPrompt)
        }
    }
}

private struct SidebarItemView: View {
    let viewType: ViewType

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: viewType.icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24, height: 24)

            Text(viewType.rawValue)
                .font(.system(size: 14, weight: .medium))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
    }
}

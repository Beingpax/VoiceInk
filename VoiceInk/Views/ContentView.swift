import SwiftUI
import SwiftData
import KeyboardShortcuts

// ViewType enum with all cases
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
    case settings = "Settings"
    case license = "VoiceInk Pro"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .metrics: return "gauge.medium"
        case .transcribeAudio: return "waveform.circle.fill"
        case .history: return "doc.text.fill"
        case .models: return "brain.head.profile"
        case .enhancement: return "wand.and.stars"
        case .powerMode: return "sparkles.square.fill.on.square"
        case .permissions: return "shield.fill"
        case .audioInput: return "mic.fill"
        case .dictionary: return "character.book.closed.fill"
        case .settings: return "gearshape.fill"
        case .license: return "crown.fill"
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @AppStorage("powerModeUIFlag") private var powerModeUIFlag = false
    @State private var selectedView: ViewType? = .metrics
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    @StateObject private var licenseViewModel = LicenseViewModel()

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
            List(selection: $selectedView) {
                Section {
                    // App Header
                    HStack(spacing: 6) {
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .cornerRadius(8)
                        }

                        Text("VoiceInk")
                            .font(.system(size: 14, weight: .semibold))

                        if case .licensed = licenseViewModel.licenseState {
                            Text("PRO")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(4)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                ForEach(visibleViewTypes) { viewType in
                    Section {
                        NavigationLink(value: viewType) {
                            HStack(spacing: 12) {
                                Image(systemName: viewType.icon)
                                    .font(.system(size: 18, weight: .medium))
                                    .frame(width: 24, height: 24)

                                Text(viewType.rawValue)
                                    .font(.system(size: 14, weight: .medium))

                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 2)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("VoiceInk")
            .navigationSplitViewColumnWidth(210)
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
        .frame(minWidth: 940, minHeight: 730)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = notification.userInfo?["destination"] as? String {
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
                case "Transcribe Audio":
                    selectedView = .transcribeAudio
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
        case .metrics:
            MetricsView()
        case .models:
            ModelManagementView(whisperState: whisperState)
        case .enhancement:
            EnhancementSettingsView()
        case .transcribeAudio:
            AudioTranscribeView()
        case .history:
            TranscriptionHistoryView()
        case .audioInput:
            AudioInputSettingsView()
        case .dictionary:
            DictionarySettingsView(whisperPrompt: whisperState.whisperPrompt)
        case .powerMode:
            PowerModeView()
        case .settings:
            SettingsView()
                .environmentObject(whisperState)
        case .permissions:
            PermissionsView()
        case .license:
            LicenseManagementView()
                .environmentObject(licenseViewModel)
        }
    }
}

 

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
    case license = "VoiceInk Pro"

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
        case .license: return "checkmark.seal"
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

                        if case .licensed = licenseViewModel.licenseState {
                            Text("PRO")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Color(red: 0.36, green: 0.28, blue: 0.88))
                                .cornerRadius(4)
                        }

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
            .background(Color(red: 0.97, green: 0.97, blue: 0.98)) // Custom light cement mockup theme
            .safeAreaInset(edge: .bottom) {
                // Bottom Pro Plan Card
                VStack(spacing: 0) {
                    Divider()
                        .background(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.06))
                        .padding(.bottom, 12)

                    Button(action: {
                        selectedView = .license
                    }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .stroke(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.08), lineWidth: 2.5)
                                    .frame(width: 22, height: 22)

                                Circle()
                                    .trim(from: 0, to: 0.85)
                                    .stroke(
                                        AngularGradient(
                                            colors: [Color(red: 0.54, green: 0.12, blue: 0.92), Color(red: 0.28, green: 0.58, blue: 0.95), Color(red: 0.54, green: 0.12, blue: 0.92)],
                                            center: .center
                                        ),
                                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                                    )
                                    .frame(width: 22, height: 22)
                                    .rotationEffect(.degrees(-90))
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text("PRO PLAN")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))

                                Text("Active")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(red: 0.28, green: 0.65, blue: 0.45))
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.3))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.white.opacity(0.65))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.05), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .background(Color(red: 0.97, green: 0.97, blue: 0.98))
            }
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
                    selectedView = .license
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
        case .license:
            LicenseView()
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

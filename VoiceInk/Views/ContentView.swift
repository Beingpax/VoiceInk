import SwiftUI
import SwiftData
import KeyboardShortcuts
import Combine

// ViewType enum with all cases
enum ViewType: String, CaseIterable {
    case metrics = "Dashboard"
    case record = "Record Audio"
    case transcribeAudio = "Transcribe Audio"
    case history = "History"
    case models = "AI Models"
    case enhancement = "Enhancement"
    case powerMode = "Power Mode"
    case workflows = "Workflows"
    case permissions = "Permissions"
    case audioInput = "Audio Input"
    case dictionary = "Dictionary"
    case license = "VoiceInk Pro"
    case settings = "Settings"
    case about = "About"
    
    var icon: String {
        switch self {
        case .metrics: return "gauge.medium"
        case .record: return "mic.circle.fill"
        case .transcribeAudio: return "waveform.circle.fill"
        case .history: return "doc.text.fill"
        case .models: return "brain.head.profile"
        case .enhancement: return "wand.and.stars"
        case .powerMode: return "sparkles.square.fill.on.square"
        case .workflows: return "arrow.triangle.branch"
        case .permissions: return "shield.fill"
        case .audioInput: return "mic.fill"
        case .dictionary: return "character.book.closed.fill"
        case .license: return "checkmark.seal.fill"
        case .settings: return "gearshape.fill"
        case .about: return "info.circle.fill"
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

struct DynamicSidebar: View {
    @Binding var selectedView: ViewType
    @Binding var hoveredView: ViewType?
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var licenseViewModel = LicenseViewModel()
    @Namespace private var buttonAnimation

    var body: some View {
        VStack(spacing: 15) {
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
                
                #if DEVELOPMENT_MODE
                // Always show PRO badge in development mode
                Text("DEV")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.green)
                    .cornerRadius(4)
                #else
                if case .licensed = licenseViewModel.licenseState {
                    Text("PRO")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
                #endif
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Navigation Items
            ForEach(ViewType.allCases, id: \.self) { viewType in
                #if DEVELOPMENT_MODE
                // Skip license view in development mode
                if viewType != .license {
                    DynamicSidebarButton(
                        title: viewType.rawValue,
                        systemImage: viewType.icon,
                        isSelected: selectedView == viewType,
                        isHovered: hoveredView == viewType,
                        namespace: buttonAnimation
                    ) {
                        selectedView = viewType
                    }
                    .onHover { isHovered in
                        hoveredView = isHovered ? viewType : nil
                    }
                }
                #else
                DynamicSidebarButton(
                    title: viewType.rawValue,
                    systemImage: viewType.icon,
                    isSelected: selectedView == viewType,
                    isHovered: hoveredView == viewType,
                    namespace: buttonAnimation
                ) {
                    selectedView = viewType
                }
                .onHover { isHovered in
                    hoveredView = isHovered ? viewType : nil
                }
                #endif
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DynamicSidebarButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isHovered: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundColor(isSelected ? .white : (isHovered ? .accentColor : .primary))
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.5), radius: 5, x: 0, y: 2)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    }
                }
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var workflowManager: WorkflowManager
    @State private var selectedView: ViewType = .metrics
    @State private var hoveredView: ViewType?
    @State private var hasLoadedData = false
    @State private var showWorkflowErrorAlert = false
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    @StateObject private var licenseViewModel = LicenseViewModel()
    
    private var isSetupComplete: Bool {
        hasLoadedData &&
        whisperState.currentModel != nil &&
        KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil &&
        AXIsProcessTrusted() &&
        CGPreflightScreenCaptureAccess()
    }

    var body: some View {
        NavigationSplitView {
            DynamicSidebar(
                selectedView: $selectedView,
                hoveredView: $hoveredView
            )
            .frame(width: 200)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar(.hidden, for: .automatic)
                .navigationTitle("")
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1100, minHeight: 750)
       .background(Color(.controlBackgroundColor))
        .onAppear {
            hasLoadedData = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            print("ContentView: Received navigation notification")
            if let destination = notification.userInfo?["destination"] as? String {
                print("ContentView: Destination received: \(destination)")
                switch destination {
                case "Settings":
                    print("ContentView: Navigating to Settings")
                    selectedView = .settings
                case "AI Models":
                    print("ContentView: Navigating to AI Models")
                    selectedView = .models
                case "VoiceInk Pro":
                    print("ContentView: Navigating to VoiceInk Pro")
                    selectedView = .license
                case "History":
                    print("ContentView: Navigating to History")
                    selectedView = .history
                case "Permissions":
                    print("ContentView: Navigating to Permissions")
                    selectedView = .permissions
                case "Enhancement":
                    print("ContentView: Navigating to Enhancement")
                    selectedView = .enhancement
                case "Workflows":
                    print("ContentView: Navigating to Workflows")
                    selectedView = .workflows
                default:
                    print("ContentView: No matching destination found for: \(destination)")
                    break
                }
            } else {
                print("ContentView: No destination in notification")
            }
        }
        .alert("Workflow Error", isPresented: $showWorkflowErrorAlert) {
            Button("OK", role: .cancel) {
                // Clear the error message when user acknowledges it
                workflowManager.errorMessage = nil
            }
        } message: {
            if let errorMessage = workflowManager.errorMessage {
                Text(errorMessage)
            } else {
                Text("An unknown error occurred with the workflow.")
            }
        }
        .onChange(of: workflowManager.errorMessage) { newValue in
            // Only show alert in ContentView if we're not already in WorkflowsView
            showWorkflowErrorAlert = newValue != nil && selectedView != .workflows
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedView {
        case .metrics:
            if isSetupComplete {
                MetricsView(skipSetupCheck: true)
            } else {
                MetricsSetupView()
            }
        case .models:
            ModelManagementView(whisperState: whisperState)
        case .enhancement:
            EnhancementSettingsView()
        case .record:
            RecordView()
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
        case .workflows:
            WorkflowsView()
        case .settings:
            SettingsView()
                .environmentObject(whisperState)
        case .about:
            AboutView()
        case .license:
            LicenseManagementView()
        case .permissions:
            PermissionsView()
        }
    }
}

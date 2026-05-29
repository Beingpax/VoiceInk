import SwiftUI
import SwiftData

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .center,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

enum ConfigurationMode: Hashable {
    case add
    case edit(ModeConfig)
    
    var isAdding: Bool {
        if case .add = self { return true }
        return false
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .add:
            hasher.combine(0)
        case .edit(let config):
            hasher.combine(1)
            hasher.combine(config.id)
        }
    }
    
    static func == (lhs: ConfigurationMode, rhs: ConfigurationMode) -> Bool {
        switch (lhs, rhs) {
        case (.add, .add):
            return true
        case (.edit(let lhsConfig), .edit(let rhsConfig)):
            return lhsConfig.id == rhsConfig.id
        default:
            return false
        }
    }
}

enum ConfigurationType {
    case application
    case website
}

struct ModeView: View {
    @StateObject private var modeManager = ModeManager.shared
    @StateObject private var modeWarmupStore = ModeFormWarmupStore.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var activePanel: PanelType?
    @State private var panelID = UUID()

    private enum PanelType {
        case configuration(ConfigurationMode)
        case settings
    }

    private var isPanelOpen: Bool {
        activePanel != nil
    }
    
    var body: some View {
            VStack(spacing: 0) {
                // Header Section
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("Modes")
                                    .font(.system(size: 28, weight: .bold, design: .default))
                                    .foregroundColor(.primary)
                                
                                InfoTip(
                                    "Modes help you set up VoiceInk for different writing tasks, workflows, and scenarios.",
                                    learnMoreURL: "https://tryvoiceink.com/docs/modes"
                                )
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                openPanel(mode: .add)
                            }) {
                                Label("Add Mode", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .help("Add Mode")

                            Button(action: { openSettingsPanel() }) {
                                Label("Settings", systemImage: "gearshape")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .help("Modes Settings")
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                
                // Content Section
                Group {
                        GeometryReader { geometry in
                            ScrollView {
                                VStack(spacing: 0) {
                                    if modeManager.configurations.isEmpty {
                                        VStack(spacing: 24) {
                                            Spacer()
                                                .frame(height: geometry.size.height * 0.2)
                                            
                                            VStack(spacing: 16) {
                                                Image(systemName: "square.grid.2x2.fill")
                                                    .font(.system(size: 48, weight: .regular))
                                                    .foregroundColor(.secondary.opacity(0.6))
                                                
                                                VStack(spacing: 8) {
                                                    Text("No Modes Yet")
                                                        .font(.system(size: 20, weight: .medium))
                                                        .foregroundColor(.primary)
                                                    
                                                    Text("Create first mode to automate your VoiceInk workflow based on apps/website you are using")
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.secondary)
                                                        .multilineTextAlignment(.center)
                                                        .lineSpacing(2)
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: geometry.size.height)
                                    } else {
                                        VStack(spacing: 0) {
                                            ModeConfigurationsGrid(
                                                modeManager: modeManager,
                                                onEditConfig: { config in
                                                    openPanel(mode: .edit(config))
                                                }
                                            )
                                            .padding(.horizontal, 24)
                                            .padding(.vertical, 20)
                                            
                                            Spacer()
                                                .frame(height: 40)
                                        }
                                    }
                                }
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .sidePanel(isPresented: .init(
                get: { isPanelOpen },
                set: { if !$0 { closePanel() } }
            ), dismissOnExitCommand: false) {
                switch activePanel {
                case .configuration(let mode)?:
                    ModeConfigEditorView(mode: mode, modeManager: modeManager, onDismiss: closePanel)
                        .environmentObject(modeWarmupStore)
                        .id(panelID)
                case .settings?:
                    ModeSettingsPanelView(modeManager: modeManager, onDismiss: closePanel)
                case nil:
                    EmptyView()
                }
            }
            .onAppear {
                modeWarmupStore.configure(
                    aiService: aiService,
                    enhancementService: enhancementService,
                    transcriptionModelManager: transcriptionModelManager
                )
            }
    }

    private func openPanel(mode: ConfigurationMode) {
        panelID = UUID()
        activePanel = .configuration(mode)
    }

    private func closePanel() {
        activePanel = nil
    }

    private func openSettingsPanel() {
        activePanel = .settings
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }
}

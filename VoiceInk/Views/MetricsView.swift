import SwiftUI
import SwiftData
import Charts
import KeyboardShortcuts

struct MetricsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transcription.timestamp) private var transcriptions: [Transcription]
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @StateObject private var licenseViewModel = LicenseViewModel()
    @State private var hasLoadedData = false
    @State private var showDebugInfo = false
    let skipSetupCheck: Bool
    
    init(skipSetupCheck: Bool = false) {
        self.skipSetupCheck = skipSetupCheck
        
        // Print debug info to help diagnose compilation flag issues
        #if DEVELOPMENT_MODE
        print("🧪 MetricsView initialized in DEVELOPMENT MODE")
        #else
        print("⚠️ MetricsView initialized in NORMAL MODE (not development)")
        #endif
    }
    
    private var isDevelopmentMode: Bool {
        #if DEVELOPMENT_MODE
        return true
        #else
        return false
        #endif
    }
    
    var body: some View {
        VStack {
            // Debug info for development
            #if DEBUG
            Button("Debug Build Info") {
                showDebugInfo.toggle()
            }
            .buttonStyle(.plain)
            .font(.footnote)
            .padding(.top, 8)
            
            if showDebugInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build Configuration:")
                        .fontWeight(.bold)
                    #if DEVELOPMENT_MODE
                    Text("• DEVELOPMENT_MODE: ✅ Enabled")
                        .foregroundColor(.green)
                    #else
                    Text("• DEVELOPMENT_MODE: ❌ Disabled")
                        .foregroundColor(.red)
                    #endif
                    
                    Text("• License State: \(String(describing: licenseViewModel.licenseState))")
                    Text("• Can Use App: \(licenseViewModel.canUseApp ? "Yes" : "No")")
                }
                .font(.footnote)
                .padding()
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            #endif
            
            // Trial Message - only show if not in development mode
            #if !DEVELOPMENT_MODE
            if case .trial(let daysRemaining) = licenseViewModel.licenseState {
                TrialMessageView(
                    message: "You have \(daysRemaining) days left in your trial",
                    type: daysRemaining <= 2 ? .warning : .info
                )
                .padding()
            } else if case .trialExpired = licenseViewModel.licenseState {
                TrialMessageView(
                    message: "Your trial has expired. Upgrade to continue using VoiceInk",
                    type: .expired
                )
                .padding()
            }
            #endif
            
            Group {
                if skipSetupCheck {
                    MetricsContent(transcriptions: Array(transcriptions))
                } else if isSetupComplete {
                    MetricsContent(transcriptions: Array(transcriptions))
                } else {
                    MetricsSetupView()
                }
            }
        }
        .background(Color(.controlBackgroundColor))
        .task {
            // Ensure the model context is ready
            hasLoadedData = true
        }
    }
    
    private var isSetupComplete: Bool {
        hasLoadedData &&
        whisperState.currentModel != nil &&
        KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil &&
        AXIsProcessTrusted() &&
        CGPreflightScreenCaptureAccess()
    }
}

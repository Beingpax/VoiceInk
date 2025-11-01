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
    
    var body: some View {
        VStack {
            // Trial Message
            if case .trial(let daysRemaining) = licenseViewModel.licenseState {
                TrialMessageView(
                    message: "You have \(daysRemaining) days left in your trial",
                    type: daysRemaining <= 2 ? .warning : .info,
                    onAddLicenseKey: {
                        // Post notification to navigate to VoiceInk Pro tab
                        NotificationCenter.default.post(
                            name: .navigateToDestination,
                            object: nil,
                            userInfo: ["destination": "VoiceInk Pro"]
                        )
                    }
                )
                .padding()
            } else if case .trialExpired = licenseViewModel.licenseState {
                TrialMessageView(
                    message: "Your trial has expired. Upgrade to continue using VoiceInk",
                    type: .expired,
                    onAddLicenseKey: {
                        // Also allow navigation from expired state
                        NotificationCenter.default.post(
                            name: .navigateToDestination,
                            object: nil,
                            userInfo: ["destination": "VoiceInk Pro"]
                        )
                    }
                )
                .padding()
            }

            MetricsContent(
                transcriptions: Array(transcriptions),
                licenseState: licenseViewModel.licenseState
            )
        }
        .background(Color(.controlBackgroundColor))
    }
}

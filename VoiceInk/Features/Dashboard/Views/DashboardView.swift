import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @ObservedObject private var licenseViewModel = LicenseViewModel.shared
    @ObservedObject private var starPrompt = GitHubStarPromptCoordinator.shared

    var body: some View {
        DashboardContent(
            modelContext: modelContext,
            licenseState: licenseViewModel.licenseState,
            onAddLicenseKey: navigateToLicenseManagement
        )
        .overlay(alignment: .bottomTrailing) {
            if starPrompt.isVisible {
                GitHubStarPromptCard(
                    isBusy: starPrompt.isStarring,
                    completionState: starPrompt.completionState,
                    openFailed: starPrompt.openFailed,
                    onStar: { starPrompt.star() },
                    onLater: { starPrompt.later() }
                )
                // True corner anchor, sitting over Copy System Info rather than making room for it.
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: starPrompt.isVisible)
    }

    private func navigateToLicenseManagement() {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: ["destination": "VoiceInk Pro"]
        )
    }
}

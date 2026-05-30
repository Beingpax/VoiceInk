import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @StateObject private var licenseViewModel = LicenseViewModel()
    
    var body: some View {
        DashboardContent(
            modelContext: modelContext,
            licenseState: licenseViewModel.licenseState,
            onAddLicenseKey: navigateToLicenseManagement
        )
    }

    private func navigateToLicenseManagement() {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: ["destination": "VoiceInk Pro"]
        )
    }
}

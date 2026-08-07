import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RecordingShortcutManager.self) private var recordingShortcutManager
    @State private var licenseViewModel = LicenseViewModel()

    var body: some View {
        DashboardContent(
            modelContext: modelContext,
            licenseState: licenseViewModel.licenseState,
            onAddLicenseKey: navigateToLicenseManagement
        )
        .onReceive(NotificationCenter.default.publisher(for: .licenseStatusChanged)) { _ in
            licenseViewModel.refreshLicenseState()
        }
    }

    private func navigateToLicenseManagement() {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: ["destination": "VoiceInk Pro"]
        )
    }
}

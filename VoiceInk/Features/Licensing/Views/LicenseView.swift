import SwiftUI

struct LicenseView: View {
    @StateObject private var licenseViewModel = LicenseViewModel()

    var body: some View {
        VStack(spacing: 15) {
            Text("License Management")
                .font(.headline)

            if case .licensed = licenseViewModel.licenseState {
                VStack(spacing: 10) {
                    Text("Premium Features Activated")
                        .foregroundColor(AppTheme.Status.positive)

                    Button(
                        role: .destructive,
                        action: {
                            Task { await licenseViewModel.deactivateLicense() }
                        }
                    ) {
                        Text("Deactivate License")
                    }
                    .disabled(licenseViewModel.isDeactivating)
                }
            } else {
                TextField("Enter License Key", text: $licenseViewModel.licenseKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 300)

                Button(action: {
                    Task {
                        await licenseViewModel.validateLicense()
                    }
                }) {
                    if licenseViewModel.isValidating {
                        ProgressView()
                    } else {
                        Text("Activate License")
                    }
                }
                .disabled(licenseViewModel.isValidating)
            }

            if let message = licenseViewModel.validationMessage {
                Text(message)
                    .foregroundColor(
                        licenseViewModel.validationSuccess ? AppTheme.Status.positive : AppTheme.Status.error
                    )
                    .font(.caption)
            }
        }
        .padding()
    }
}

struct LicenseView_Previews: PreviewProvider {
    static var previews: some View {
        LicenseView()
    }
}

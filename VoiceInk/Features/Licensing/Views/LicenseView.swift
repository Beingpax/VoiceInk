import SwiftUI

struct LicenseView: View {
    @ObservedObject private var licenseViewModel = LicenseViewModel.shared
    @State private var licenseKeyDraft = ""

    var body: some View {
        VStack(spacing: 15) {
            Text("License Management")
                .font(.headline)

            if licenseViewModel.hasVerifiedLicense {
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
                TextField("Enter License Key", text: $licenseKeyDraft)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 300)

                Button(action: {
                    Task {
                        await licenseViewModel.validateLicense(licenseKeyDraft)
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
        .onChange(of: licenseViewModel.hasVerifiedLicense) { _, _ in
            licenseKeyDraft = ""
        }
    }
}

struct LicenseView_Previews: PreviewProvider {
    static var previews: some View {
        LicenseView()
    }
}

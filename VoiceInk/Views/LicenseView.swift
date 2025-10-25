import SwiftUI

struct LicenseView: View {
    @StateObject private var licenseViewModel = LicenseViewModel()

    var body: some View {
        VStack(spacing: 18) {
            Text("Community Edition")
                .font(.title2.weight(.semibold))

            Text(licenseViewModel.headline)
                .font(.headline)

            Text(licenseViewModel.subheadline)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 360)

            Divider().padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 12) {
                Text("Highlights")
                    .font(.headline)

                benefit("waveform", text: "Offline Whisper and Parakeet models bundled by default.")
                benefit("lock.shield", text: "Full functionality without license keys or paywalls.")
                benefit("sparkles", text: "Extensible prompts and enhancements without vendor lock-in.")
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func benefit(_ systemImage: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LicenseView_Previews: PreviewProvider {
    static var previews: some View {
        LicenseView()
    }
}

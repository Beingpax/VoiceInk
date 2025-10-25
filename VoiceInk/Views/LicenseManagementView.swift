import SwiftUI

struct LicenseManagementView: View {
    @StateObject private var licenseViewModel = LicenseViewModel()
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                heroSection
                builtInBenefits
                communitySection
                supportSection
            }
            .padding(36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var heroSection: some View {
        VStack(spacing: 20) {
            AppIconView()
                .frame(width: 96, height: 96)

            VStack(spacing: 8) {
                Text("VoiceInk Community Edition")
                    .font(.system(size: 32, weight: .bold))

                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 6) {
                Text(licenseViewModel.headline)
                    .font(.headline)
                Text(licenseViewModel.subheadline)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 520)
        }
        .padding()
    }

    private var builtInBenefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Everything Included", systemImage: "seal.fill")
                .font(.title3.weight(.semibold))

            Text("This fork removes trials and paywalls so the full transcription experience is immediately available. Local Whisper models and the Parakeet fast model ship ready to go—no external accounts or API keys required.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                benefitRow(symbol: "waveform", text: "Local Whisper + Parakeet models bundled for instant offline transcription.")
                benefitRow(symbol: "lock.shield", text: "All processing stays on-device by default—ideal for privacy-first workflows.")
                benefitRow(symbol: "sparkles", text: "Enhancement presets remain optional and can be extended without vendor lock-in.")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: false))
        .cornerRadius(16)
    }

    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Contribute Back", systemImage: "person.3.fill")
                .font(.title3.weight(.semibold))

            Text(licenseViewModel.contributionNote)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(licenseViewModel.communityResources) { resource in
                    resourceCard(resource)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: false))
        .cornerRadius(16)
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Stay Involved", systemImage: "hands.sparkles.fill")
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(licenseViewModel.supportLinks) { link in
                    resourceCard(link)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: false))
        .cornerRadius(16)
    }

    @ViewBuilder
    private func resourceCard(_ resource: LicenseViewModel.CommunityResource) -> some View {
        Button(action: {
            NSWorkspace.shared.open(resource.url)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                Label(resource.title, systemImage: resource.systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(.headline)

                Text(resource.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.windowBackgroundColor).opacity(0.55))
            )
        }
        .buttonStyle(.plain)
    }

    private func benefitRow(symbol: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

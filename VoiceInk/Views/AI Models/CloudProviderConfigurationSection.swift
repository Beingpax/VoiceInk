import SwiftUI

struct CloudProviderConfigurationSection: View {
    let provider: ModelProvider

    static func hasConfiguration(for provider: ModelProvider) -> Bool {
        switch provider {
        case .soniox:
            return true
        default:
            return false
        }
    }

    var body: some View {
        switch provider {
        case .soniox:
            SonioxRegionPickerView()
        default:
            EmptyView()
        }
    }
}

private struct SonioxRegionPickerView: View {
    @AppStorage(SonioxRegion.defaultsKey) private var regionRawValue = SonioxRegion.us.rawValue

    private var selectedRegion: SonioxRegion {
        SonioxRegion(rawValue: regionRawValue) ?? .us
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Soniox Region", selection: $regionRawValue) {
                ForEach(SonioxRegion.allCases) { region in
                    Text(region.displayName).tag(region.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: regionRawValue) { _, _ in
                NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            }

            Text(selectedRegion.restBaseURL.absoluteString)
                .font(.caption)
                .foregroundColor(Color(.secondaryLabelColor))
        }
    }
}

import SwiftUI

struct AppPickerPopover: View {
    let installedApps: [(url: URL, name: String, bundleId: String, icon: NSImage)]
    @Binding var selectedAppConfigs: [AppConfig]
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(installedApps, id: \.bundleId) { app in
                        let isSelected = selectedAppConfigs.contains(where: { $0.bundleIdentifier == app.bundleId })

                        Button {
                            toggleAppSelection(app)
                        } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                    .cornerRadius(6)

                                Text(app.name)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 280, height: 380)
    }

    private func toggleAppSelection(_ app: (url: URL, name: String, bundleId: String, icon: NSImage)) {
        if let index = selectedAppConfigs.firstIndex(where: { $0.bundleIdentifier == app.bundleId }) {
            selectedAppConfigs.remove(at: index)
        } else {
            selectedAppConfigs.append(AppConfig(bundleIdentifier: app.bundleId, appName: app.name))
        }
    }
}

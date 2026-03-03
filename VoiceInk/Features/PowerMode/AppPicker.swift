import SwiftUI

// App Picker Sheet
struct AppPickerSheet: View {
    let installedApps: [(url: URL, name: String, bundleId: String, icon: NSImage)]
    @Binding var selectedAppConfigs: [AppConfig]
    @Binding var searchText: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Select Applications")
                    .font(.headline)
                
                Spacer()
                
                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search applications...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
                
            // App Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)], spacing: 16) {
                    ForEach(installedApps.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), id: \.bundleId) { app in
                        AppGridItem(
                            app: app,
                            isSelected: selectedAppConfigs.contains(where: { $0.bundleIdentifier == app.bundleId }),
                            action: { 
                                toggleAppSelection(app)
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }
    
    private func toggleAppSelection(_ app: (url: URL, name: String, bundleId: String, icon: NSImage)) {
        if let index = selectedAppConfigs.firstIndex(where: { $0.bundleIdentifier == app.bundleId }) {
            selectedAppConfigs.remove(at: index)
        } else {
            let appConfig = AppConfig(bundleIdentifier: app.bundleId, appName: app.name)
            selectedAppConfigs.append(appConfig)
        }
    }
}

import SwiftUI

struct TriggerGroupEditorView: View {
    @Binding var group: ModeTriggerGroup
    let installedApps: [InstalledAppInfo]
    let reservedAppBundleIds: Set<String>
    let reservedWebsites: Set<String>
    let cleanURL: (String) -> String

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            addTriggerField
        }
        .frame(width: 340, height: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Edit the apps and websites in this group.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if group.isEmpty {
                    Text("No triggers in this group")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    ForEach(group.appConfigs) { appConfig in
                        groupAppRow(appConfig)
                    }

                    ForEach(group.urlConfigs) { urlConfig in
                        groupWebsiteRow(urlConfig)
                    }
                }
            }
            .padding(6)
        }
    }

    private var addTriggerField: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Add app or website...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit(addWebsiteIfPossible)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if canOfferWebsite {
                websiteSuggestionRow
                    .padding(.horizontal, 6)
            }

            appSuggestions
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var appSuggestions: some View {
        let apps = filteredApps.prefix(4)
        if !apps.isEmpty {
            VStack(spacing: 2) {
                ForEach(Array(apps), id: \.bundleId) { app in
                    Button {
                        addApp(app)
                    } label: {
                        HStack(spacing: 8) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                                .cornerRadius(5)
                            Text(app.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var websiteSuggestionRow: some View {
        Button(action: addWebsiteIfPossible) {
            HStack(spacing: 8) {
                TriggerSymbol(systemName: "globe")
                Text(String(format: String(localized: "Add %@"), websiteCandidate))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.Surface.card))
        }
        .buttonStyle(.plain)
    }

    private func groupAppRow(_ appConfig: AppConfig) -> some View {
        HStack(spacing: 10) {
            TriggerAppIcon(bundleId: appConfig.bundleIdentifier, size: 24)
            Text(appConfig.appName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            TriggerRemoveButton {
                group.appConfigs.removeAll { $0.id == appConfig.id }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func groupWebsiteRow(_ urlConfig: URLConfig) -> some View {
        HStack(spacing: 10) {
            TriggerSymbol(systemName: "globe")
            Text(urlConfig.url)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            TriggerRemoveButton {
                group.urlConfigs.removeAll { $0.id == urlConfig.id }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var filteredApps: [InstalledAppInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return installedApps.filter { app in
            !group.appConfigs.contains(where: { $0.bundleIdentifier == app.bundleId })
                && !reservedAppBundleIds.contains(app.bundleId)
                && (app.name.localizedCaseInsensitiveContains(query)
                    || app.bundleId.localizedCaseInsensitiveContains(query))
        }
    }

    private var websiteCandidate: String {
        cleanURL(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canOfferWebsite: Bool {
        isWebsiteLike(websiteCandidate) && !reservedWebsites.contains(websiteCandidate)
            && !group.urlConfigs.contains(where: { cleanURL($0.url) == websiteCandidate })
    }

    private func addApp(_ app: InstalledAppInfo) {
        guard !reservedAppBundleIds.contains(app.bundleId),
            !group.appConfigs.contains(where: { $0.bundleIdentifier == app.bundleId })
        else { return }
        group.appConfigs.append(AppConfig(bundleIdentifier: app.bundleId, appName: app.name))
        searchText = ""
    }

    private func addWebsiteIfPossible() {
        guard canOfferWebsite else { return }
        group.urlConfigs.append(URLConfig(url: websiteCandidate))
        searchText = ""
    }

    private func isWebsiteLike(_ value: String) -> Bool {
        guard !value.isEmpty,
            value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
            value.rangeOfCharacter(from: .alphanumerics) != nil
        else {
            return false
        }

        return value.contains(".") || value.contains(":") || value == "localhost"
    }
}

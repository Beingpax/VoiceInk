import SwiftUI

struct TriggerPickerPopover: View {
    let installedApps: [InstalledAppInfo]
    let isLoadingApps: Bool
    @Binding var appConfigs: [AppConfig]
    @Binding var websiteConfigs: [URLConfig]
    @Binding var triggerGroups: [ModeTriggerGroup]
    @Binding var searchText: String
    let cleanURL: (String) -> String

    @FocusState private var isSearchFieldFocused: Bool

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var snapshot: TriggerSnapshot {
        TriggerSnapshot(
            appConfigs: appConfigs,
            websiteConfigs: websiteConfigs,
            triggerGroups: triggerGroups,
            cleanURL: cleanURL
        )
    }

    private var filteredApps: [InstalledAppInfo] {
        guard !query.isEmpty else { return installedApps }
        return installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.bundleId.localizedCaseInsensitiveContains(query)
        }
    }

    private var websiteCandidate: String {
        cleanURL(query)
    }

    private var canOfferWebsite: Bool {
        isWebsiteLike(websiteCandidate)
    }

    private var isWebsiteAlreadyAdded: Bool {
        snapshot.websites.contains(websiteCandidate)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    if query.isEmpty {
                        suggestedGroups
                    }

                    if canOfferWebsite {
                        websiteCandidateRow
                    }

                    appList
                }
                .padding(6)
            }
        }
        .frame(width: 340, height: 440)
        .onAppear {
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            TextField("Search apps or enter website...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFieldFocused)
                .onSubmit(addWebsiteIfPossible)

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
    }

    private var suggestedGroups: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.top, 2)

            ForEach(TriggerTemplateCatalog.templates) { template in
                TriggerTemplateRow(
                    template: template,
                    group: template.availableGroup(
                        installedApps: installedApps,
                        existingAppBundleIds: snapshot.appBundleIds,
                        existingWebsites: snapshot.websites,
                        cleanURL: cleanURL
                    ),
                    isAdded: snapshot.templateIds.contains(template.id),
                    isLoadingApps: isLoadingApps,
                    onAdd: addTemplateGroup
                )
            }

            Divider()
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var appList: some View {
        if isLoadingApps && installedApps.isEmpty {
            loadingState
        } else if filteredApps.isEmpty && !canOfferWebsite {
            emptyState
        } else {
            ForEach(filteredApps, id: \.bundleId) { app in
                appRow(app)
            }
        }
    }

    private var websiteCandidateRow: some View {
        Button(action: addWebsiteIfPossible) {
            HStack(spacing: 10) {
                TriggerSymbol(systemName: isWebsiteAlreadyAdded ? "checkmark" : "globe")

                VStack(alignment: .leading, spacing: 1) {
                    Text(isWebsiteAlreadyAdded ? "Website already added" : "Add website")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(websiteCandidate)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isWebsiteAlreadyAdded {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func appRow(_ app: InstalledAppInfo) -> some View {
        let isSelected = snapshot.appBundleIds.contains(app.bundleId)

        return Button {
            guard !isSelected else { return }
            appConfigs.append(AppConfig(bundleIdentifier: app.bundleId, appName: app.name))
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)

                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .secondary : .primary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.secondary.opacity(0.08) : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(isSelected)
    }

    private var emptyState: some View {
        Text(query.isEmpty ? "No apps found" : "No matching apps")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading apps")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func addTemplateGroup(_ group: ModeTriggerGroup) {
        if let templateId = group.templateId,
           triggerGroups.contains(where: { $0.templateId == templateId }) {
            return
        }

        let currentSnapshot = snapshot
        var availableGroup = group
        availableGroup.appConfigs = group.appConfigs.filter {
            !currentSnapshot.appBundleIds.contains($0.bundleIdentifier)
        }
        availableGroup.urlConfigs = group.urlConfigs.filter {
            !currentSnapshot.websites.contains(cleanURL($0.url))
        }

        guard !availableGroup.isEmpty else { return }
        triggerGroups.append(availableGroup)
    }

    private func addWebsiteIfPossible() {
        guard canOfferWebsite, !isWebsiteAlreadyAdded else { return }
        websiteConfigs.append(URLConfig(url: websiteCandidate))
        searchText = ""
    }

    private func isWebsiteLike(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              value.rangeOfCharacter(from: .alphanumerics) != nil else {
            return false
        }

        return value.contains(".") || value.contains(":") || value == "localhost"
    }
}

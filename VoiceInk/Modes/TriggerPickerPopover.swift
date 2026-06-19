import SwiftUI

struct TriggerPickerPopover: View {
    let installedApps: [InstalledAppInfo]
    let isLoadingApps: Bool
    let currentModeId: UUID
    @Binding var appConfigs: [AppConfig]
    @Binding var websiteConfigs: [URLConfig]
    @Binding var triggerGroups: [ModeTriggerGroup]
    @Binding var triggerWords: [String]
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
        return installedApps.compactMap { app -> (app: InstalledAppInfo, rank: Int)? in
            guard let rank = appSearchRank(app, matching: query) else { return nil }
            return (app, rank)
        }
        .sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
        }
        .map { $0.app }
    }

    private func appSearchRank(_ app: InstalledAppInfo, matching query: String) -> Int? {
        let term = query.lowercased()
        let name = app.name.lowercased()
        let bundleId = app.bundleId.lowercased()

        if name == term { return 0 }
        if name.hasPrefix(term) { return 1 }
        if name.contains(term) { return 2 }
        if bundleId.hasPrefix(term) { return 3 }
        if bundleId.contains(term) { return 4 }

        return nil
    }

    private var websiteCandidate: String {
        cleanURL(query)
    }

    private var canOfferWebsite: Bool {
        isWebsiteLike(websiteCandidate)
    }

    private var otherConfigurations: [ModeConfig] {
        ModeManager.shared.configurations.filter { $0.id != currentModeId }
    }

    private var isWebsiteAlreadyAdded: Bool {
        snapshot.websites.contains(websiteCandidate)
    }

    private var canOfferTriggerWord: Bool {
        !query.isEmpty && !isWebsiteLike(websiteCandidate)
    }

    private var isTriggerWordAlreadyAdded: Bool {
        triggerWords.contains { $0.localizedCaseInsensitiveCompare(query) == .orderedSame }
    }

    private var triggerWordClaimedByOtherMode: ModeConfig? {
        otherConfigurations.first { mode in
            mode.triggerWords.contains { $0.localizedCaseInsensitiveCompare(query) == .orderedSame }
        }
    }

    private func appClaimedByOtherMode(_ bundleId: String) -> ModeConfig? {
        otherConfigurations.first { mode in
            mode.allAppConfigs.contains { $0.bundleIdentifier == bundleId }
        }
    }

    private var websiteClaimedByOtherMode: ModeConfig? {
        otherConfigurations.first { mode in
            mode.allURLConfigs.contains { cleanURL($0.url) == websiteCandidate }
        }
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

                    if canOfferTriggerWord {
                        triggerWordCandidateRow
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

            TextField("Search apps, website, or trigger word...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFieldFocused)
                .onSubmit(submitSearch)

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
                let isAdded = snapshot.templateIds.contains(template.id)
                let group = templateGroup(for: template, isAdded: isAdded)

                TriggerTemplateRow(
                    template: template,
                    group: group,
                    isAdded: isAdded,
                    isLoadingApps: isLoadingApps,
                    onToggle: { group in
                        toggleTemplateGroup(group, templateId: template.id)
                    }
                )
            }

            Divider()
                .padding(.vertical, 4)
        }
    }

    private func templateGroup(for template: TriggerTemplate, isAdded: Bool) -> ModeTriggerGroup {
        if isAdded, let selectedGroup = selectedTemplateGroup(template.id) {
            return selectedGroup
        }

        return availableTemplateGroup(for: template)
    }

    private func availableTemplateGroup(for template: TriggerTemplate) -> ModeTriggerGroup {
        template.availableGroup(
            installedApps: installedApps,
            existingAppBundleIds: snapshot.appBundleIds,
            existingWebsites: snapshot.websites,
            cleanURL: cleanURL
        )
    }

    private func selectedTemplateGroup(_ templateId: String) -> ModeTriggerGroup? {
        triggerGroups.first { $0.templateId == templateId }
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
        let claimedBy = websiteClaimedByOtherMode

        return triggerCandidateRow(
            systemName: "globe",
            isSelected: isWebsiteAlreadyAdded,
            claimedBy: claimedBy,
            unavailableMessage: "Each website can only belong to one mode",
            addTitle: "Add website",
            removeTitle: "Remove website",
            detail: websiteCandidate,
            action: toggleWebsiteCandidate
        )
    }

    private func triggerCandidateRow(
        systemName: String,
        isSelected: Bool,
        claimedBy: ModeConfig?,
        unavailableMessage: String,
        addTitle: LocalizedStringKey,
        removeTitle: LocalizedStringKey,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        let isUnavailable = claimedBy != nil && !isSelected
        let symbolName = isSelected ? "checkmark" : (isUnavailable ? "exclamationmark.triangle" : systemName)

        return Button(action: action) {
            HStack(spacing: 10) {
                TriggerSymbol(systemName: symbolName)

                VStack(alignment: .leading, spacing: 1) {
                    if isUnavailable, let claimedBy {
                        Text("Already used by \"\(claimedBy.name)\"")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(unavailableMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(isSelected ? removeTitle : addTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !isSelected && !isUnavailable {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.Surface.card))
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
    }

    private func appRow(_ app: InstalledAppInfo) -> some View {
        let isSelected = snapshot.appBundleIds.contains(app.bundleId)
        let claimedBy = isSelected ? nil : appClaimedByOtherMode(app.bundleId)

        return Button {
            toggleApp(app)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)

                if let claimedBy {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text("Used by \"\(claimedBy.name)\"")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(claimedBy != nil)
    }

    private var emptyState: some View {
        Text(query.isEmpty ? LocalizedStringKey("No apps found") : LocalizedStringKey("No matching apps"))
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

    private func toggleTemplateGroup(_ group: ModeTriggerGroup, templateId: String) {
        if triggerGroups.contains(where: { $0.templateId == templateId }) {
            triggerGroups.removeAll { $0.templateId == templateId }
        } else {
            addTemplateGroup(group)
        }
    }

    private func addTemplateGroup(_ group: ModeTriggerGroup) {
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

    private var triggerWordCandidateRow: some View {
        let claimedBy = triggerWordClaimedByOtherMode

        return triggerCandidateRow(
            systemName: "mic.fill",
            isSelected: isTriggerWordAlreadyAdded,
            claimedBy: claimedBy,
            unavailableMessage: "Each trigger word can only belong to one mode",
            addTitle: "Add trigger word",
            removeTitle: "Remove trigger word",
            detail: "Say \"\(query)\" to activate this mode",
            action: toggleTriggerWordCandidate
        )
    }

    private func submitSearch() {
        if canOfferWebsite {
            addWebsiteIfPossible()
        } else if canOfferTriggerWord {
            addTriggerWordIfPossible()
        }
    }

    private func addTriggerWordIfPossible() {
        guard canOfferTriggerWord, !isTriggerWordAlreadyAdded, triggerWordClaimedByOtherMode == nil else { return }
        let normalized = ModeConfig.normalizedTriggerWords([query]).first ?? query
        triggerWords.append(normalized)
        searchText = ""
    }

    private func toggleTriggerWordCandidate() {
        guard canOfferTriggerWord else { return }
        if isTriggerWordAlreadyAdded {
            triggerWords.removeAll { $0.localizedCaseInsensitiveCompare(query) == .orderedSame }
        } else {
            addTriggerWordIfPossible()
        }
    }

    private func addWebsiteIfPossible() {
        guard canOfferWebsite, !isWebsiteAlreadyAdded, websiteClaimedByOtherMode == nil else { return }
        websiteConfigs.append(URLConfig(url: websiteCandidate))
        searchText = ""
    }

    private func toggleWebsiteCandidate() {
        guard canOfferWebsite else { return }
        if isWebsiteAlreadyAdded {
            removeWebsite(websiteCandidate)
        } else {
            addWebsiteIfPossible()
        }
    }

    private func toggleApp(_ app: InstalledAppInfo) {
        if snapshot.appBundleIds.contains(app.bundleId) {
            removeApp(bundleId: app.bundleId)
        } else {
            appConfigs.append(AppConfig(bundleIdentifier: app.bundleId, appName: app.name))
        }
    }

    private func removeApp(bundleId: String) {
        appConfigs.removeAll { $0.bundleIdentifier == bundleId }
        for index in triggerGroups.indices {
            triggerGroups[index].appConfigs.removeAll { $0.bundleIdentifier == bundleId }
        }
        triggerGroups.removeAll { $0.isEmpty }
    }

    private func removeWebsite(_ website: String) {
        let cleanedWebsite = cleanURL(website)
        websiteConfigs.removeAll { cleanURL($0.url) == cleanedWebsite }
        for index in triggerGroups.indices {
            triggerGroups[index].urlConfigs.removeAll { cleanURL($0.url) == cleanedWebsite }
        }
        triggerGroups.removeAll { $0.isEmpty }
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

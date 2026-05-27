import SwiftUI

struct ModeTriggerSection: View {
    @Binding var appConfigs: [AppConfig]
    @Binding var websiteConfigs: [URLConfig]
    let cleanURL: (String) -> String

    @State private var isShowingTriggerPicker = false
    @State private var installedApps: [InstalledAppInfo] = []
    @State private var triggerSearchText = ""
    @State private var isLoadingInstalledApps = false
    @State private var hasLoadedInstalledApps = false

    var body: some View {
        Section {
            if hasSelectedTriggers {
                selectedTriggers
                    .padding(.vertical, 2)
            } else {
                emptyTriggerState
            }
        } header: {
            triggerHeader
        }
    }

    private var hasSelectedTriggers: Bool {
        !appConfigs.isEmpty || !websiteConfigs.isEmpty
    }

    private var triggerHeader: some View {
        HStack {
            HStack(spacing: 4) {
                Text("Triggers")
                InfoTip("VoiceInk automatically switches to this mode when you use the apps or websites you add here.")
            }

            Spacer()

            AddIconButton(helpText: "Add trigger") {
                triggerSearchText = ""
                isShowingTriggerPicker = true
                loadInstalledAppsIfNeeded()
            }
            .popover(isPresented: $isShowingTriggerPicker, arrowEdge: .bottom) {
                TriggerPickerPopover(
                    installedApps: installedApps,
                    isLoadingApps: isLoadingInstalledApps,
                    selectedAppConfigs: $appConfigs,
                    websiteConfigs: $websiteConfigs,
                    searchText: $triggerSearchText,
                    cleanURL: cleanURL
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyTriggerState: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("No automatic triggers")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var selectedTriggers: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appConfigs.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 38), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(appConfigs) { appConfig in
                        TriggerAppToken(appConfig: appConfig) {
                            appConfigs.removeAll(where: { $0.id == appConfig.id })
                        }
                    }
                }
            }

            if !websiteConfigs.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(websiteConfigs) { urlConfig in
                        TriggerWebsiteToken(urlConfig: urlConfig) {
                            websiteConfigs.removeAll(where: { $0.id == urlConfig.id })
                        }
                    }
                }
            }
        }
    }

    private func loadInstalledAppsIfNeeded() {
        guard !hasLoadedInstalledApps, !isLoadingInstalledApps else { return }

        isLoadingInstalledApps = true

        DispatchQueue.global(qos: .userInitiated).async {
            let apps = InstalledApps.load()

            DispatchQueue.main.async {
                installedApps = apps
                hasLoadedInstalledApps = true
                isLoadingInstalledApps = false
            }
        }
    }
}

private typealias InstalledAppInfo = (url: URL, name: String, bundleId: String, icon: NSImage)

private enum InstalledApps {
    static func load() -> [InstalledAppInfo] {
        let userAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
        let localAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
        let systemAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask)
        let allAppURLs = userAppURLs + localAppURLs + systemAppURLs

        var allApps: [URL] = []

        func scanDirectory(_ baseURL: URL, depth: Int = 0) {
            guard depth < 5 else { return }
            guard let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for item in enumerator {
                guard let url = item as? URL else { continue }
                let resolvedURL = url.resolvingSymlinksInPath()

                if resolvedURL.pathExtension == "app" {
                    allApps.append(resolvedURL)
                    enumerator.skipDescendants()
                    continue
                }

                var isDirectory: ObjCBool = false
                if url != resolvedURL &&
                   FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) &&
                   isDirectory.boolValue {
                    enumerator.skipDescendants()
                    scanDirectory(resolvedURL, depth: depth + 1)
                }
            }
        }

        for baseURL in allAppURLs {
            scanDirectory(baseURL)
        }

        let apps: [InstalledAppInfo] = allApps.compactMap { (url: URL) -> InstalledAppInfo? in
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier,
                  let name = (bundle.infoDictionary?["CFBundleName"] as? String) ??
                            (bundle.infoDictionary?["CFBundleDisplayName"] as? String) else {
                return nil
            }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (url: url, name: name, bundleId: bundleId, icon: icon)
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        var seenBundleIds = Set<String>()
        return apps.filter { app in
            seenBundleIds.insert(app.bundleId).inserted
        }
    }
}

private struct TriggerPickerPopover: View {
    let installedApps: [InstalledAppInfo]
    let isLoadingApps: Bool
    @Binding var selectedAppConfigs: [AppConfig]
    @Binding var websiteConfigs: [URLConfig]
    @Binding var searchText: String
    let cleanURL: (String) -> String

    @FocusState private var isSearchFieldFocused: Bool

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredApps: [InstalledAppInfo] {
        guard !query.isEmpty else { return installedApps }

        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(query) ||
            app.bundleId.localizedCaseInsensitiveContains(query)
        }
    }

    private var websiteCandidate: String {
        cleanURL(query)
    }

    private var canOfferWebsite: Bool {
        isWebsiteLike(websiteCandidate)
    }

    private var isWebsiteAlreadyAdded: Bool {
        websiteConfigs.contains { cleanURL($0.url) == websiteCandidate }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    if canOfferWebsite {
                        websiteCandidateRow

                        if !filteredApps.isEmpty {
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }

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
                .padding(6)
            }
        }
        .frame(width: 320, height: 420)
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

    private var websiteCandidateRow: some View {
        Button {
            addWebsiteIfPossible()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: 28, height: 28)

                    Image(systemName: isWebsiteAlreadyAdded ? "checkmark" : "globe")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(isWebsiteAlreadyAdded ? "Website already added" : "Add website")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(websiteCandidate)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
    }

    private func appRow(_ app: InstalledAppInfo) -> some View {
        let isSelected = selectedAppConfigs.contains(where: { $0.bundleIdentifier == app.bundleId })

        return Button {
            toggleAppSelection(app)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)

                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.secondary.opacity(0.10) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color(NSColor.separatorColor).opacity(0.7) : Color.clear, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)

            Text(query.isEmpty ? "No apps found" : "No matching apps")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
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

    private func toggleAppSelection(_ app: InstalledAppInfo) {
        if let index = selectedAppConfigs.firstIndex(where: { $0.bundleIdentifier == app.bundleId }) {
            selectedAppConfigs.remove(at: index)
        } else {
            selectedAppConfigs.append(AppConfig(bundleIdentifier: app.bundleId, appName: app.name))
        }
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

private struct TriggerAppToken: View {
    let appConfig: AppConfig
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TriggerAppIcon(bundleId: appConfig.bundleIdentifier, size: 30)
                .padding(3)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                }

            TriggerTokenRemoveButton(action: onRemove)
                .offset(x: 5, y: -5)
        }
        .frame(width: 38, height: 38)
        .help(appConfig.appName)
    }
}

private struct TriggerWebsiteToken: View {
    let urlConfig: URLConfig
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 20, height: 20)
                .background {
                    Circle()
                        .fill(Color.secondary.opacity(0.10))
                }

            Text(urlConfig.url)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            TriggerTokenRemoveButton(action: onRemove)
        }
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
        }
    }
}

private struct TriggerAppIcon: View {
    let bundleId: String
    var size: CGFloat = 20

    var body: some View {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: size * 0.58, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(Color(NSColor.controlBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                }
        }
    }
}

private struct TriggerTokenRemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Remove trigger")
    }
}

import SwiftUI

struct TriggerGroupRow: View {
    @Binding var group: ModeTriggerGroup
    let installedApps: [InstalledAppInfo]
    let reservedAppBundleIds: Set<String>
    let reservedWebsites: Set<String>
    let cleanURL: (String) -> String
    let loadInstalledAppsIfNeeded: () -> Void
    let onRemove: () -> Void

    @State private var isShowingEditor = false

    var body: some View {
        HStack(spacing: 10) {
            TriggerSymbol(systemName: groupSystemImage)

            Text(group.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                TriggerGroupPreviewStack(appConfigs: group.appConfigs, urlConfigs: group.urlConfigs)

                TriggerEditButton {
                    loadInstalledAppsIfNeeded()
                    isShowingEditor = true
                }
                .popover(isPresented: $isShowingEditor, arrowEdge: .bottom) {
                    TriggerGroupEditorView(
                        group: $group,
                        installedApps: installedApps,
                        reservedAppBundleIds: reservedAppBundleIds,
                        reservedWebsites: reservedWebsites,
                        cleanURL: cleanURL
                    )
                }

                TriggerRemoveButton {
                    isShowingEditor = false
                    onRemove()
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.Surface.control)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.Border.control, lineWidth: 0.5)
        }
        .help(group.summaryText)
    }

    private var groupSystemImage: String {
        guard let templateId = group.templateId,
            let template = TriggerTemplateCatalog.templates.first(where: { $0.id == templateId })
        else {
            return "folder"
        }

        return template.systemImage
    }
}

struct TriggerAppChip: View {
    let appConfig: AppConfig
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TriggerAppIcon(bundleId: appConfig.bundleIdentifier, size: 30)
                .padding(3)
                .background(AppCardBackground(cornerRadius: 8))

            TriggerRemoveButton(action: onRemove)
                .offset(x: 5, y: -5)
        }
        .frame(width: 38, height: 38)
        .help(appConfig.appName)
    }
}

struct TriggerWebsiteChip: View {
    let urlConfig: URLConfig
    let onRemove: () -> Void

    var body: some View {
        TriggerTextChip(
            systemName: "globe",
            title: urlConfig.url,
            truncationMode: .middle,
            removeHelp: "Remove website",
            onRemove: onRemove
        )
    }
}

struct TriggerWordChip: View {
    let word: String
    let onRemove: () -> Void

    var body: some View {
        TriggerTextChip(
            systemName: "mic.fill",
            title: word,
            truncationMode: .tail,
            removeHelp: "Remove trigger word",
            onRemove: onRemove
        )
    }
}

private struct TriggerTextChip: View {
    let systemName: String
    let title: String
    let truncationMode: Text.TruncationMode
    let removeHelp: LocalizedStringKey
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(truncationMode)
                .frame(maxWidth: 100, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help(removeHelp)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppCardBackground(cornerRadius: 7))
    }
}

struct TriggerGroupPreviewStack: View {
    let appConfigs: [AppConfig]
    let urlConfigs: [URLConfig]
    var tileSize: CGFloat = 28

    private var items: [TriggerGroupPreviewItem] {
        let totalCount = appConfigs.count + urlConfigs.count

        guard totalCount > 0 else { return [.empty] }

        let appItems = appConfigs.prefix(visibleAppCount).map { TriggerGroupPreviewItem.app($0.bundleIdentifier) }
        return appItems + (showsWebsiteTile ? [.website] : [])
    }

    private var stackWidth: CGFloat {
        tileSize + CGFloat(max(items.count - 1, 0)) * overlapOffset
    }

    private var overlapOffset: CGFloat {
        tileSize * 0.48
    }

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .leading) {
                ForEach(items.indices, id: \.self) { index in
                    previewTile(for: items[index])
                        .offset(x: CGFloat(index) * overlapOffset)
                        .zIndex(Double(index))
                }
            }
            .frame(width: stackWidth, height: tileSize)

            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.system(size: tileSize * 0.30, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 5)
                    .frame(height: tileSize - 2)
                    .background {
                        RoundedRectangle(cornerRadius: tileSize * 0.32)
                            .fill(AppTheme.Surface.control)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: tileSize * 0.32)
                            .strokeBorder(AppTheme.Border.control, lineWidth: 0.5)
                    }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func previewTile(for item: TriggerGroupPreviewItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: tileSize * 0.24)
                .fill(tileBackground(for: item))

            switch item {
            case .app(let bundleId):
                TriggerAppIcon(bundleId: bundleId, size: tileSize - 6)
            case .website:
                ZStack {
                    Circle()
                        .fill(AppTheme.Surface.card)
                        .frame(width: tileSize - 8, height: tileSize - 8)
                    Image(systemName: "globe")
                        .font(.system(size: tileSize * 0.38, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            case .empty:
                Image(systemName: "folder")
                    .font(.system(size: tileSize * 0.43, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: tileSize, height: tileSize)
        .overlay {
            RoundedRectangle(cornerRadius: tileSize * 0.24)
                .strokeBorder(AppTheme.Border.control, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 2.5, x: 0, y: 1)
    }

    private func tileBackground(for item: TriggerGroupPreviewItem) -> Color {
        switch item {
        case .empty:
            return AppTheme.Surface.control
        case .app, .website:
            return AppTheme.Surface.window
        }
    }

    private var visibleAppCount: Int {
        min(appConfigs.count, urlConfigs.isEmpty ? 5 : 4)
    }

    private var showsWebsiteTile: Bool {
        !urlConfigs.isEmpty
    }

    private var representedCount: Int {
        visibleAppCount + (showsWebsiteTile ? 1 : 0)
    }

    private var overflowCount: Int {
        max(appConfigs.count + urlConfigs.count - representedCount, 0)
    }
}

private enum TriggerGroupPreviewItem: Equatable {
    case app(String)
    case website
    case empty
}

struct TriggerAppIcon: View {
    let bundleId: String
    var size: CGFloat = 20

    var body: some View {
        if let icon = TriggerAppIconCache.shared.icon(for: bundleId) {
            Image(nsImage: icon)
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
                        .fill(AppTheme.Surface.control)
                }
        }
    }
}

struct TriggerRemoveButton: View {
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

struct TriggerEditButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Edit trigger group")
    }
}

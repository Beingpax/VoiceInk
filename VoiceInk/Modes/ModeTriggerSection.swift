import SwiftUI

struct ModeTriggerSection: View {
    @Binding var appConfigs: [AppConfig]
    @Binding var websiteConfigs: [URLConfig]
    @Binding var triggerGroups: [ModeTriggerGroup]
    let cleanURL: (String) -> String

    @State private var isShowingTriggerPicker = false
    @State private var installedApps: [InstalledAppInfo] = []
    @State private var triggerSearchText = ""
    @State private var isLoadingInstalledApps = false
    @State private var hasLoadedInstalledApps = false

    private var hasSelectedTriggers: Bool {
        !triggerGroups.isEmpty || !appConfigs.isEmpty || !websiteConfigs.isEmpty
    }

    var body: some View {
        Section {
            if hasSelectedTriggers {
                ModeTriggerSelectionView(
                    appConfigs: $appConfigs,
                    websiteConfigs: $websiteConfigs,
                    triggerGroups: $triggerGroups,
                    installedApps: installedApps,
                    cleanURL: cleanURL,
                    loadInstalledAppsIfNeeded: loadInstalledAppsIfNeeded
                )
                .padding(.vertical, 2)
            } else {
                emptyTriggerState
            }
        } header: {
            triggerHeader
        }
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
                    appConfigs: $appConfigs,
                    websiteConfigs: $websiteConfigs,
                    triggerGroups: $triggerGroups,
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

import SwiftUI

struct ModeTriggerSection: View {
    @Binding var appConfigs: [AppConfig]
    @Binding var websiteConfigs: [URLConfig]
    @Binding var triggerGroups: [ModeTriggerGroup]
    let modeId: UUID
    let cleanURL: (String) -> String

    @EnvironmentObject private var modeWarmupStore: ModeFormWarmupStore

    @State private var isShowingTriggerPicker = false
    @State private var triggerSearchText = ""

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
                    installedApps: modeWarmupStore.installedApps,
                    cleanURL: cleanURL,
                    loadInstalledAppsIfNeeded: modeWarmupStore.refreshInstalledApps
                )
                .padding(.vertical, 2)
            } else {
                emptyTriggerState
            }

            HStack {
                Text("Keyboard Shortcut")
                InfoTip("Assign a unique keyboard shortcut to instantly activate this mode and start recording.")

                Spacer()

                ShortcutRecorder(action: .mode(modeId))
                    .frame(minHeight: 28)
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
                modeWarmupStore.refreshInstalledApps()
            }
            .popover(isPresented: $isShowingTriggerPicker, arrowEdge: .bottom) {
                TriggerPickerPopover(
                    installedApps: modeWarmupStore.installedApps,
                    isLoadingApps: modeWarmupStore.isLoadingInstalledApps,
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
}

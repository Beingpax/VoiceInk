import SwiftUI
import UniformTypeIdentifiers

struct PowerModeSettingsPanelView: View {
    @ObservedObject var powerModeManager: PowerModeManager
    @AppStorage("powerModePersistConfig") private var persistModeConfig = false
    let onDismiss: () -> Void

    private let contentInset: CGFloat = 20
    private let rowCornerRadius: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Modes Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider().opacity(0.5), alignment: .bottom)

            VStack(alignment: .leading, spacing: 8) {
                Text("Behavior")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)

                Toggle(isOn: $persistModeConfig) {
                    HStack(spacing: 6) {
                        Text("Persist Mode Settings")
                            .font(.system(size: 13, weight: .medium))

                        InfoTip("When enabled, the Mode settings applied for recording stay active after the recording ends. When disabled, VoiceInk restores the transcription, enhancement, language, and model settings that were active before the Mode was applied.")

                        Spacer(minLength: 8)
                    }
                }
                .toggleStyle(.switch)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: rowCornerRadius)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, contentInset)

            HStack {
                Text("Reorder Modes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, contentInset)
            .padding(.top, 18)
            .padding(.bottom, 8)

            PowerModeReorderList(powerModeManager: powerModeManager)
                .padding(.horizontal, contentInset)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onExitCommand(perform: onDismiss)
    }

}

private struct PowerModeReorderList: View {
    @ObservedObject var powerModeManager: PowerModeManager

    @State private var draggedConfigID: UUID?
    @State private var targetedConfigID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(powerModeManager.configurations) { config in
                    PowerModeReorderRow(
                        config: config,
                        isDragged: draggedConfigID == config.id,
                        isTargeted: targetedConfigID == config.id
                    )
                    .onDrag {
                        draggedConfigID = config.id
                        return NSItemProvider(object: config.id.uuidString as NSString)
                    } preview: {
                        PowerModeReorderDragPreview(config: config)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: PowerModeReorderDropDelegate(
                            item: config,
                            powerModeManager: powerModeManager,
                            draggedConfigID: $draggedConfigID,
                            targetedConfigID: $targetedConfigID
                        )
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .onDrop(
            of: [UTType.text],
            delegate: PowerModeReorderResetDropDelegate(
                draggedConfigID: $draggedConfigID,
                targetedConfigID: $targetedConfigID
            )
        )
    }
}

private struct PowerModeReorderRow: View {
    let config: PowerModeConfig
    let isDragged: Bool
    let isTargeted: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: 34, height: 34)

                Text(config.emoji)
                    .font(.system(size: 18))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(config.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    PowerModeReorderMeta(icon: "app.fill", value: countText(config.appConfigs?.count ?? 0, singular: "App", plural: "Apps"))
                    PowerModeReorderMeta(icon: "globe", value: countText(config.urlConfigs?.count ?? 0, singular: "Website", plural: "Websites"))
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 6) {
                if config.isDefault {
                    PowerModeReorderBadge(title: "Default", isProminent: true)
                }

                if !config.isEnabled {
                    PowerModeReorderBadge(title: "Disabled")
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(rowBorder, lineWidth: isTargeted ? 1.5 : 1)
        }
        .shadow(color: Color.black.opacity(isDragged ? 0.10 : 0.03), radius: isDragged ? 10 : 2, x: 0, y: isDragged ? 5 : 1)
        .scaleEffect(isDragged ? 0.985 : 1)
        .opacity(isDragged ? 0.55 : 1)
        .animation(.smooth(duration: 0.16), value: isDragged)
        .animation(.smooth(duration: 0.16), value: isTargeted)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(config.name)
    }

    private var rowBackground: Color {
        if isTargeted {
            return Color(NSColor.controlAccentColor).opacity(0.10)
        }

        if isHovering {
            return Color.secondary.opacity(0.14)
        }

        return Color.secondary.opacity(0.1)
    }

    private var rowBorder: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.65)
        }

        return Color(NSColor.separatorColor).opacity(0.55)
    }

    private func countText(_ count: Int, singular: String, plural: String) -> String {
        if count == 0 {
            return "No \(plural)"
        }

        if count == 1 {
            return "1 \(singular)"
        }

        return "\(count) \(plural)"
    }
}

private struct PowerModeReorderMeta: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))

            Text(value)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }
}

private struct PowerModeReorderBadge: View {
    let title: String
    var isProminent = false

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isProminent ? Color.white : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(isProminent ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            }
            .overlay {
                if !isProminent {
                    Capsule()
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                }
            }
    }
}

private struct PowerModeReorderDragPreview: View {
    let config: PowerModeConfig

    var body: some View {
        HStack(spacing: 10) {
            Text(config.emoji)
                .font(.system(size: 18))

            Text(config.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        }
    }
}

private struct PowerModeReorderDropDelegate: DropDelegate {
    let item: PowerModeConfig
    let powerModeManager: PowerModeManager
    @Binding var draggedConfigID: UUID?
    @Binding var targetedConfigID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedConfigID,
              draggedConfigID != item.id,
              let fromIndex = powerModeManager.configurations.firstIndex(where: { $0.id == draggedConfigID }),
              let toIndex = powerModeManager.configurations.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        targetedConfigID = item.id

        withAnimation(.smooth(duration: 0.18)) {
            var updatedConfigurations = powerModeManager.configurations
            updatedConfigurations.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
            powerModeManager.replaceConfigurations(updatedConfigurations)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if targetedConfigID == item.id {
            targetedConfigID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedConfigID = nil
        targetedConfigID = nil
        return true
    }
}

private struct PowerModeReorderResetDropDelegate: DropDelegate {
    @Binding var draggedConfigID: UUID?
    @Binding var targetedConfigID: UUID?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedConfigID = nil
        targetedConfigID = nil
        return true
    }
}

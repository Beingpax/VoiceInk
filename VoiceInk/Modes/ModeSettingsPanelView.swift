import SwiftUI
import UniformTypeIdentifiers

struct ModeSettingsPanelView: View {
    @ObservedObject var modeManager: ModeManager
    let onDismiss: () -> Void

    @AppStorage("ModeTipDismissed")
    private var isTipDismissed = false


    private let contentInset: CGFloat = 20

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
                        .background(AppTheme.Surface.card)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(Divider().opacity(0.5), alignment: .bottom)

            HStack {
                Text("Reorder Modes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                + Text(" (drag to reorder)")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, contentInset)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ModeReorderList(modeManager: modeManager)
                .padding(.horizontal, contentInset)

            if !isTipDismissed {
                ModeSettingsQuickSwitchTip {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isTipDismissed = true
                    }
                }
                .padding(.horizontal, contentInset)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.16), value: isTipDismissed)
        .onExitCommand(perform: onDismiss)
    }

}

private struct ModeReorderList: View {
    @ObservedObject var modeManager: ModeManager

    @State private var draggedConfigID: UUID?
    @State private var targetedConfigID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(modeManager.configurations) { config in
                    ModeReorderRow(
                        config: config,
                        isDragged: draggedConfigID == config.id,
                        isTargeted: targetedConfigID == config.id
                    )
                    .onDrag {
                        draggedConfigID = config.id
                        return NSItemProvider(object: config.id.uuidString as NSString)
                    } preview: {
                        ModeReorderDragPreview(config: config)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: ModeReorderDropDelegate(
                            item: config,
                            modeManager: modeManager,
                            draggedConfigID: $draggedConfigID,
                            targetedConfigID: $targetedConfigID
                        )
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: .infinity)
        .onDrop(
            of: [UTType.text],
            delegate: ModeReorderResetDropDelegate(
                draggedConfigID: $draggedConfigID,
                targetedConfigID: $targetedConfigID
            )
        )
    }
}

private struct ModeReorderRow: View {
    let config: ModeConfig
    let isDragged: Bool
    let isTargeted: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ModeIconView(icon: config.icon, size: config.icon.kind == .emoji ? 18 : 14)
            }
            .frame(width: 34, height: 34)
            .background(
                AppCardBackground(isSelected: false, cornerRadius: 17)
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(config.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    ModeReorderMeta(icon: "app.fill", value: countText(config.allAppConfigs.count, singular: "App", plural: "Apps"))
                    ModeReorderMeta(icon: "globe", value: countText(config.allURLConfigs.count, singular: "Website", plural: "Websites"))
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 6) {
                if config.isDefault {
                    DefaultModeIndicator()
                }

                if !config.isEnabled {
                    ModeReorderBadge(title: "Disabled", systemImage: "slash.circle.fill")
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
            return AppTheme.Selection.fill
        }

        if isHovering {
            return AppTheme.Surface.controlActive
        }

        return AppTheme.Surface.card
    }

    private var rowBorder: Color {
        if isTargeted {
            return AppTheme.Selection.border
        }

        return AppTheme.Border.control.opacity(0.55)
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

private struct ModeReorderMeta: View {
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

private struct ModeReorderBadge: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(AppTheme.Surface.card)
        }
        .overlay {
            Capsule()
                .stroke(AppTheme.Border.control, lineWidth: 0.5)
        }
    }
}

private struct ModeReorderDragPreview: View {
    let config: ModeConfig

    var body: some View {
        HStack(spacing: 10) {
            ModeIconView(icon: config.icon, size: config.icon.kind == .emoji ? 18 : 14)

            Text(config.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.Border.control, lineWidth: 0.5)
        }
    }
}

private struct ModeReorderDropDelegate: DropDelegate {
    let item: ModeConfig
    let modeManager: ModeManager
    @Binding var draggedConfigID: UUID?
    @Binding var targetedConfigID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedConfigID,
              draggedConfigID != item.id,
              let fromIndex = modeManager.configurations.firstIndex(where: { $0.id == draggedConfigID }),
              let toIndex = modeManager.configurations.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        targetedConfigID = item.id

        withAnimation(.smooth(duration: 0.18)) {
            var updatedConfigurations = modeManager.configurations
            updatedConfigurations.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
            modeManager.replaceConfigurations(updatedConfigurations)
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

private struct ModeReorderResetDropDelegate: DropDelegate {
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

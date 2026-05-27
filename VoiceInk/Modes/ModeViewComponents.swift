import SwiftUI

struct VoiceInkButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDisabled ? Color.accentColor.opacity(0.5) : Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct ModeEmptyStateView: View {
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Modes")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add customized modes for different contexts")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VoiceInkButton(
                title: "Add New Mode",
                action: action
            )
            .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ModeConfigurationsGrid: View {
    @ObservedObject var modeManager: ModeManager
    let onEditConfig: (ModeConfig) -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach($modeManager.configurations) { $config in
                ConfigurationRow(
                    config: $config,
                    isEditing: false,
                    modeManager: modeManager,
                    onEditConfig: onEditConfig
                )
            }
        }
    }
}

/// Small, consistent icon-only add button used across Mode configuration rows.
struct AddIconButton: View {
    let helpText: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .disabled(isDisabled)
    }
}

struct DefaultModeIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            Text("Default")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 7)
        .padding(.trailing, 9)
        .frame(height: 24)
        .background {
            Capsule()
                .fill(Color.secondary.opacity(0.1))
        }
        .overlay {
            Capsule()
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
        }
        .contentShape(Capsule())
        .help("Default mode is used when no app or website matches")
    }
}

struct ConfigurationRow: View {
    @Binding var config: ModeConfig
    let isEditing: Bool
    let modeManager: ModeManager
    let onEditConfig: (ModeConfig) -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @State private var isHovering = false
    
    private let maxAppIconsToShow = 5
    
    private var selectedPrompt: CustomPrompt? {
        guard let promptId = config.selectedPrompt,
              let uuid = UUID(uuidString: promptId) else { return nil }
        return enhancementService.allPrompts.first { $0.id == uuid }
    }
    
    private var selectedModel: String? {
        if let modelName = config.selectedTranscriptionModelName,
           let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == modelName }) {
            return model.displayName
        }
        return "Default"
    }
    
    private var selectedLanguage: String? {
        if let langCode = config.selectedLanguage {
            if langCode == "auto" { return "Auto" }
            if langCode == "en" { return "English" }
            
            if let modelName = config.selectedTranscriptionModelName,
               let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == modelName }),
               let langName = TranscriptionLanguageSupport.languages(for: model)[langCode] {
                return langName
            }
            return langCode.uppercased()
        }
        return "Default"
    }

    private var hasVisibleMetadata: Bool {
        (selectedModel.map { $0 != "Default" } ?? false) ||
        (selectedLanguage.map { $0 != "Default" } ?? false) ||
        config.isAIEnhancementEnabled ||
        config.autoSendKey.isEnabled
    }
    
    private var appCount: Int { return config.appConfigs?.count ?? 0 }
    private var websiteCount: Int { return config.urlConfigs?.count ?? 0 }
    
    private var websiteText: String {
        if websiteCount == 0 { return "" }
        return websiteCount == 1 ? "1 Website" : "\(websiteCount) Websites"
    }
    
    private var appText: String {
        if appCount == 0 { return "" }
        return appCount == 1 ? "1 App" : "\(appCount) Apps"
    }
    
    private var extraAppsCount: Int {
        return max(0, appCount - maxAppIconsToShow)
    }
    
    private var visibleAppConfigs: [AppConfig] {
        return Array(config.appConfigs?.prefix(maxAppIconsToShow) ?? [])
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: 40, height: 40)
                    
                    ModeIconView(icon: config.icon, size: config.icon.kind == .emoji ? 20 : 16)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(config.name)
                        .font(.system(size: 15, weight: .semibold))
                    
                    HStack(spacing: 12) {
                        if appCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 10))
                                Text(appText)
                                    .font(.caption2)
                            }
                        }

                        if websiteCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.system(size: 10))
                                Text(websiteText)
                                    .font(.caption2)
                            }
                        }
                    }
                    .padding(.top, 2)
                    .foregroundColor(.secondary)
                }
                
                Spacer()

                if config.isDefault {
                    DefaultModeIndicator()
                } else {
                    Toggle("", isOn: Binding(
                        get: { config.isEnabled },
                        set: { newValue in
                            if newValue {
                                modeManager.enableConfiguration(with: config.id)
                            } else {
                                modeManager.disableConfiguration(with: config.id)
                            }
                        }
                    ))
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .labelsHidden()
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            
            if hasVisibleMetadata {
                Divider()
                
                HStack(spacing: 8) {
                    if let model = selectedModel, model != "Default" {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.system(size: 10))
                            Text(model)
                                .font(.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule()
                            .fill(Color(NSColor.controlBackgroundColor)))
                        .overlay(
                            Capsule()
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                    }
                    
                    if let language = selectedLanguage, language != "Default" {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                            Text(language)
                                .font(.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule()
                            .fill(Color(NSColor.controlBackgroundColor)))
                        .overlay(
                            Capsule()
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                    }
                    
                    if config.isAIEnhancementEnabled,
                       config.selectedAIProvider != AIProvider.localCLI.rawValue,
                       let modelName = config.selectedAIModel,
                       !modelName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10))
                            Text(modelName.count > 20 ? String(modelName.prefix(18)) + "..." : modelName)
                                .font(.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule()
                            .fill(Color(NSColor.controlBackgroundColor)))
                        .overlay(
                            Capsule()
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                    }
                    
                    if config.autoSendKey.isEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 10))
                            Text(config.autoSendKey.displayName)
                                .font(.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule()
                            .fill(Color(NSColor.controlBackgroundColor)))
                        .overlay(
                            Capsule()
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                    }
                    if config.isAIEnhancementEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text(selectedPrompt?.title ?? "AI")
                                .font(.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule()
                            .fill(Color(NSColor.controlBackgroundColor)))
                        .overlay(
                            Capsule()
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                    }

                    Spacer()
                }
                
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .background(Color.secondary.opacity(0.1))
            }
    }
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .background(CardBackground(isSelected: isEditing))
    .opacity(config.isEnabled ? 1.0 : 0.70)

    .onHover { hovering in
        withAnimation(.easeInOut(duration: 0.15)) {
            isHovering = hovering
        }
    }
    .onTapGesture(count: 2) {
        onEditConfig(config)
    }
    .contextMenu {
        Button(action: {
            onEditConfig(config)
        }) {
            Label("Edit", systemImage: "pencil")
        }
        if modeManager.configurations.count > 1 {
            Button(role: .destructive, action: {
                let alert = NSAlert()
                alert.messageText = "Delete Mode?"
                alert.informativeText = "Are you sure you want to delete the '\(config.name)' mode? This action cannot be undone."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Delete")
                alert.addButton(withTitle: "Cancel")
                alert.buttons[0].hasDestructiveAction = true

                if alert.runModal() == .alertFirstButtonReturn {
                    modeManager.removeConfiguration(with: config.id)
                }
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    }
    
    private var isSelected: Bool {
        return isEditing
    }
}

struct ModeAppIcon: View {
    let bundleId: String
    
    var body: some View {
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appUrl.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
        }
    }
}

struct AppGridItem: View {
    let app: (url: URL, name: String, bundleId: String, icon: NSImage)
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
                    .shadow(color: Color(NSColor.shadowColor).opacity(0.1), radius: 2, x: 0, y: 1)
                Text(app.name)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28)
            }
            .frame(width: 80, height: 80)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

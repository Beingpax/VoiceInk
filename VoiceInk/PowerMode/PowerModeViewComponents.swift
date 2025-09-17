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

struct PowerModeEmptyStateView: View {
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Power Modes")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add customized power modes for different contexts")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VoiceInkButton(
                title: "Add New Power Mode",
                action: action
            )
            .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PowerModeConfigurationsGrid: View {
    @ObservedObject var powerModeManager: PowerModeManager
    let onEditConfig: (PowerModeConfig) -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(powerModeManager.configurations.indices, id: \.self) { index in
                let config = powerModeManager.configurations[index]
                ConfigurationRow(
                    config: $powerModeManager.configurations[index],
                    isEditing: false,
                    powerModeManager: powerModeManager,
                    onEditConfig: onEditConfig,
                    shortcutIndex: index
                )
                .contextMenu {
                    Button(action: {
                        onEditConfig(config)
                    }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: {
                        powerModeManager.removeConfiguration(with: config.id)
                    }) {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

struct ConfigurationRow: View {
    @Binding var config: PowerModeConfig
    let isEditing: Bool
    let powerModeManager: PowerModeManager
    let onEditConfig: (PowerModeConfig) -> Void
    let shortcutIndex: Int
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var whisperState: WhisperState
    @State private var isHovering = false
    
    private let maxAppIconsToShow = 5
    
    private var selectedPrompt: CustomPrompt? {
        guard let promptId = config.selectedPrompt,
              let uuid = UUID(uuidString: promptId) else { return nil }
        return enhancementService.allPrompts.first { $0.id == uuid }
    }
    
    private var selectedModel: String? {
        if let modelName = config.selectedTranscriptionModelName,
           let model = whisperState.allAvailableModels.first(where: { $0.name == modelName }) {
            return model.displayName
        }
        return "Default"
    }
    
    private var selectedLanguage: String? {
        if let langCode = config.selectedLanguage {
            if langCode == "auto" { return "Auto" }
            if langCode == "en" { return "English" }
            
            if let modelName = config.selectedTranscriptionModelName,
               let model = whisperState.allAvailableModels.first(where: { $0.name == modelName }),
               let langName = model.supportedLanguages[langCode] {
                return langName
            }
            return langCode.uppercased()
        }
        return "Default"
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
                    
                    Text(config.emoji)
                        .font(.system(size: 20))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(config.name)
                            .font(.system(size: 15, weight: .semibold))
                        
                        if config.isDefault {
                            Text("Default")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor))
                                .foregroundColor(.white)
                        }
                    }
                    
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
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if shortcutIndex < 10 {
                    Text("⌘\(shortcutIndex < 9 ? String(shortcutIndex + 1) : "0")")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.trailing, 8)
                }
                
                Toggle("", isOn: $config.isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .labelsHidden()
                    .onChange(of: config.isEnabled) { _, _ in
                        powerModeManager.updateConfiguration(config)
                    }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            
            if selectedModel != nil || selectedLanguage != nil || config.isAIEnhancementEnabled || config.isAutoSendEnabled {
                Divider()
                    .padding(.horizontal, 16)
                
                HStack(spacing: 8) {
                    if let model = selectedModel, model != "Default" {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.system(size: 10))
                            Text(model)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule()
                            .fill(Color(NSColor.controlBackgroundColor)))
                        .overlay(
                            Capsule()
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                    }
                    
                    if config.isAIEnhancementEnabled, let modelName = config.selectedAIModel, !modelName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10))
                            Text(modelName.count > 20 ? String(modelName.prefix(18)) + "..." : modelName)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule()
                            .fill(Color(NSColor.controlBackgroundColor)))
                        .overlay(
                            Capsule()
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                    }
                    
                    if config.isAutoSendEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 10))
                            Text("Auto Send")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule()
                            .fill(Color(NSColor.controlBackgroundColor)))
                        .overlay(
                            Capsule()
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                    }
                    if config.isAIEnhancementEnabled {
                        if config.useScreenCapture {
                            HStack(spacing: 4) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 10))
                                Text("Context Awareness")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule()
                                .fill(Color(NSColor.controlBackgroundColor)))
                            .overlay(
                                Capsule()
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text(selectedPrompt?.title ?? "AI")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule()
                            .fill(Color.accentColor.opacity(0.1)))
                        .foregroundColor(.accentColor)
                    }

                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }
    }
    .background(CardBackground(isSelected: isEditing))
    .opacity(config.isEnabled ? 1.0 : 0.5)

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
        Button(role: .destructive, action: {
            powerModeManager.removeConfiguration(with: config.id)
        }) {
            Label("Remove", systemImage: "trash")
        }
    }
    }
    
    private var isSelected: Bool {
        return isEditing
    }
}

struct PowerModeAppIcon: View {
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

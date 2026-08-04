import SwiftUI

struct ConfigurationRow: View {
    private struct TranscriptionModelMetadata {
        let label: String
        let isWarning: Bool
    }

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
            let uuid = UUID(uuidString: promptId)
        else { return nil }
        return enhancementService.allPrompts.first { $0.id == uuid }
    }

    private var transcriptionModelMetadata: TranscriptionModelMetadata {
        switch ModeRuntimeResolver.transcriptionModelResolution(
            mode: config,
            transcriptionModelManager: transcriptionModelManager
        ) {
        case .available(_, let model):
            return TranscriptionModelMetadata(
                label: model.displayName,
                isWarning: false
            )
        case .noMode, .noSelection, .modelNotFound, .unavailable:
            return TranscriptionModelMetadata(
                label: String(localized: "Unavailable"),
                isWarning: true
            )
        }
    }

    private var selectedLanguage: String? {
        if let langCode = config.selectedLanguage {
            if langCode == "auto" { return String(localized: "Auto") }
            if langCode == "en" { return String(localized: "English") }

            if let modelName = config.selectedTranscriptionModelName,
                let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == modelName }),
                let langName = TranscriptionLanguageSupport.languages(
                    for: model, realtimeEnabled: config.isRealtimeTranscriptionEnabled)[langCode]
            {
                return langName
            }
            return langCode.uppercased()
        }
        return "Default"
    }

    private var appCount: Int { return config.allAppConfigs.count }
    private var websiteCount: Int { return config.allURLConfigs.count }

    private var websiteText: String {
        if websiteCount == 0 { return "" }
        return String(localized: "\(websiteCount) Websites")
    }

    private var appText: String {
        if appCount == 0 { return "" }
        return String(localized: "\(appCount) Apps")
    }

    private var extraAppsCount: Int {
        return max(0, appCount - maxAppIconsToShow)
    }

    private var visibleAppConfigs: [AppConfig] {
        return Array(config.allAppConfigs.prefix(maxAppIconsToShow))
    }

    private var editModeButton: some View {
        Button {
            onEditConfig(config)
        } label: {
            Text("Edit")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(AppTheme.Surface.control)
                )
                .overlay(
                    Capsule()
                        .stroke(AppTheme.Border.control, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("Edit mode")
        .accessibilityLabel("Edit mode")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        ModeIconView(icon: config.icon, size: config.icon.kind == .emoji ? 20 : 16)
                    }
                    .frame(width: 40, height: 40)
                    .background(
                        AppCardBackground(isSelected: false, cornerRadius: AppTheme.Radius.pill)
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(config.name)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)

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
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onEditConfig(config)
                }

                if !config.isDefault {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { config.isEnabled },
                            set: { newValue in
                                if newValue {
                                    modeManager.enableConfiguration(with: config.id)
                                } else {
                                    modeManager.disableConfiguration(with: config.id)
                                }
                            }
                        )
                    )
                    .toggleStyle(SwitchToggleStyle(tint: AppTheme.Accent.primary))
                    .labelsHidden()
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppMaterialCardBackground.fill)

            Divider()

            HStack(spacing: 8) {
                let modelMetadata = transcriptionModelMetadata
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                    Text(modelMetadata.label)
                        .font(.caption)
                }
                .foregroundStyle(modelMetadata.isWarning ? Color.white : Color.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(
                            modelMetadata.isWarning
                                ? Color.red.opacity(0.80) : AppTheme.Surface.control)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            modelMetadata.isWarning
                                ? Color.red.opacity(0.80) : AppTheme.Border.control,
                            lineWidth: 0.5
                        )
                )

                if let language = selectedLanguage, language != "Default" {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                        Text(language)
                            .font(.caption)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppTheme.Surface.control)
                    )
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.Border.control, lineWidth: 0.5)
                    )
                }

                if config.isAIEnhancementEnabled,
                    config.selectedAIProvider != AIProvider.localCLI.rawValue,
                    let modelName = config.selectedAIModel,
                    !modelName.isEmpty
                {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                        Text(modelName.count > 20 ? String(modelName.prefix(18)) + "..." : modelName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppTheme.Surface.control)
                    )
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.Border.control, lineWidth: 0.5)
                    )
                }

                if config.outputMode != .paste {
                    HStack(spacing: 4) {
                        Image(systemName: config.outputMode.iconName)
                            .font(.system(size: 10))
                        Text(config.outputMode.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppTheme.Surface.control)
                    )
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.Border.control, lineWidth: 0.5)
                    )
                }

                if config.outputMode == .paste && config.autoSendKey.isEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 10))
                        Text(config.autoSendKey.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppTheme.Surface.control)
                    )
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.Border.control, lineWidth: 0.5)
                    )
                }
                if config.isAIEnhancementEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text(
                            config.selectedAIProvider == AIProvider.voiceInkRefine.rawValue
                                ? VoiceInkRefineService.providerName
                                : selectedPrompt?.title ?? "AI"
                        )
                            .font(.caption)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppTheme.Surface.control)
                    )
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.Border.control, lineWidth: 0.5)
                    )
                }

                Spacer()

                if isHovering {
                    editModeButton
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onEditConfig(config)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .background(AppTheme.Surface.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    AppMaterialCardBackground.border(for: isEditing),
                    lineWidth: AppMaterialCardBackground.lineWidth(for: isEditing)
                )
        }
        .opacity(config.isEnabled ? 1.0 : 0.70)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

}

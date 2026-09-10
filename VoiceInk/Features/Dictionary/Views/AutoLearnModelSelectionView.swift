import SwiftUI

struct AutoLearnSectionHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Auto Learn")
            InfoTip(
                LocalizedStringKey(
                    "Automatically learns corrections you make after dictation. Only correction pairs are sent to your selected AI provider; recordings and full text fields are never sent."
                ),
                learnMoreURL: "https://tryvoiceink.com/docs/auto-learn-dictionary"
            )
            .accessibilityLabel("Learn about Dictionary Auto Learn")
        }
    }
}

struct AutoLearnModelSelectionView: View {
    var retriesOnChange = true

    @EnvironmentObject private var aiService: AIService
    @AppStorage(AutoLearnSettings.isEnabledKey) private var isAutoLearnDictionaryEnabled = true
    @AppStorage(AutoLearnSettings.providerKey) private var autoLearnProvider = ""
    @AppStorage(AutoLearnSettings.modelKey) private var autoLearnModel = ""
    @AppStorage(AutoLearnSettings.hasFailureKey) private var hasAutoLearnFailure = false

    private var providerOptions: [AIProvider] {
        var providers = aiService.connectedProviders
        if let selectedProvider, selectedProvider.supportsEnhancement,
            !providers.contains(selectedProvider)
        {
            providers.insert(selectedProvider, at: 0)
        }
        return providers
    }

    private var selectedProvider: AIProvider? {
        AIProvider(rawValue: autoLearnProvider)
    }

    var body: some View {
        Group {
            if providerOptions.isEmpty {
                LabeledContent("Provider") {
                    Text("No AI providers connected")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            } else {
                Picker("Provider", selection: providerBinding) {
                    ForEach(providerOptions, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }

                if let selectedProvider {
                    modelPicker(for: selectedProvider)

                    if !aiService.connectedProviders.contains(selectedProvider) {
                        Text("The selected provider is currently unavailable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear(perform: prepareSelectionIfNeeded)
        .onChange(of: autoLearnModel) { _, _ in
            retryAfterConfigurationChange()
        }
    }

    private var providerBinding: Binding<AIProvider> {
        Binding(
            get: {
                selectedProvider ?? providerOptions.first ?? aiService.selectedProvider
            },
            set: { provider in
                autoLearnProvider = provider.rawValue
                autoLearnModel = defaultModel(for: provider)
                refreshModelsIfNeeded(for: provider)
                retryAfterConfigurationChange()
            }
        )
    }

    @ViewBuilder
    private func modelPicker(for provider: AIProvider) -> some View {
        if provider == .localCLI {
            LabeledContent("Model") {
                Text("Configured command")
                    .foregroundStyle(.secondary)
            }
        } else if provider == .voiceInkRefine {
            LabeledContent("Model") {
                Text(VoiceInkRefineService.modelName)
                    .foregroundStyle(.secondary)
            }
        } else {
            let models = modelOptions(for: provider)
            if models.isEmpty {
                LabeledContent("Model") {
                    Text("No models available")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            } else {
                Picker("Model", selection: $autoLearnModel) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }
        }
    }

    private func modelOptions(for provider: AIProvider) -> [String] {
        var models = aiService.availableModels(for: provider)
        if !autoLearnModel.isEmpty, !models.contains(autoLearnModel) {
            models.insert(autoLearnModel, at: 0)
        }
        return models
    }

    private func defaultModel(for provider: AIProvider) -> String {
        if provider == .localCLI { return "" }
        if provider == .voiceInkRefine { return VoiceInkRefineService.modelName }
        let models = aiService.availableModels(for: provider)
        let selectedModel = aiService.selectedModel(for: provider)
        return models.contains(selectedModel) ? selectedModel : models.first ?? selectedModel
    }

    private func prepareSelectionIfNeeded() {
        guard let provider = selectedProvider, provider.supportsEnhancement else {
            guard let fallback = providerOptions.first else { return }
            autoLearnProvider = fallback.rawValue
            autoLearnModel = defaultModel(for: fallback)
            refreshModelsIfNeeded(for: fallback)
            return
        }

        if autoLearnModel.isEmpty, provider != .localCLI {
            autoLearnModel = defaultModel(for: provider)
        }
        refreshModelsIfNeeded(for: provider)
    }

    private func refreshModelsIfNeeded(for provider: AIProvider) {
        switch provider {
        case .ollama:
            Task {
                let models = await aiService.refreshOllamaConnectionAndModels().map(\.name)
                updateModelSelection(afterLoading: models, for: provider)
            }
        case .openRouter:
            Task {
                await aiService.fetchOpenRouterModels()
                updateModelSelection(afterLoading: aiService.availableModels(for: provider), for: provider)
            }
        default:
            break
        }
    }

    private func updateModelSelection(afterLoading models: [String], for provider: AIProvider) {
        guard selectedProvider == provider,
            !models.isEmpty,
            !models.contains(autoLearnModel)
        else { return }
        autoLearnModel = models[0]
    }

    private func retryAfterConfigurationChange() {
        guard retriesOnChange, isAutoLearnDictionaryEnabled, hasAutoLearnFailure else { return }
        Task {
            await AutoLearnService.shared.retryPendingReviews()
        }
    }
}

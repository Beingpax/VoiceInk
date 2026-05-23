import SwiftUI
import AppKit

struct CustomProviderManagementView: View {
    @ObservedObject var customModelManager: CustomCloudModelManager
    @ObservedObject var customAIProviderManager: CustomAIProviderManager
    @Binding var customModelToEdit: CustomCloudModel?

    let onTranscriptionModelsChanged: () -> Void
    let onDeleteTranscriptionModel: (CustomCloudModel) -> Void

    @State private var customAIProviderToEdit: CustomAIProviderConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                ProviderSectionHeader(
                    title: "Custom Transcription",
                    subtitle: "OpenAI-compatible audio transcription endpoints."
                )

                if customModelManager.customModels.isEmpty {
                    emptyState("No custom transcription models added")
                } else {
                    ForEach(customModelManager.customModels) { model in
                        CustomModelCardView(
                            model: model,
                            deleteAction: {
                                onDeleteTranscriptionModel(model)
                            },
                            editAction: { model in
                                customModelToEdit = model
                            }
                        )
                    }
                }

                AddCustomModelCardView(
                    customModelManager: customModelManager,
                    onModelAdded: {
                        onTranscriptionModelsChanged()
                        customModelToEdit = nil
                    },
                    editingModel: customModelToEdit
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                ProviderSectionHeader(
                    title: "Custom Enhancement",
                    subtitle: "OpenAI-compatible chat completion providers for enhancement."
                )

                if customAIProviderManager.providers.isEmpty {
                    emptyState("No custom enhancement providers added")
                } else {
                    ForEach(customAIProviderManager.providers) { provider in
                        CustomAIProviderCard(
                            provider: provider,
                            isActive: customAIProviderManager.activeProviderID == provider.id,
                            onActivate: {
                                customAIProviderManager.activateProvider(provider.id)
                            },
                            onEdit: {
                                customAIProviderToEdit = provider
                            },
                            onDelete: {
                                customAIProviderManager.deleteProvider(provider)
                            }
                        )
                    }
                }

                CustomAIProviderEditorView(
                    manager: customAIProviderManager,
                    editingProvider: customAIProviderToEdit,
                    onFinishEditing: {
                        customAIProviderToEdit = nil
                    }
                )
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(ProviderSurface(cornerRadius: 10))
    }
}

private struct CustomAIProviderCard: View {
    let provider: CustomAIProviderConfig
    let isActive: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(provider.name)
                        .font(.system(size: 13, weight: .semibold))

                    if isActive {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                Text("\(provider.trimmedModels.count) models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isActive {
                Button("Use") {
                    onActivate()
                }
                .controlSize(.small)
            }

            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
        }
        .padding(14)
        .background(ProviderSurface(isActive: isActive, cornerRadius: 10))
    }
}

private struct CustomAIProviderEditorView: View {
    @ObservedObject var manager: CustomAIProviderManager
    let editingProvider: CustomAIProviderConfig?
    let onFinishEditing: () -> Void

    @State private var isExpanded = false
    @State private var providerName = ""
    @State private var baseURL = ""
    @State private var modelsText = ""
    @State private var selectedModel = ""
    @State private var apiKey = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?

    private var isEditing: Bool {
        editingProvider != nil
    }

    private var models: [String] {
        modelsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isExpanded {
                Button {
                    openEditor(with: editingProvider)
                } label: {
                    Label("Add Enhancement Provider", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(isEditing ? "Edit Enhancement Provider" : "Add Enhancement Provider")
                            .font(.system(size: 14, weight: .semibold))

                        Spacer()

                        Button {
                            closeEditor()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                    }

                    FormField(title: "Provider Name", text: $providerName, placeholder: "My Provider")
                    FormField(title: "Base URL", text: $baseURL, placeholder: "https://api.example.com/v1/chat/completions")

                    ProviderConfigurationGroup(title: "Models") {
                        TextEditor(text: $modelsText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 72)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 1)
                            )
                    }

                    FormField(title: "Verification Model", text: $selectedModel, placeholder: "gpt-4.1")
                    FormField(title: "API Key", text: $apiKey, placeholder: isEditing ? "Leave blank to keep saved key" : "your-api-key", isSecure: true)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Button("Cancel") {
                            closeEditor()
                        }

                        Spacer()

                        Button {
                            verifyAndSave()
                        } label: {
                            HStack(spacing: 6) {
                                if isVerifying {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isVerifying ? "Verifying" : isEditing ? "Save Changes" : "Verify & Add")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isVerifying)
                    }
                }
                .padding(16)
                .background(ProviderSurface(cornerRadius: 10))
            }
        }
        .onChange(of: editingProvider) { _, newValue in
            guard let newValue else { return }
            openEditor(with: newValue)
        }
    }

    private func openEditor(with provider: CustomAIProviderConfig?) {
        if let provider {
            providerName = provider.name
            baseURL = provider.baseURL
            modelsText = provider.trimmedModels.joined(separator: "\n")
            selectedModel = provider.selectedModel
            apiKey = ""
        } else {
            providerName = ""
            baseURL = ""
            modelsText = ""
            selectedModel = ""
            apiKey = ""
        }

        errorMessage = nil
        withAnimation(.smooth(duration: 0.22)) {
            isExpanded = true
        }
    }

    private func closeEditor() {
        withAnimation(.smooth(duration: 0.22)) {
            isExpanded = false
        }
        clearFields()
        onFinishEditing()
    }

    private func clearFields() {
        providerName = ""
        baseURL = ""
        modelsText = ""
        selectedModel = ""
        apiKey = ""
        errorMessage = nil
        isVerifying = false
    }

    private func verifyAndSave() {
        let trimmedName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalModels = Array(Set(models + [trimmedSelectedModel])).filter { !$0.isEmpty }.sorted()
        let finalSelectedModel = trimmedSelectedModel.isEmpty ? finalModels.first ?? "" : trimmedSelectedModel

        let validationErrors = manager.validateProvider(
            name: trimmedName,
            baseURL: trimmedURL,
            models: finalModels,
            excluding: editingProvider?.id
        )

        guard validationErrors.isEmpty else {
            errorMessage = validationErrors.joined(separator: "\n")
            return
        }

        let keyToVerify = apiKey.isEmpty
            ? editingProvider.map { manager.apiKey(for: $0) } ?? ""
            : apiKey

        guard !keyToVerify.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "API key cannot be empty"
            return
        }

        isVerifying = true
        errorMessage = nil

        Task {
            let result = await manager.verifyProvider(
                baseURL: trimmedURL,
                apiKey: keyToVerify,
                model: finalSelectedModel
            )

            await MainActor.run {
                isVerifying = false

                guard result.isValid else {
                    errorMessage = result.errorMessage ?? "Verification failed"
                    return
                }

                let provider = CustomAIProviderConfig(
                    id: editingProvider?.id ?? UUID(),
                    name: trimmedName,
                    baseURL: trimmedURL,
                    models: finalModels,
                    selectedModel: finalSelectedModel
                )

                let didSave: Bool
                if isEditing {
                    didSave = manager.updateProvider(provider, apiKey: apiKey.isEmpty ? nil : keyToVerify)
                } else {
                    didSave = manager.addProvider(provider, apiKey: keyToVerify)
                }

                if didSave {
                    closeEditor()
                } else {
                    errorMessage = "Failed to save the API key"
                }
            }
        }
    }
}

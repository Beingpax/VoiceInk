import SwiftUI

struct APIKeyManagementView: View {
    @EnvironmentObject private var aiService: AIService

    var onAddConfig: (() -> Void)?
    var onEditConfig: ((AIProviderConfiguration) -> Void)?

    var body: some View {
        Section {
            if aiService.providerConfigurations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No AI providers configured")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Add a provider configuration to enable AI enhancement with different models and services.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)

                    Button {
                        onAddConfig?()
                    } label: {
                        Label("Add Provider", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(aiService.providerConfigurations) { config in
                    ProviderConfigRow(config: config, apiKeyRevision: aiService.apiKeyRevision)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onEditConfig?(config)
                        }
                        .contextMenu {
                            Button {
                                onEditConfig?(config)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            if !config.isDefault {
                                Button {
                                    aiService.setDefaultProviderConfiguration(config)
                                } label: {
                                    Label("Set as Default", systemImage: "star")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    aiService.deleteProviderConfiguration(config)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
            }
        } header: {
            HStack {
                Text("AI Provider Integration")
                Spacer()
                Button {
                    onAddConfig?()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add new provider configuration")
            }
        }
    }
}

private struct ProviderConfigRow: View {
    let config: AIProviderConfiguration
    let apiKeyRevision: Int  // Forces re-render when API keys change

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(config.hasAPIKey ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if config.isDefault {
                        Text("Default")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                Text("\(config.provider.rawValue) - \(config.effectiveModel)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.vertical, 4)
    }
}

func getAPIKeyURL(for provider: AIProvider) -> URL? {
    switch provider {
    case .groq: return URL(string: "https://console.groq.com/keys")
    case .openAI: return URL(string: "https://platform.openai.com/api-keys")
    case .gemini: return URL(string: "https://makersuite.google.com/app/apikey")
    case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
    case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
    case .elevenLabs: return URL(string: "https://elevenlabs.io/speech-synthesis")
    case .deepgram: return URL(string: "https://console.deepgram.com/api-keys")
    case .soniox: return URL(string: "https://console.soniox.com/")
    case .openRouter: return URL(string: "https://openrouter.ai/keys")
    case .cerebras: return URL(string: "https://cloud.cerebras.ai/")
    default: return nil
    }
}

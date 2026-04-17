import SwiftUI
import LLMkit

/// Multi-API-key configuration view used inside `CloudModelCardView` for
/// providers that opt in to key rotation (currently ElevenLabs).
///
/// Lets the user add/remove/label multiple keys, toggle them on/off, see which
/// one is active, manually rotate, and see last-failure state at a glance.
struct MultiAPIKeyConfigurationView: View {
    let providerKey: String
    let providerDisplayName: String
    /// Called when the set of keys changes so the parent card can refresh its
    /// "Configured" badge and trigger model list refreshes.
    var onKeysChanged: () -> Void = {}

    @State private var keys: [APIKeyEntry] = []
    @State private var activeKeyId: UUID? = nil
    @State private var newKeyLabel: String = ""
    @State private var newKeyValue: String = ""
    @State private var isVerifying: Bool = false
    @State private var verificationError: String? = nil
    @State private var showGlobalError: Bool = false
    @State private var globalErrorMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if keys.isEmpty {
                Text("No keys configured. Add your first \(providerDisplayName) API key below.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(keys) { key in
                        keyRow(for: key)
                    }
                }
            }

            Divider().padding(.vertical, 4)

            addKeySection

            if let verificationError = verificationError {
                Text(verificationError)
                    .font(.caption)
                    .foregroundColor(Color(.systemRed))
            }

            rotationFooter
        }
        .onAppear(perform: reload)
        .alert("Error", isPresented: $showGlobalError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(globalErrorMessage)
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Text("API Keys")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))
            Spacer()
            if keys.count > 1 {
                Button(action: rotateManually) {
                    Label("Rotate Now", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Switch to the next enabled key")
            }
        }
    }

    private func keyRow(for key: APIKeyEntry) -> some View {
        let isActive = key.id == activeKeyId
        return HStack(spacing: 10) {
            // Active indicator
            Circle()
                .fill(isActive && !key.disabled ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 8, height: 8)
                .help(isActive ? "Active key" : "Inactive key")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TextField(
                        "Label",
                        text: Binding(
                            get: { key.label },
                            set: { newValue in
                                APIKeyManager.shared.updateAPIKey(
                                    id: key.id,
                                    label: newValue,
                                    forProvider: providerKey
                                )
                                reload()
                            }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))

                    if isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            .foregroundColor(Color.accentColor)
                    }
                    if key.disabled {
                        Text("Disabled")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.2)))
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Text(maskedKey(key.key))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let reason = key.lastFailureReason {
                        Text("⚠︎ \(reason)")
                            .font(.system(size: 10))
                            .foregroundColor(Color(.systemOrange))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(reason + (key.lastFailureAt.map { " (\(Self.relativeDateFormatter.localizedString(for: $0, relativeTo: Date())))" } ?? ""))
                    }
                }
            }

            Spacer()

            // Make-active button
            if !isActive && !key.disabled {
                Button("Use") {
                    APIKeyManager.shared.setActiveKey(id: key.id, forProvider: providerKey)
                    reload()
                    onKeysChanged()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Set this key as the active key")
            }

            // Enable/disable toggle
            Toggle(
                "",
                isOn: Binding(
                    get: { !key.disabled },
                    set: { newValue in
                        APIKeyManager.shared.updateAPIKey(
                            id: key.id,
                            disabled: !newValue,
                            forProvider: providerKey
                        )
                        reload()
                        onKeysChanged()
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(key.disabled ? "Enable this key" : "Disable this key")

            // Remove
            Button(action: { remove(key) }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundColor(Color(.systemRed))
            .help("Remove this key")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.06) : Color.clear)
        )
    }

    private var addKeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a new key")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                TextField("Label (e.g. \"Account 2\")", text: $newKeyLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)

                SecureField("\(providerDisplayName) API key", text: $newKeyValue)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isVerifying)

                Button(action: addKey) {
                    HStack(spacing: 4) {
                        if isVerifying {
                            ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(isVerifying ? "Verifying…" : "Verify & Add")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(.controlAccentColor)))
                }
                .buttonStyle(.plain)
                .disabled(newKeyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)
            }
        }
    }

    private var rotationFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Auto-rotation")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text("When \(providerDisplayName) returns an auth or quota error (401 / 403 / 429 / quota_exceeded / rate_limited), VoiceInk automatically tries the next enabled key. Network failures do not trigger rotation.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func reload() {
        keys = APIKeyManager.shared.getAPIKeys(forProvider: providerKey)
        activeKeyId = APIKeyManager.shared.activeAPIKey(forProvider: providerKey)?.id
    }

    private func addKey() {
        let trimmedKey = newKeyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = newKeyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        // Reject duplicate keys up front with a friendly message rather than
        // silently failing.
        if keys.contains(where: { $0.key == trimmedKey }) {
            verificationError = "This key is already configured."
            return
        }

        isVerifying = true
        verificationError = nil

        Task {
            let result: (isValid: Bool, errorMessage: String?)
            switch providerKey.lowercased() {
            case "elevenlabs":
                result = await ElevenLabsClient.verifyAPIKey(trimmedKey)
            default:
                result = (false, "Multi-key verification is not yet implemented for \(providerDisplayName).")
            }

            await MainActor.run {
                isVerifying = false
                if result.isValid {
                    guard APIKeyManager.shared.addAPIKey(
                        trimmedKey,
                        label: trimmedLabel,
                        forProvider: providerKey
                    ) != nil else {
                        verificationError = "Failed to store the key. Please try again."
                        return
                    }
                    newKeyLabel = ""
                    newKeyValue = ""
                    verificationError = nil
                    reload()
                    onKeysChanged()
                } else {
                    verificationError = result.errorMessage ?? "Verification failed"
                }
            }
        }
    }

    private func remove(_ key: APIKeyEntry) {
        APIKeyManager.shared.removeAPIKey(id: key.id, forProvider: providerKey)
        reload()
        onKeysChanged()
    }

    private func rotateManually() {
        guard keys.filter({ !$0.disabled }).count > 1 else {
            globalErrorMessage = "You need at least two enabled keys to rotate."
            showGlobalError = true
            return
        }
        _ = APIKeyManager.shared.rotateToNextKey(
            forProvider: providerKey,
            reason: "Manual rotation"
        )
        reload()
        onKeysChanged()
    }

    // MARK: - Formatting

    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "•", count: max(key.count, 4)) }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)••••••\(suffix)"
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

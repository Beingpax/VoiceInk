import SwiftUI

struct AutoLearnFailurePanel: View {
    let onClose: () -> Void

    @AppStorage(AutoLearnSettings.isEnabledKey) private var isAutoLearnEnabled = true
    @AppStorage(AutoLearnSettings.hasFailureKey) private var hasFailure = false
    @AppStorage(AutoLearnSettings.failureMessageKey) private var failureMessage = ""
    @State private var pendingCount: Int?

    var body: some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "Auto-Learn Failed", onClose: onClose)

            Form {
                Section {
                    AutoLearnModelSelectionView(retriesOnChange: false)
                } header: {
                    AutoLearnSectionHeader()
                }

                Section("What Happened") {
                    Label {
                        Text(errorDescription)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("How to Fix It") {
                    Text(retryGuidance)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: hasFailure) { _, failed in
            if !failed {
                onClose()
            }
        }
        .task(id: hasFailure) {
            await refreshPendingCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .autoLearnQueueDidChange)) { _ in
            Task {
                await refreshPendingCount()
            }
        }
    }

    private var retryGuidance: LocalizedStringKey {
        guard isAutoLearnEnabled else {
            return "Enable Auto Learn before retrying pending corrections."
        }
        guard let pendingCount else {
            return "The pending corrections could not be read. Retry to try again."
        }
        return "Pending corrections: \(pendingCount). Choose another model or provider above, then retry."
    }

    private func refreshPendingCount() async {
        pendingCount = try? await AutoLearnService.shared.outstandingReviewCount()
    }

    private var errorDescription: String {
        failureMessage.isEmpty
            ? String(localized: "The selected provider or model could not review the pending corrections.")
            : failureMessage
    }

    private var footer: some View {
        HStack {
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Retry") {
                Task {
                    await AutoLearnService.shared.retryPendingReviews()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isAutoLearnEnabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(Divider().opacity(0.5), alignment: .top)
    }
}

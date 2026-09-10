import SwiftUI

struct AutoLearnFailurePanel: View {
    let onClose: () -> Void

    @AppStorage(AutoLearnSettings.hasFailureKey) private var hasFailure = false
    @AppStorage(AutoLearnSettings.failureMessageKey) private var failureMessage = ""

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
                    Text("Choose another model or provider above, then retry the 24 pending corrections.")
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(Divider().opacity(0.5), alignment: .top)
    }
}

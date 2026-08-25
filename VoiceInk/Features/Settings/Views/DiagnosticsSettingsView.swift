import SwiftUI

struct DiagnosticsSettingsView: View {
    @State private var isExportingLogs = false
    @State private var exportedLogURL: URL?
    @State private var showLogExportError = false
    @State private var logExportError: String = ""

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let url = exportedLogURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.Status.positive)
                }

                Button("Export") {
                    exportDiagnosticLogs()
                }
                .disabled(isExportingLogs)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isExportingLogs {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Export Logs")
                }
                Text("Exports VoiceInk logs from the most recent 30 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Export Failed", isPresented: $showLogExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(logExportError)
        }
    }

    private func exportDiagnosticLogs() {
        isExportingLogs = true
        exportedLogURL = nil

        Task {
            do {
                let url = try await LogExporter.shared.exportLogs()
                await MainActor.run {
                    exportedLogURL = url
                    isExportingLogs = false
                }
            } catch {
                await MainActor.run {
                    logExportError = error.localizedDescription
                    showLogExportError = true
                    isExportingLogs = false
                }
            }
        }
    }
}

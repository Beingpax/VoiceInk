import SwiftUI

struct DiagnosticsSettingsView: View {
    @State private var isExportingLogs = false
    @State private var exportedLogURL: URL?
    @State private var showLogExportError = false
    @State private var logExportError: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export logs to help troubleshoot issues.")
                .settingsDescription()

            HStack(spacing: 12) {
                Button {
                    exportDiagnosticLogs()
                } label: {
                    HStack {
                        if isExportingLogs {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                        Text("Export Diagnostic Logs")
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(isExportingLogs)

                if let url = exportedLogURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .controlSize(.large)
                }
            }

            if exportedLogURL != nil {
                Text("Logs exported to Downloads folder.")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .alert("Export Failed", isPresented: $showLogExportError) {
            Button("OK", role: .cancel) { }
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

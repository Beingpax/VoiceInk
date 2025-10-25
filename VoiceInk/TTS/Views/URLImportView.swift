import SwiftUI

struct URLImportView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var urlString: String = ""
    @State private var shouldAutoGenerate: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: viewModel.isMinimalistMode ? 8 : 12) {
            HStack(alignment: .center, spacing: viewModel.isMinimalistMode ? 8 : 12) {
                TextField("https://example.com/article", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isImportingFromURL)
                    .onSubmit { triggerImport(autoGenerate: shouldAutoGenerate) }
                    .frame(minWidth: 240)

                Button {
                    triggerImport(autoGenerate: false)
                } label: {
                    if viewModel.isMinimalistMode {
                        Image(systemName: "tray.and.arrow.down")
                            .imageScale(.large)
                    } else {
                        Label("Import", systemImage: "tray.and.arrow.down")
                            .frame(minWidth: 90)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isImportingFromURL)
                .help("Import the page content without generating audio")

                Button {
                    triggerImport(autoGenerate: true)
                } label: {
                    if viewModel.isMinimalistMode {
                        Image(systemName: "waveform.badge.mic")
                            .imageScale(.large)
                    } else {
                        Label("Import & Generate", systemImage: "waveform.badge.mic")
                            .frame(minWidth: 150)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isImportingFromURL)
                .help("Import the page content and immediately generate speech")
            }

            HStack(spacing: viewModel.isMinimalistMode ? 8 : 12) {
                Toggle(isOn: $shouldAutoGenerate) {
                    Text("Auto-generate after import")
                }
                .disabled(viewModel.isImportingFromURL)

                if viewModel.isImportingFromURL {
                    ProgressView()
                        .progressViewStyle(.circular)
                }

                Spacer()
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text("Paste a web article URL to pull the readable text into the editor and let Smart Import trim the noise.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func triggerImport(autoGenerate: Bool) {
        Task {
            await viewModel.importText(from: urlString, autoGenerate: autoGenerate && shouldAutoGenerate)
        }
    }
}

struct URLImportView_Previews: PreviewProvider {
    static var previews: some View {
        URLImportView()
            .environmentObject(TTSViewModel())
            .padding()
            .frame(width: 600)
    }
}

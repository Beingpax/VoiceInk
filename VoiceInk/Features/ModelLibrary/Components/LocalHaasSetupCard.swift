import SwiftUI

struct LocalHaasSetupCard: View {
    var autoDownload = false
    var onReady: () -> Void = {}
    @ObservedObject private var runtime = LocalHaasRuntime.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HaaS-ja + Horizon").font(.headline)
            Text("このMacで音声認識と句読点補完を行います。初回に約655MBのモデルを取得します。取得後はインターネット接続がなくても使えます。")
                .font(.callout)
            if runtime.isDownloading {
                ProgressView(value: Double(runtime.completedFiles), total: Double(max(1, runtime.totalFiles)))
                Text("モデルを取得・検証しています（\(runtime.completedFiles)/\(runtime.totalFiles)ファイル）")
                    .font(.caption).foregroundStyle(.secondary)
                Button("中止") { runtime.cancelDownload() }
            } else if runtime.isReady {
                Label("モデルの準備ができました", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(runtime.errorMessage == nil ? "モデルをダウンロード" : "再試行") {
                    Task { await prepare() }
                }
            }
            if let message = runtime.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Link("HaaSモデルの配布元", destination: URL(string: "https://huggingface.co/sakasegawa/Haas-ja-v1.0-GGUF")!)
                Link("Horizonモデルの配布元", destination: URL(string: "https://huggingface.co/Horizon-Labs/punctuation-restoration-small")!)
            }.font(.caption)
        }
        .padding(16)
        .background(AppMaterialCardBackground(cornerRadius: 12))
        .task {
            await runtime.refreshStatus()
            if autoDownload { await prepare() }
        }
    }

    private func prepare() async {
        do { try await runtime.prepare(); onReady() } catch { /* Runtime publishes the actionable error. */ }
    }
}

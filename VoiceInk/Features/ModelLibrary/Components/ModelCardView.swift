import AppKit
import SwiftUI

struct ModelCardView: View {
    let model: any TranscriptionModel
    let isDownloaded: Bool
    let downloadProgress: [String: Double]
    let modelURL: URL?
    let isWarming: Bool

    // Actions
    var deleteAction: () -> Void
    var downloadAction: () -> Void
    var cancelDownloadAction: () -> Void
    var body: some View {
        Group {
            switch model.provider {
            case .whisper:
                if let whisperModel = model as? WhisperModel {
                    WhisperModelCardView(
                        model: whisperModel,
                        isDownloaded: isDownloaded,
                        downloadProgress: downloadProgress,
                        modelURL: modelURL,
                        isWarming: isWarming,
                        deleteAction: deleteAction,
                        downloadAction: downloadAction,
                        cancelDownloadAction: cancelDownloadAction
                    )
                } else if let importedModel = model as? ImportedWhisperModel {
                    ImportedWhisperModelCardView(
                        model: importedModel,
                        isDownloaded: isDownloaded,
                        modelURL: modelURL,
                        deleteAction: deleteAction
                    )
                }
            case .fluidAudio:
                if let fluidAudioModel = model as? FluidAudioModel {
                    FluidAudioModelCardView(model: fluidAudioModel)
                }
            case .transcribeCpp:
                if let transcribeCppModel = model as? TranscribeCppModel {
                    TranscribeCppModelCardView(model: transcribeCppModel)
                }
            case .nativeApple:
                if let nativeAppleModel = model as? NativeAppleModel {
                    NativeAppleModelCardView(
                        model: nativeAppleModel
                    )
                }
            default:
                EmptyView()
            }
        }
    }
}

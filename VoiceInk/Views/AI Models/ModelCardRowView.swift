import SwiftUI
import AppKit

struct ModelCardRowView: View {
    let model: any TranscriptionModel
    @ObservedObject var whisperState: WhisperState
    let isDownloaded: Bool
    let isCurrent: Bool
    let downloadProgress: [String: Double]
    let modelURL: URL?
    
    // Actions
    var deleteAction: () -> Void
    var setDefaultAction: () -> Void
    var downloadAction: () -> Void
    var editAction: ((CustomCloudModel) -> Void)?
    
    var body: some View {
        Group {
            switch model.provider {
            case .local:
                if let localModel = model as? LocalModel {
                    LocalModelCardView(
                        model: localModel,
                        isDownloaded: isDownloaded,
                        isCurrent: isCurrent,
                        downloadProgress: downloadProgress,
                        modelURL: modelURL,
                        deleteAction: deleteAction,
                        setDefaultAction: setDefaultAction,
                        downloadAction: downloadAction
                    )
                }
                    case .parakeet:
            if let parakeetModel = model as? ParakeetModel {
                ParakeetModelCardRowView(
                    model: parakeetModel,
                        whisperState: whisperState
                    )
                }
            case .groq, .elevenLabs, .deepgram, .mistral:
                if let cloudModel = model as? CloudModel {
                    CloudModelCardView(
                        model: cloudModel,
                        isCurrent: isCurrent,
                        setDefaultAction: setDefaultAction
                    )
                }
            case .custom:
                if let customModel = model as? CustomCloudModel {
                    CustomModelCardView(
                        model: customModel,
                        isCurrent: isCurrent,
                        setDefaultAction: setDefaultAction,
                        deleteAction: deleteAction,
                        editAction: editAction ?? { _ in }
                    )
                }
            }
        }
    }
}
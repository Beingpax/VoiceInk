import SwiftUI
import AppKit

struct ModelCardRowView: View {
    let model: any TranscriptionModel
    @ObservedObject var whisperState: WhisperState
    let isDownloaded: Bool
    let isCurrent: Bool
    let downloadProgress: [String: Double]
    let modelURL: URL?
    let isWarming: Bool
    
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
                        isWarming: isWarming,
                        deleteAction: deleteAction,
                        setDefaultAction: setDefaultAction,
                        downloadAction: downloadAction
                    )
                } else if let importedModel = model as? ImportedLocalModel {
                    ImportedLocalModelCardView(
                        model: importedModel,
                        isDownloaded: isDownloaded,
                        isCurrent: isCurrent,
                        modelURL: modelURL,
                        deleteAction: deleteAction,
                        setDefaultAction: setDefaultAction
                    )
                }
                    case .parakeet:
            if let parakeetModel = model as? ParakeetModel {
                ParakeetModelCardRowView(
                    model: parakeetModel,
                        whisperState: whisperState
                    )
                }
            case .senseVoice:
                if let senseVoiceModel = model as? SenseVoiceModel {
                    SenseVoiceModelCardView(
                        model: senseVoiceModel,
                        whisperState: whisperState,
                        isCurrent: isCurrent,
                        isDownloaded: isDownloaded,
                        downloadProgress: whisperState.senseVoiceDownloadProgress[senseVoiceModel.name] ?? 0,
                        downloadAction: downloadAction,
                        deleteAction: deleteAction,
                        setDefaultAction: setDefaultAction,
                        showInFinderAction: { whisperState.showSenseVoiceModelInFinder(senseVoiceModel) }
                    )
                }
            case .nativeApple:
                if let nativeAppleModel = model as? NativeAppleModel {
                    NativeAppleModelCardView(
                        model: nativeAppleModel,
                        isCurrent: isCurrent,
                        setDefaultAction: setDefaultAction
                    )
                }
            case .groq, .elevenLabs, .deepgram, .mistral, .gemini, .soniox:
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

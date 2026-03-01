import SwiftUI

struct MiniRecorderView: View {
    @ObservedObject var engine: VoiceInkEngine
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService

    @State private var activePopover: ActivePopoverState = .none

    // MARK: - Design Constants
    private let mainContentHeight: CGFloat = 40
    private let width: CGFloat = 184
    private let cornerRadius: CGFloat = 20

    private var contentLayout: some View {
        HStack(spacing: 0) {
            RecorderPromptButton(
                activePopover: $activePopover,
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.leading, 12)

            Spacer(minLength: 0)

            RecorderStatusDisplay(
                currentState: engine.recordingState,
                audioMeter: recorder.audioMeter
            )

            Spacer(minLength: 0)

            RecorderPowerModeButton(
                activePopover: $activePopover,
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.trailing, 12)
        }
        .frame(height: mainContentHeight)
    }

    var body: some View {
        if windowManager.isVisible {
            contentLayout
                .frame(width: width)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}


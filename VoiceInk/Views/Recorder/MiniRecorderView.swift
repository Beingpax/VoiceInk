import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    let onRecordButtonTapped: () -> Void
    @EnvironmentObject var windowManager: MiniWindowManager

    // MARK: - Layout Constants

    private let controlBarHeight: CGFloat = 40
    private let compactWidth: CGFloat = 184
    private let expandedWidth: CGFloat = 300
    private let compactCornerRadius: CGFloat = 20
    private let expandedCornerRadius: CGFloat = 14

    // true when live transcript is streaming in during recording
    private var hasLiveTranscript: Bool {
        stateProvider.recordingState == .recording
            && !stateProvider.partialTranscript.isEmpty
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            RecorderRecordButton(
                recordingState: stateProvider.recordingState,
                action: onRecordButtonTapped
            )
            .padding(.leading, 10)

            Spacer(minLength: 0)

            RecorderStatusDisplay(
                currentState: stateProvider.recordingState,
                audioMeter: recorder.audioMeter
            )

            Spacer(minLength: 0)

            RecorderModeButton(
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.trailing, 12)
        }
        .frame(height: controlBarHeight)
    }

    private var transcriptSection: some View {
        VStack(spacing: 0) {
            if hasLiveTranscript {
                LiveTranscriptView(text: stateProvider.partialTranscript)
                Divider().background(Color.white.opacity(0.15))
            }
        }
    }

    var body: some View {
        if windowManager.isVisible {
            VStack(spacing: 0) {
                transcriptSection
                controlBar
            }
            .frame(width: hasLiveTranscript ? expandedWidth : compactWidth)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: hasLiveTranscript ? expandedCornerRadius : compactCornerRadius, style: .continuous))
            .animation(.easeInOut(duration: 0.3), value: hasLiveTranscript)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

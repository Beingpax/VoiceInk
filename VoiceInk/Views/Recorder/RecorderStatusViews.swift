import SwiftUI

// MARK: - Processing Indicator Component
struct ProcessingIndicator: View {
    @State private var rotation: Double = 0
    let color: Color

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(color, lineWidth: 1.7)
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Progress Animation Component
struct ProgressAnimation: View {
    @State private var currentDot = 0
    @State private var timer: Timer?
    let animationSpeed: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index <= currentDot ? 0.8 : 0.2))
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: animationSpeed, repeats: true) { _ in
                currentDot = (currentDot + 1) % 7
                if currentDot >= 5 { currentDot = -1 }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Status Display Component
struct RecorderStatusDisplay: View {
    let currentState: RecordingState
    let audioMeter: AudioMeter
    let menuBarHeight: CGFloat?

    init(currentState: RecordingState, audioMeter: AudioMeter, menuBarHeight: CGFloat? = nil) {
        self.currentState = currentState
        self.audioMeter = audioMeter
        self.menuBarHeight = menuBarHeight
    }

    var body: some View {
        Group {
            if currentState == .enhancing {
                VStack(spacing: 2) {
                    Text("Enhancing")
                        .foregroundColor(.white)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    ProgressAnimation(animationSpeed: 0.15)
                }
            } else if currentState == .transcribing {
                VStack(spacing: 2) {
                    Text("Transcribing")
                        .foregroundColor(.white)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    ProgressAnimation(animationSpeed: 0.12)
                }
            } else if currentState == .recording {
                AudioVisualizer(
                    audioMeter: audioMeter,
                    color: .white,
                    isActive: currentState == .recording
                )
                .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
            } else {
                StaticVisualizer(color: .white)
                    .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
            }
        }
    }
}

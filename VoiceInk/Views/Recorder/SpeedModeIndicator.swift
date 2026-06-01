import SwiftUI

/// Minimal recording indicator for Speed Mode — zero animation, zero overhead.
/// Just a colored dot + state text. No TimelineView, no Canvas, no waveform.
struct SpeedModeIndicator: View {
    let state: RecordingState

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)

            Text(stateLabel)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dotColor: Color {
        switch state {
        case .recording: return .red
        case .transcribing: return .orange
        case .enhancing: return .purple
        case .starting: return .yellow
        default: return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }

    private var stateLabel: String {
        switch state {
        case .recording: return "REC"
        case .transcribing: return "TRANSCRIBING"
        case .enhancing: return "ENHANCING"
        case .starting: return "STARTING"
        default: return "READY"
        }
    }
}

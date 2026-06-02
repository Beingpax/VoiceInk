import SwiftUI

/// Speed Mode settings card — one toggle to disable all visual overhead.
/// When enabled: no visualizer, no decorative elements, no animations,
/// no screen capture/OCR, no dynamic HUD, no drag-to-target.
struct SpeedModeSettingsCard: View {
    @AppStorage("speedMode") private var speedMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(speedMode ? .orange : Color(red: 0.36, green: 0.28, blue: 0.88))
                Text("Speed Mode")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                Spacer()
                Toggle("", isOn: $speedMode)
                    .toggleStyle(.switch)
                    .tint(.orange)
            }

            Divider().opacity(0.5)

            if speedMode {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Active — maximum responsiveness", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                    Text("Disabled: waveform visualizer, decorative labels, window animations, screen context capture, dynamic HUD sizing, drag-to-target")
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Strip all visual overhead for SuperWhisper-level toggle responsiveness. Minimal indicator replaces waveform.")
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(speedMode ? Color.orange.opacity(0.04) : Color.white.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(speedMode ? Color.orange.opacity(0.3) : Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

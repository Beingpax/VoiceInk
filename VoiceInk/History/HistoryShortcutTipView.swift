import SwiftUI
import KeyboardShortcuts

struct HistoryShortcutTipView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "command.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Access")
                        .font(.headline)
                    Text("Open history from anywhere with a global shortcut")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 12) {
                Text("Open History Window")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                KeyboardShortcuts.Recorder(for: .openHistoryWindow)
                    .controlSize(.small)

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}

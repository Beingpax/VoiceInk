import SwiftUI

struct HistoryShortcutTipView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "command.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
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

                ShortcutRecorder(action: .openHistoryWindow)
                    .controlSize(.small)

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Surface.materialCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .strokeBorder(AppTheme.Border.card, lineWidth: 1)
        )
    }
}

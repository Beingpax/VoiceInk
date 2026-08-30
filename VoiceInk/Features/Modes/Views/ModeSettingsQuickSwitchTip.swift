import SwiftUI

struct ModeSettingsQuickSwitchTip: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mode shortcuts")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)
                    .lineLimit(1)

                Text("During recording, press Option + 1-9 to switch modes quickly.")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.Text.secondary)
                    .frame(width: 22, height: 22)
                    .background(AppTheme.Surface.control)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss shortcut tip")
        }
        .padding(12)
        .background(AppMaterialCardBackground(cornerRadius: AppTheme.Radius.card))
    }
}

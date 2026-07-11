import SwiftUI

struct AppIconView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Accent.fill)
                .frame(width: 160, height: 160)
                .blur(radius: 30)

            if let image = NSImage(named: "AppIcon") {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .cornerRadius(30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.Accent.border, radius: 20)
            }
        }
    }
}

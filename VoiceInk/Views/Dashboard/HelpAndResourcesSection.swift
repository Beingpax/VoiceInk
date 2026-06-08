import SwiftUI

struct HelpAndResourcesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Help & Resources")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                resourceLink(
                    icon: "sparkles",
                    title: "Recommended Models",
                    color: AppTheme.Sidebar.models,
                    url: "https://tryvoiceink.com/recommended-models"
                )

                resourceLink(
                    icon: "video.fill",
                    title: "YouTube Videos & Guides",
                    color: AppTheme.Sidebar.dashboard,
                    url: "https://www.youtube.com/@tryvoiceink/videos"
                )

                resourceLink(
                    icon: "book.fill",
                    title: "Documentation",
                    color: AppTheme.Sidebar.dictionary,
                    url: "https://tryvoiceink.com/docs"
                )
                
                resourceLink(
                    icon: "exclamationmark.bubble.fill",
                    title: "Feedback or Issues?",
                    color: AppTheme.Sidebar.audio,
                    action: {
                        EmailSupport.openSupportEmail()
                    }
                )
            }
        }
        .padding(18)
        .background(AppCardBackground(cornerRadius: 28))
    }
    
    private func resourceLink(icon: String, title: String, color: Color, url: String? = nil, action: (() -> Void)? = nil) -> some View {
        Button(action: {
            if let action = action {
                action()
            } else if let urlString = url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 10) {
                DashboardIconGlyph(systemName: icon, color: color, size: 15, frameSize: 20)
                
                Text(title)
                    .font(.system(size: 13))
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(AppTheme.Surface.subtle)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        }
        .buttonStyle(.plain)
    }
}

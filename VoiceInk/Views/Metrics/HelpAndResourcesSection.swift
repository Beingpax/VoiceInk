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
                    url: "https://tryvoiceink.com/recommended-models"
                )

                resourceLink(
                    icon: "video.fill",
                    title: "YouTube Videos & Guides",
                    url: "https://www.youtube.com/@tryvoiceink/videos"
                )

                resourceLink(
                    icon: "book.fill",
                    title: "Documentation",
                    url: "https://tryvoiceink.com/docs"
                )
                
                resourceLink(
                    icon: "exclamationmark.bubble.fill",
                    title: "Feedback or Issues?",
                    action: {
                        EmailSupport.openSupportEmail()
                    }
                )
            }
        }
        .padding(18)
        .background(CardBackground(cornerRadius: 28))
    }
    
    private func resourceLink(icon: String, title: String, url: String? = nil, action: (() -> Void)? = nil) -> some View {
        Button(action: {
            if let action = action {
                action()
            } else if let urlString = url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13))
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

struct AnnouncementView: View {
    let title: String
    let description: String
    let onClose: () -> Void
    let onLearnMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }

            if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }

            HStack(spacing: 8) {
                Button(action: onLearnMore) {
                    Text("Learn more")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onClose) {
                    Text("Dismiss")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minWidth: 360, idealWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.clear)
                .background(
                    ZStack {
                        // Match Mini Recorder background layers
                        Color.black.opacity(0.9)
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.95),
                                Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.9)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .opacity(0.05)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
        )
    }
}


 


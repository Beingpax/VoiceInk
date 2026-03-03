import SwiftUI

struct AppNotificationView: View {
    let title: String
    let type: NotificationType
    let duration: TimeInterval
    let onClose: () -> Void
    let onTap: (() -> Void)?
    
    @State private var progress: Double = 1.0
    @State private var timer: Timer?

    enum NotificationType {
        case error
        case warning
        case info
        case success

        var iconName: String {
            switch self {
            case .error: return "xmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .error: return .red
            case .warning: return .yellow
            case .info: return .blue
            case .success: return .green
            }
        }
    }

    var body: some View {
        ZStack {
            HStack(alignment: .center, spacing: 12) {
                // Type icon
                Image(systemName: type.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(type.iconColor)
                    .frame(width: 20, height: 20)

                // Single message text
                Text(title)
                    .font(.system(size: 12))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 220, maxWidth: 750, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.clear)
                .background(
                    ZStack {
                        // Base dark background
                        Color.black.opacity(0.9)
                        
                        // Subtle gradient overlay
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.95),
                                Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.9)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        
                        // Very subtle visual effect for depth
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .opacity(0.05)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
        )
        .overlay(
            // Subtle inner border
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .overlay(
            VStack {
                Spacer()
                GeometryReader { geometry in
                    Rectangle()
                        .fill(type.iconColor.opacity(0.8))
                        .frame(width: geometry.size.width * max(0, progress), height: 2)
                        .animation(.linear(duration: 0.1), value: progress)
                }
                .frame(height: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .onAppear {
            startProgressTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onTapGesture {
            if let onTap = onTap {
                onTap()
                onClose()
            }
        }
    }
    
    private func startProgressTimer() {
        let updateInterval: TimeInterval = 0.1
        let totalSteps = duration / updateInterval
        let stepDecrement = 1.0 / totalSteps
        
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            if progress > 0 {
                progress = max(0, progress - stepDecrement)
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }
}


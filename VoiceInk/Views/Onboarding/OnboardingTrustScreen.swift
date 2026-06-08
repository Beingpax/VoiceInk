import AppKit
import SwiftUI

struct OnboardingTrustScreen: View {
    let contentMaxWidth: CGFloat
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepScreen(
            systemImage: "lock.shield",
            title: "Privacy Starts Here",
            subtitle: "Review how VoiceInk handles your data before choosing a license.",
            contentMaxWidth: max(contentMaxWidth, 720),
            showsHeader: false,
            contentYOffset: 0
        ) {
            OnboardingTrustContent()
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Continue",
                isPrimaryEnabled: true,
                onLeading: onBack,
                onPrimary: onContinue
            )
        }
    }
}

private struct OnboardingTrustContent: View {
    var body: some View {
        ZStack {
            TrustHeader()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 52)

            TrustBody()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: 24)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TrustHeader: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(AppTheme.Text.primary)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.Surface.controlActive)
                )

            Text("VoiceInk is private by default")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(AppTheme.Text.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TrustBody: View {
    var body: some View {
        VStack(spacing: 0) {
            TrustMapView()
                .frame(height: 270)
                .padding(.bottom, 28)

            VStack(spacing: 10) {
                Text("Your data never has to leave your device.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)
                    .multilineTextAlignment(.center)

                Text("VoiceInk is also open source, so you can inspect every single line of code.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.Text.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 610)
            }
        }
    }
}

private struct TrustMapView: View {
    var body: some View {
        ZStack {
            TrustConnectorLines()
                .stroke(AppTheme.Border.control.opacity(0.58), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .frame(width: 500, height: 210)
                .offset(y: 22)

            TrustPill(
                systemImage: "internaldrive.fill",
                title: "Local Storage"
            )
            .offset(y: -94)

            TrustPill(
                systemImage: "chevron.left.forwardslash.chevron.right",
                title: "Open Source"
            )
            .offset(x: -172, y: -12)

            TrustPill(
                systemImage: "slider.horizontal.3",
                title: "You Control It"
            )
            .offset(x: 172, y: -12)

            TrustShield()
                .offset(y: 76)
        }
    }
}

private struct TrustConnectorLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX
        let topY = rect.minY + 18
        let branchY = rect.minY + 110
        let shieldY = rect.maxY - 34
        let leftX = rect.minX + 78
        let rightX = rect.maxX - 78

        path.move(to: CGPoint(x: centerX, y: topY))
        path.addLine(to: CGPoint(x: centerX, y: shieldY))

        path.move(to: CGPoint(x: leftX, y: branchY))
        path.addLine(to: CGPoint(x: leftX, y: shieldY - 5))
        path.addLine(to: CGPoint(x: centerX - 52, y: shieldY - 5))

        path.move(to: CGPoint(x: rightX, y: branchY))
        path.addLine(to: CGPoint(x: rightX, y: shieldY - 5))
        path.addLine(to: CGPoint(x: centerX + 52, y: shieldY - 5))

        return path
    }
}

private struct TrustPill: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.Text.secondary)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.Text.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(
            Capsule()
                .fill(AppTheme.Surface.control.opacity(0.84))
        )
        .overlay(
            Capsule()
                .stroke(AppTheme.Border.subtle, lineWidth: 1)
        )
    }
}

private struct TrustShield: View {
    var body: some View {
        ZStack {
            Image(systemName: "shield.fill")
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            AppTheme.Surface.control,
                            AppTheme.Surface.controlActive
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Image(systemName: "shield")
                        .font(.system(size: 96, weight: .regular))
                        .foregroundColor(AppTheme.Border.control)
                )

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 52, height: 52)
        }
    }
}

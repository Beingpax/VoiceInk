import SwiftUI

struct OnboardingBackground: View {
    var body: some View {
        VisualEffectView(
            material: .sidebar,
            blendingMode: .behindWindow
        )
        .ignoresSafeArea()
    }
}

struct OnboardingHeroHeader: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.primary.opacity(0.82))
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.Surface.controlActive)
                )

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.Text.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct OnboardingProgressBadge: View {
    let currentStep: Int
    let totalSteps: Int

    private var percent: Int {
        guard totalSteps > 0 else { return 0 }
        return Int((Double(currentStep) / Double(totalSteps) * 100).rounded())
    }

    var body: some View {
        SegmentedProgressRing(
            totalSegments: totalSteps,
            filledSegments: currentStep,
            percent: percent
        )
    }
}

struct OnboardingBottomBar: View {
    let leadingTitle: String?
    let primaryTitle: String
    let isPrimaryEnabled: Bool
    var showsPrimaryButton: Bool = true
    let onLeading: (() -> Void)?
    let onPrimary: () -> Void

    var body: some View {
        HStack {
            if let leadingTitle, let onLeading {
                Button(action: onLeading) {
                    Text(leadingTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary.opacity(0.78))
                        .frame(width: 104, height: 42)
                        .background(AppMaterialCardBackground(cornerRadius: AppTheme.Radius.control))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if showsPrimaryButton {
                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isPrimaryEnabled ? .white : .secondary)
                        .frame(width: 132, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                                .fill(isPrimaryEnabled ? Color.primary.opacity(0.78) : AppTheme.Surface.controlActive)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isPrimaryEnabled)
            }
        }
    }
}

struct OnboardingStepScreen<Content: View, BottomBar: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let contentMaxWidth: CGFloat
    let bottomBarMaxWidth: CGFloat
    let showsHeader: Bool
    let contentYOffset: CGFloat
    let content: Content
    let bottomBar: BottomBar

    init(
        stage: OnboardingStage,
        contentMaxWidth: CGFloat,
        bottomBarMaxWidth: CGFloat? = nil,
        showsHeader: Bool = true,
        contentYOffset: CGFloat = 0,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar
    ) {
        self.systemImage = stage.systemImage
        self.title = stage.title
        self.subtitle = stage.subtitle
        self.contentMaxWidth = contentMaxWidth
        self.bottomBarMaxWidth = bottomBarMaxWidth ?? contentMaxWidth
        self.showsHeader = showsHeader
        self.contentYOffset = contentYOffset
        self.content = content()
        self.bottomBar = bottomBar()
    }

    init(
        systemImage: String,
        title: String,
        subtitle: String,
        contentMaxWidth: CGFloat,
        bottomBarMaxWidth: CGFloat? = nil,
        showsHeader: Bool = true,
        contentYOffset: CGFloat = 0,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.contentMaxWidth = contentMaxWidth
        self.bottomBarMaxWidth = bottomBarMaxWidth ?? contentMaxWidth
        self.showsHeader = showsHeader
        self.contentYOffset = contentYOffset
        self.content = content()
        self.bottomBar = bottomBar()
    }

    var body: some View {
        ZStack {
            if showsHeader {
                VStack(spacing: 0) {
                    OnboardingHeroHeader(
                        systemImage: systemImage,
                        title: title,
                        subtitle: subtitle
                    )
                    .frame(maxWidth: contentMaxWidth)

                    Spacer(minLength: 0)
                }
                .padding(.top, 52)
            }

            content
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: contentYOffset)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                bottomBar
                    .frame(maxWidth: bottomBarMaxWidth)
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 48)
    }
}

private struct SegmentedProgressRing: View {
    let totalSegments: Int
    let filledSegments: Int
    let percent: Int

    private let segmentGap: Double = 0.035
    private let lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            ForEach(0..<totalSegments, id: \.self) { index in
                Circle()
                    .trim(from: segmentStart(index), to: segmentEnd(index))
                    .stroke(
                        index < filledSegments ? Color.primary.opacity(0.72) : AppTheme.Surface.controlActive,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            Text("\(percent)%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primary.opacity(0.82))
        }
        .frame(width: 46, height: 46)
    }

    private func segmentStart(_ index: Int) -> CGFloat {
        guard totalSegments > 0 else { return 0 }
        return CGFloat(Double(index) / Double(totalSegments) + segmentGap / 2)
    }

    private func segmentEnd(_ index: Int) -> CGFloat {
        guard totalSegments > 0 else { return 0 }
        return CGFloat(Double(index + 1) / Double(totalSegments) - segmentGap / 2)
    }
}

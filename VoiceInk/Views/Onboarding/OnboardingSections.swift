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

enum OnboardingLayout {
    static let chromeMaxWidth: CGFloat = 560
    static let horizontalPadding: CGFloat = 48
    static let headerTopPadding: CGFloat = 52
    static let bottomPadding: CGFloat = 28
}

struct OnboardingHeroHeader: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(AppTheme.Text.primary)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.Surface.controlActive)
                )

            VStack(spacing: 8) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(AppTheme.Text.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(subtitle))
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

    private var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStep) / Double(totalSteps)
    }

    var body: some View {
        SegmentedProgressRing(
            totalSegments: totalSteps,
            filledSegments: currentStep,
            progress: progress
        )
    }
}

enum OnboardingBottomBarPlacement {
    case split
    case centered
}

struct OnboardingBottomBar: View {
    let leadingTitle: String?
    let primaryTitle: String
    let isPrimaryEnabled: Bool
    var placement: OnboardingBottomBarPlacement = .split
    let onLeading: (() -> Void)?
    let onPrimary: () -> Void

    private enum Metrics {
        static let controlButtonWidth: CGFloat = 132
        static let buttonHeight: CGFloat = 42
        static let primaryButtonHorizontalPadding: CGFloat = 20
    }

    var body: some View {
        HStack(spacing: 0) {
            switch placement {
            case .split:
                leadingSlot
                Spacer(minLength: 0)
            case .centered:
                Spacer(minLength: 0)
            }

            primaryButton

            if case .centered = placement {
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var leadingSlot: some View {
        if let leadingTitle, let onLeading {
            Button(action: onLeading) {
                Text(LocalizedStringKey(leadingTitle))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.Action.secondaryForeground)
                    .frame(width: Metrics.controlButtonWidth, height: Metrics.buttonHeight)
                    .background(AppMaterialCardBackground(cornerRadius: AppTheme.Radius.control))
            }
            .buttonStyle(.plain)
        } else {
            AppTheme.Surface.clear
                .frame(width: Metrics.controlButtonWidth, height: Metrics.buttonHeight)
                .accessibilityHidden(true)
        }
    }

    private var primaryButton: some View {
        Button(action: onPrimary) {
            Text(LocalizedStringKey(primaryTitle))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(
                    isPrimaryEnabled ? AppTheme.Action.primaryForeground : AppTheme.Action.disabledForeground
                )
                .padding(.horizontal, Metrics.primaryButtonHorizontalPadding)
                .frame(minWidth: Metrics.controlButtonWidth, minHeight: Metrics.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .fill(isPrimaryEnabled ? AppTheme.Action.primaryFill : AppTheme.Action.disabledFill)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isPrimaryEnabled)
    }
}

struct OnboardingStepScreen<Content: View, BottomBar: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let contentMaxWidth: CGFloat
    let showsHeader: Bool
    let contentYOffset: CGFloat
    let content: Content
    let bottomBar: BottomBar

    init(
        stage: OnboardingStage,
        contentMaxWidth: CGFloat,
        showsHeader: Bool = true,
        contentYOffset: CGFloat = 0,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar
    ) {
        self.systemImage = stage.systemImage
        self.title = stage.title
        self.subtitle = stage.subtitle
        self.contentMaxWidth = contentMaxWidth
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
        showsHeader: Bool = true,
        contentYOffset: CGFloat = 0,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.contentMaxWidth = contentMaxWidth
        self.showsHeader = showsHeader
        self.contentYOffset = contentYOffset
        self.content = content()
        self.bottomBar = bottomBar()
    }

    var body: some View {
        if showsHeader {
            VStack(spacing: 0) {
                OnboardingHeroHeader(
                    systemImage: systemImage,
                    title: title,
                    subtitle: subtitle
                )
                .frame(maxWidth: OnboardingLayout.chromeMaxWidth)
                .padding(.top, OnboardingLayout.headerTopPadding)

                Spacer(minLength: 0)

                content
                    .frame(maxWidth: contentMaxWidth)
                    .offset(y: contentYOffset)

                Spacer(minLength: 0)

                bottomBar
                    .frame(maxWidth: OnboardingLayout.chromeMaxWidth)
                    .padding(.bottom, OnboardingLayout.bottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, OnboardingLayout.horizontalPadding)
        } else {
            ZStack {
                content
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(y: contentYOffset)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    bottomBar
                        .frame(maxWidth: OnboardingLayout.chromeMaxWidth)
                }
                .padding(.bottom, OnboardingLayout.bottomPadding)
            }
            .padding(.horizontal, OnboardingLayout.horizontalPadding)
        }
    }
}

private struct SegmentedProgressRing: View {
    let totalSegments: Int
    let filledSegments: Int
    let progress: Double

    private let segmentGap: Double = 0.035
    private let lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            ForEach(0..<totalSegments, id: \.self) { index in
                Circle()
                    .trim(from: segmentStart(index), to: segmentEnd(index))
                    .stroke(
                        index < filledSegments ? AppTheme.Accent.primary : AppTheme.Surface.controlActive,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.Text.primary)
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

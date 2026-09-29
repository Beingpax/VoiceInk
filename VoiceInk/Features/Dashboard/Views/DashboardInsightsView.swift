import SwiftUI

struct DashboardInsightsView: View {
    @Binding var selectedPeriod: DashboardInsightPeriod
    let dailyActivityPoints: [DashboardProductivityPoint]
    let allTimeDailyActivityPoints: [DashboardProductivityPoint]
    let peakHoursSummary: DashboardPeakHoursSummary
    let isPeakHoursLocked: Bool
    let timeSavedSummary: DashboardTimeSavedSummary
    let modelUsage: ModelUsageSummary
    let modelPerformanceSummaries: [ModelPerformanceSummary]
    let onBack: () -> Void
    let onViewModelUsage: () -> Void
    let onViewModelPerformance: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            DashboardEditorialSummaryCard(
                summary: timeSavedSummary
            )

            DashboardActivityCalendarCard(
                points: allTimeDailyActivityPoints,
                selectedPoints: dailyActivityPoints,
                peakHoursSummary: peakHoursSummary,
                isPeakHoursLocked: isPeakHoursLocked
            )

            ModelUsageCard(
                summary: modelUsage,
                onViewMore: onViewModelUsage
            )

            ModelPerformanceCard(
                summaries: modelPerformanceSummaries,
                onViewMore: onViewModelPerformance
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(DashboardInsightButtonStyle())
            .help("Back to dashboard")
            .accessibilityLabel("Back to dashboard")

            VStack(alignment: .leading, spacing: 3) {
                Text("VoiceInk Insights")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppTheme.Text.primary)

                Text("A closer look at your VoiceInk usage.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.Text.secondary)
            }
            .layoutPriority(1)

            Spacer(minLength: 16)

            InsightPeriodPicker(
                title: "Insights period",
                selection: $selectedPeriod
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

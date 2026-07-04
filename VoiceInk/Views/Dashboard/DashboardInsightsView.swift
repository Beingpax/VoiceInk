import SwiftUI

struct DashboardInsightsView: View {
    @Binding var selectedPeriod: DashboardInsightPeriod
    let productivityPoints: [DashboardProductivityPoint]
    let peakHoursSummary: DashboardPeakHoursSummary
    let isPeakHoursLocked: Bool
    let timeSavedSummary: DashboardTimeSavedSummary
    let modelUsage: ModelUsageSummary
    let modelPerformanceSummaries: [ModelPerformanceSummary]
    let onBack: () -> Void
    let onViewModelUsage: () -> Void
    let onViewModelPerformance: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            DashboardProductivityCard(
                period: $selectedPeriod,
                points: productivityPoints
            )

            HStack(alignment: .top, spacing: DashboardLayout.columnSpacing) {
                DashboardPeakHoursCard(summary: peakHoursSummary, isLocked: isPeakHoursLocked)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                DashboardTimeSavedCard(summary: timeSavedSummary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("VoiceInk Insights")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Text.primary)

                Text("A closer look at your VoiceInk usage.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Text.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                AppIconButton(
                    systemName: "chevron.left",
                    help: "Back to dashboard",
                    size: 34,
                    iconSize: 12,
                    cornerRadius: 17,
                    action: onBack
                )

                InsightPeriodPicker(
                    title: "Insights period",
                    selection: $selectedPeriod
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

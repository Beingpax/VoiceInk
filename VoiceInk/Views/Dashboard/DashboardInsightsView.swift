import SwiftUI

struct DashboardInsightsView: View {
    @Binding var selectedPeriod: DashboardProductivityPeriod
    let productivityPoints: [DashboardProductivityPoint]
    let peakHoursSummary: DashboardPeakHoursSummary
    let isPeakHoursLocked: Bool
    let timeSavedSummary: DashboardTimeSavedSummary
    let modelUsageSummaries: [DashboardModelUsageSummary]
    let onBack: () -> Void
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

            DashboardModelUsageCard(
                summaries: modelUsageSummaries,
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

                Picker("", selection: $selectedPeriod) {
                    ForEach(DashboardProductivityPeriod.allCases) { period in
                        Text(period.pickerTitle).tag(period)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

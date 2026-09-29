import Foundation
import SwiftUI

struct ModelDetailActionLabel: View {
    let title: LocalizedStringKey
    var icon: String = "chevron.right"

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(1)

            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(height: 32)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct InsightPeriodPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: DashboardInsightPeriod

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(DashboardInsightPeriod.allCases) { period in
                    Button {
                        selection = period
                    } label: {
                        Text(period.pickerTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                    }
                    .buttonStyle(DashboardInsightButtonStyle(isSelected: period == selection, isQuiet: true))
                    .accessibilityAddTraits(period == selection ? [.isSelected] : [])
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            compactPicker
        }
        .padding(5)
        .background(AppTheme.Insights.card, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var compactPicker: some View {
        Menu {
            ForEach(DashboardInsightPeriod.allCases) { period in
                Button {
                    selection = period
                } label: {
                    if period == selection {
                        Label(period.pickerTitle, systemImage: "checkmark")
                    } else {
                        Text(period.pickerTitle)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text(selection.pickerTitle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.Insights.selectionText)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(AppTheme.Insights.selection, in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(Text(title))
    }
}

enum ModelLinks {
    static func openRecommendedModels() {
        if let url = URL(string: "https://tryvoiceink.com/docs/recommended-models") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ModelActionLabel: View {
    let title: LocalizedStringKey
    let icon: String
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))

            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isPrimary ? Color.white : AppTheme.Text.primary)
        .padding(.horizontal, isPrimary ? 14 : 12)
        .frame(height: 34)
        .background(isPrimary ? AppTheme.Insights.productivity : AppTheme.Insights.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isPrimary ? Color.clear : AppTheme.Insights.border,
                    lineWidth: 1
                )
        }
    }
}

struct InsightEmptyState: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondary)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
    }
}

struct ModelPreviewCardHeader: View {
    let title: LocalizedStringKey
    var infoTip: LocalizedStringKey?
    let viewMoreHelp: String
    let onViewMore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            if let infoTip {
                InfoTip(infoTip)
                    .help(Text(infoTip))
            }

            Spacer(minLength: 0)

            Button(action: onViewMore) {
                ModelDetailActionLabel(title: "View details")
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .help(viewMoreHelp)
        }
    }
}

struct ModelPreviewRow: Identifiable {
    var id: String { "\(kind.rawValue)-\(name)" }
    let name: String
    let kind: ModelInsightKind
    let value: String
    let sessionCount: Int
}

extension ModelInsightKind {
    var localizedTitle: String {
        switch self {
        case .transcription:
            return String(localized: "Transcription")
        case .enhancement:
            return String(localized: "Enhancement")
        }
    }
}

struct ModelPreviewColumnsRow: View {
    let leftTitle: LocalizedStringKey
    let leftValueTitle: LocalizedStringKey
    let leftEmptyTitle: LocalizedStringKey
    let leftEmptyIcon: String
    let leftRows: [ModelPreviewRow]

    let rightTitle: LocalizedStringKey
    let rightValueTitle: LocalizedStringKey
    let rightEmptyTitle: LocalizedStringKey
    let rightEmptyIcon: String
    let rightRows: [ModelPreviewRow]

    let overallEmptyTitle: LocalizedStringKey
    let overallEmptyIcon: String
    var valueColumnWidth: CGFloat = 80

    var body: some View {
        if leftRows.isEmpty && rightRows.isEmpty {
            InsightEmptyState(title: overallEmptyTitle, icon: overallEmptyIcon)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    leftColumn
                    Divider().overlay(AppTheme.Insights.grid)
                    rightColumn
                }
                .frame(minWidth: 580)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 20) {
                    leftColumn
                    Divider()
                    rightColumn
                }
            }
        }
    }

    private var leftColumn: some View {
        ModelInsightSection(
            title: leftTitle,
            valueTitle: leftValueTitle,
            valueColumnWidth: valueColumnWidth,
            emptyTitle: leftEmptyTitle,
            emptyIcon: leftEmptyIcon,
            rows: leftRows,
            presentation: .preview
        ) { row, columnWidth in
            ModelPreviewRowView(row: row, valueColumnWidth: columnWidth)
        }
    }

    private var rightColumn: some View {
        ModelInsightSection(
            title: rightTitle,
            valueTitle: rightValueTitle,
            valueColumnWidth: valueColumnWidth,
            emptyTitle: rightEmptyTitle,
            emptyIcon: rightEmptyIcon,
            rows: rightRows,
            presentation: .preview
        ) { row, columnWidth in
            ModelPreviewRowView(row: row, valueColumnWidth: columnWidth)
        }
    }
}

private struct ModelPreviewRowView: View {
    let row: ModelPreviewRow
    let valueColumnWidth: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ModelProviderIcon(modelName: row.name, kind: row.kind, size: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(row.sessionCount) sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ModelInsightValueText(
                text: row.value,
                width: valueColumnWidth,
                minimumScaleFactor: 0.76
            )
        }
        .modelInsightRowStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        String(localized: "\(row.kind.localizedTitle), \(row.value), \(sessionCountText)")
    }

    private var sessionCountText: String {
        String(localized: "\(row.sessionCount) sessions")
    }
}

struct ModelInsightValueText: View {
    let text: String
    let width: CGFloat
    var minimumScaleFactor: CGFloat = 0.72

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(AppTheme.Text.primary)
            .lineLimit(1)
            .minimumScaleFactor(minimumScaleFactor)
            .frame(width: width, alignment: .trailing)
    }
}

enum ModelInsightRowLayout {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 10
}

extension View {
    func modelInsightRowStyle() -> some View {
        padding(.horizontal, ModelInsightRowLayout.horizontalPadding)
            .padding(.vertical, ModelInsightRowLayout.verticalPadding)
            .background(DashboardInsightRowBackground())
    }
}

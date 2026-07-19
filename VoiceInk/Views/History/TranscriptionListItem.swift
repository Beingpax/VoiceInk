import SwiftUI

struct TranscriptionListItem: View {
    let transcription: Transcription
    let isSelected: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleCheck: () -> Void
    var goldenEvalSplit: GoldenEvalSplit? = nil

    private var goldenEvalSplitLabel: String {
        switch goldenEvalSplit {
        case .control: return "Control"
        case .train: return "Train"
        case .eval: return "Eval"
        case nil: return ""
        }
    }

    private var goldenEvalSplitColor: Color {
        switch goldenEvalSplit {
        case .control: return AppTheme.Data.purple
        case .train: return AppTheme.Status.infoStrong
        case .eval, nil: return AppTheme.Status.positive
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle(
                "",
                isOn: Binding(
                    get: { isChecked },
                    set: { _ in onToggleCheck() }
                )
            )
            .toggleStyle(CircularCheckboxStyle())
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    if transcription.flagged {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.Status.warningStrong)
                    }
                    if let goldenEvalSplit {
                        Text(goldenEvalSplitLabel)
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(goldenEvalSplitColor))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    if transcription.duration > 0 {
                        Text(transcription.duration.formatTiming())
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(AppTheme.Surface.card)
                            )
                            .foregroundColor(.secondary)
                    }
                }

                Text(transcription.enhancedText ?? transcription.text)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(2)
                    .foregroundColor(.primary)
            }
        }
        .padding(10)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(AppTheme.Selection.fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .strokeBorder(AppTheme.Selection.border, lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(AppTheme.Surface.subtle)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .strokeBorder(AppTheme.Border.tint, lineWidth: 1)
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

struct CircularCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(configuration.isOn ? AppTheme.Selection.foreground : .secondary)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
    }
}

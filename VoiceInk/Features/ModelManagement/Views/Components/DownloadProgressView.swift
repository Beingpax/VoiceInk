import SwiftUI

struct DownloadProgressView: View {
    let modelName: String
    let downloadProgress: [String: Double]
    var isOptimizing = false

    private var mainProgress: Double {
        downloadProgress[modelName + "_main"] ?? 0
    }

    private var coreMLProgress: Double {
        supportsCoreML ? (downloadProgress[modelName + "_coreml"] ?? 0) : 0
    }

    private var supportsCoreML: Bool {
        !modelName.contains("q5") && !modelName.contains("q8")
    }

    private var totalProgress: Double {
        if isOptimizing {
            return 1
        }

        return supportsCoreML ? (mainProgress * 0.5) + (coreMLProgress * 0.5) : mainProgress
    }

    private var downloadPhase: String {
        if isOptimizing {
            return String(localized: "Optimizing model for your device")
        }

        if supportsCoreML && downloadProgress[modelName + "_coreml"] != nil {
            return String(format: String(localized: "Downloading Core ML Model for %@"), modelName)
        }
        return String(format: String(localized: "Downloading %@ Model"), modelName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(downloadPhase)
                    .lineLimit(1)

                Spacer()

                Text(totalProgress, format: .percent.precision(.fractionLength(0)))
                    .fontDesign(.monospaced)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color(.secondaryLabelColor))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.Border.control.opacity(0.3))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.Accent.primary)
                        .frame(width: max(0, min(geometry.size.width * totalProgress, geometry.size.width)), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
        .animation(.smooth, value: totalProgress)
    }
}

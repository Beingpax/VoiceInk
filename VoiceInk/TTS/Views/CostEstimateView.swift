import SwiftUI

struct CostEstimateView: View {
    @EnvironmentObject var viewModel: TTSViewModel

    var body: some View {
        let estimate = viewModel.costEstimate

        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "dollarsign.circle")
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(estimate.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let detail = estimate.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(viewModel.isMinimalistMode ? 8 : 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(viewModel.inputText.isEmpty ? 0.6 : 1.0))
        )
        .animation(.easeInOut(duration: 0.2), value: estimate.summary)
    }
}

struct CostEstimateView_Previews: PreviewProvider {
    static var previews: some View {
        CostEstimateView()
            .environmentObject(TTSViewModel())
            .padding()
            .frame(width: 600)
    }
}

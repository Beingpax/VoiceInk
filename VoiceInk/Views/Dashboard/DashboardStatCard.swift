import SwiftUI

struct DashboardStatCard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String?
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                DashboardIconGlyph(systemName: icon, color: color, size: 18, frameSize: 34)
                
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(AppCardBackground(cornerRadius: 16))
    }
}

struct DashboardIconGlyph: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 15
    var frameSize: CGFloat = 20

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color)
            .frame(width: frameSize, height: frameSize)
    }
}

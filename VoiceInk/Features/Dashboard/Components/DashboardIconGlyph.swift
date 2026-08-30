import SwiftUI

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

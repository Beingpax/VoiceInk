import SwiftUI
import MarkdownUI

struct MarkdownContentView: View {
    let text: String
    var fontSize: CGFloat
    var foregroundColor: Color
    var alignment: Alignment

    init(
        _ text: String,
        fontSize: CGFloat,
        foregroundColor: Color,
        alignment: Alignment = .leading
    ) {
        self.text = text
        self.fontSize = fontSize
        self.foregroundColor = foregroundColor
        self.alignment = alignment
    }

    var body: some View {
        Markdown(text)
            .markdownTheme(.basic)
            .markdownTextStyle {
                FontSize(fontSize)
                ForegroundColor(foregroundColor)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

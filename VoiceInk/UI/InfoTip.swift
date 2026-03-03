import SwiftUI

/// A reusable info tip component that displays helpful information in a popover
struct InfoTip: View {
    // Content configuration
    var message: String
    var learnMoreLink: URL?

    // Appearance customization
    var iconName: String = "info.circle.fill"
    var iconSize: Image.Scale = .medium
    var iconColor: Color = .primary
    var width: CGFloat = 280

    // State
    @State private var isShowingTip: Bool = false

    var body: some View {
        Image(systemName: iconName)
            .imageScale(iconSize)
            .foregroundColor(iconColor)
            .fontWeight(.semibold)
            .padding(5)
            .contentShape(Rectangle())
            .popover(isPresented: $isShowingTip) {
                VStack(alignment: .leading, spacing: 0) {
                    if let url = learnMoreLink {
                        Text(message + " ")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        +
                        Text("Learn more")
                            .font(.callout)
                            .foregroundColor(.accentColor)
                    } else {
                        Text(message)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .leading)
                .padding(14)
                .onTapGesture {
                    if let url = learnMoreLink {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .onTapGesture {
                isShowingTip.toggle()
            }
    }
}

// MARK: - Convenience initializers

extension InfoTip {
    /// Creates an InfoTip with just a message
    init(_ message: String) {
        self.message = message
        self.learnMoreLink = nil
    }

    /// Creates an InfoTip with a learn more link
    init(_ message: String, learnMoreURL: String) {
        self.message = message
        self.learnMoreLink = URL(string: learnMoreURL)
    }
}

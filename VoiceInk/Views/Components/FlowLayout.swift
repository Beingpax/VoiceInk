import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        computeLayout(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(maxWidth: bounds.width, subviews: subviews)
        for (index, (position, size)) in zip(result.positions, result.sizes).enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(size)
            )
        }
    }

    private func computeLayout(maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint], sizes: [CGSize]) {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            let width = min(size.width, maxWidth)
            let itemSize = CGSize(width: width, height: size.height)

            if x > 0, x + width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(itemSize)
            rowHeight = max(rowHeight, itemSize.height)
            x += width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (
            CGSize(width: maxWidth.isFinite ? maxWidth : maxX, height: y + rowHeight),
            positions,
            sizes
        )
    }
}

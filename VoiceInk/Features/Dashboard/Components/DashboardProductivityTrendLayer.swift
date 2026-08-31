import Foundation
import SwiftUI

struct DashboardProductivityTrendLayer: View {
    let points: [DashboardProductivityPoint]
    let guideIndices: [Int]
    let yAxisUpperBound: Int
    let horizontalSlotCount: Int
    let hoveredPointID: Date?

    private let lineTint = AppTheme.Accent.strong

    private var hasVisibleData: Bool {
        points.contains { $0.words > 0 }
    }

    var body: some View {
        GeometryReader { geometry in
            let renderedPoints = Self.renderedPoints(
                for: points,
                yAxisUpperBound: yAxisUpperBound,
                horizontalSlotCount: horizontalSlotCount,
                size: geometry.size
            )
            let guideAnchors = Self.guideAnchors(for: guideIndices, in: renderedPoints)

            ZStack(alignment: .topLeading) {
                if renderedPoints.count > 0 {
                    if hasVisibleData {
                        DashboardProductivityAreaFillShape(points: renderedPoints)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        lineTint.opacity(0.30),
                                        lineTint.opacity(0.10),
                                        lineTint.opacity(0.015),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        DashboardProductivityTrendLineShape(points: renderedPoints)
                            .stroke(
                                lineTint,
                                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                            )
                            .shadow(color: lineTint.opacity(0.12), radius: 2, y: 1)

                        ForEach(guideAnchors.dropLast()) { guide in
                            DashboardProductivityXAxisGuide(
                                height: geometry.size.height,
                                tint: lineTint
                            )
                            .position(x: guide.point.x, y: geometry.size.height / 2)
                        }

                        if let latestPoint = renderedPoints.last {
                            DashboardProductivityCurrentValueMarker(tint: lineTint)
                                .position(x: latestPoint.x, y: latestPoint.y)
                        }

                        if let hoveredIndex = points.firstIndex(where: { $0.id == hoveredPointID }),
                            renderedPoints.indices.contains(hoveredIndex)
                        {
                            let hoveredPoint = renderedPoints[hoveredIndex]

                            Rectangle()
                                .fill(AppTheme.Border.subtle.opacity(0.9))
                                .frame(width: 1, height: geometry.size.height)
                                .position(x: hoveredPoint.x, y: geometry.size.height / 2)

                            Circle()
                                .fill(lineTint)
                                .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 2)
                                .frame(width: 9, height: 9)
                                .position(x: hoveredPoint.x, y: hoveredPoint.y)
                        }
                    } else {
                        DashboardProductivityBaselineShape()
                            .stroke(
                                AppTheme.Text.secondary.opacity(0.22),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                    }
                }
            }
        }
    }

    private static func renderedPoints(
        for points: [DashboardProductivityPoint],
        yAxisUpperBound: Int,
        horizontalSlotCount: Int,
        size: CGSize
    ) -> [CGPoint] {
        guard !points.isEmpty, size.width > 0, size.height > 0 else {
            return []
        }

        let maximum = max(yAxisUpperBound, 1)
        let slotCount = max(horizontalSlotCount, points.count)
        let denominator = max(slotCount - 1, 1)

        return points.enumerated().map { index, point in
            let x =
                slotCount == 1
                ? size.width / 2
                : size.width * CGFloat(index) / CGFloat(denominator)
            let progress = min(max(CGFloat(point.words) / CGFloat(maximum), 0), 1)
            let y = size.height - (size.height * progress)

            return CGPoint(x: x, y: y)
        }
    }

    private static func guideAnchors(for indices: [Int], in renderedPoints: [CGPoint])
        -> [DashboardProductivityGuideAnchor]
    {
        indices.compactMap { index in
            guard renderedPoints.indices.contains(index) else {
                return nil
            }

            return DashboardProductivityGuideAnchor(index: index, point: renderedPoints[index])
        }
    }
}

private struct DashboardProductivityGuideAnchor: Identifiable {
    let index: Int
    let point: CGPoint

    var id: Int { index }
}

struct DashboardProductivityGrid: View {
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    Rectangle()
                        .fill(AppTheme.Border.subtle.opacity(index == 4 ? 0.90 : 0.42))
                        .frame(height: 1)

                    if index < 4 {
                        Spacer(minLength: 0)
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    Rectangle()
                        .fill(AppTheme.Border.subtle.opacity(index == 0 ? 0.40 : 0.30))
                        .frame(width: 1)

                    if index < 4 {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

private struct DashboardProductivityAreaFillShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else {
            return Path()
        }

        if points.count == 1 {
            let halfWidth = min(max(rect.width * 0.055, 10), 20)
            let left = max(rect.minX, first.x - halfWidth)
            let right = min(rect.maxX, first.x + halfWidth)

            var path = Path()
            path.move(to: CGPoint(x: left, y: rect.maxY))
            path.addCurve(
                to: first,
                control1: CGPoint(x: left, y: first.y),
                control2: CGPoint(x: first.x - halfWidth * 0.48, y: first.y)
            )
            path.addCurve(
                to: CGPoint(x: right, y: rect.maxY),
                control1: CGPoint(x: first.x + halfWidth * 0.48, y: first.y),
                control2: CGPoint(x: right, y: first.y)
            )
            path.closeSubpath()
            return path
        }

        var path = DashboardProductivityTrendLineShape(points: points).path(in: rect)
        if let last = points.last {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct DashboardProductivityTrendLineShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else {
            return Path()
        }

        var path = Path()
        path.move(to: first)

        guard points.count > 1 else {
            return path
        }

        let tangents = monotoneTangents(for: points)

        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let distance = next.x - current.x
            let control1 = CGPoint(
                x: current.x + distance / 3,
                y: current.y + tangents[index] * distance / 3
            )
            let control2 = CGPoint(
                x: next.x - distance / 3,
                y: next.y - tangents[index + 1] * distance / 3
            )

            path.addCurve(
                to: next,
                control1: control1,
                control2: control2
            )
        }

        return path
    }

    private func monotoneTangents(for points: [CGPoint]) -> [CGFloat] {
        guard points.count > 1 else {
            return Array(repeating: 0, count: points.count)
        }

        let slopes = (0..<(points.count - 1)).map { index -> CGFloat in
            let current = points[index]
            let next = points[index + 1]
            let distance = next.x - current.x

            guard abs(distance) > .ulpOfOne else {
                return 0
            }

            return (next.y - current.y) / distance
        }

        var tangents = Array(repeating: CGFloat(0), count: points.count)
        tangents[0] = slopes[0]
        tangents[points.count - 1] = slopes[slopes.count - 1]

        guard points.count > 2 else {
            return tangents
        }

        for index in 1..<(points.count - 1) {
            let previousSlope = slopes[index - 1]
            let nextSlope = slopes[index]

            if previousSlope == 0 || nextSlope == 0 || previousSlope * nextSlope < 0 {
                tangents[index] = 0
            } else {
                tangents[index] = (previousSlope + nextSlope) / 2
            }
        }

        for index in slopes.indices {
            let slope = slopes[index]

            if slope == 0 {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }

            let firstRatio = tangents[index] / slope
            let secondRatio = tangents[index + 1] / slope
            let sum = firstRatio * firstRatio + secondRatio * secondRatio

            if sum > 9 {
                let scale = 3 / sqrt(sum)
                tangents[index] = scale * firstRatio * slope
                tangents[index + 1] = scale * secondRatio * slope
            }
        }

        return tangents
    }
}

private struct DashboardProductivityBaselineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

private struct DashboardProductivityCurrentValueMarker: View {
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 10, height: 10)

            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)

            Circle()
                .stroke(tint.opacity(0.20), lineWidth: 3)
                .frame(width: 14, height: 14)
        }
        .shadow(color: tint.opacity(0.12), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}
private struct DashboardProductivityXAxisGuide: View {
    let height: CGFloat
    let tint: Color

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        tint.opacity(0.00),
                        tint.opacity(0.10),
                        tint.opacity(0.04),
                        tint.opacity(0.00),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: height)
            .accessibilityHidden(true)
    }
}

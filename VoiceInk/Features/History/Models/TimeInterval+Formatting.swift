import Foundation

extension TimeInterval {
    func formatTiming() -> String {
        if self < 1 {
            return String(format: "%.0fms", self * 1000)
        }
        if self < 60 {
            return String(format: "%.1fs", self)
        }
        let minutes = Int(self) / 60
        let seconds = truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.0fs", minutes, seconds)
    }
}

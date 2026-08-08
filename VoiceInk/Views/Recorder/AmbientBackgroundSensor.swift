import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Works out whether the ambient light is sitting on a light or dark background — by looking.
///
/// **Why the appearance setting was never going to do this.** `auto` resolved through the app's own
/// appearance, which is a preference about *VoiceInk's windows*. Wanting dark app chrome on a Light
/// Mode Mac is an entirely normal thing to want, and it says nothing at all about the white document
/// the light is drawn over. That combination — app forced dark, system light — put the mint green on
/// a white page and looked exactly like broken detection, because it was.
///
/// So this measures the real thing. The app already ships ScreenCaptureKit for context capture, so
/// when that permission is present there is no reason to guess: capture the display at thumbnail
/// size once per take, average the luminance of the band the light actually occupies, and answer
/// from that.
///
/// Three rules keep it honest:
///   * it never asks for permission. Prompting for Screen Recording to choose a colour would be a
///     wildly disproportionate trade, so without the grant it silently falls back.
///   * the fallback is the *system* appearance, not the app's. That is the better proxy, and it
///     alone fixes the case above.
///   * it samples the top band, not the whole screen. The light lives against the edges, and a dark
///     wallpaper behind a white document would otherwise outvote the thing being looked at.
@MainActor
@Observable
final class AmbientBackgroundSensor {
    /// Nil until something has been measured or inferred.
    private(set) var isLightBackground: Bool?

    /// Above this mean luminance the background counts as light.
    private let lightThreshold = 0.55
    /// Hysteresis. Once a scheme is chosen it takes a clear move past the other side to switch, so
    /// a mid-grey window cannot make the light flicker between palettes mid-take.
    private let hysteresis = 0.08
    /// Fraction of the display height sampled from the top. The crest and the caption both live in
    /// roughly this band.
    private let bandFraction = 0.22

    private var isSampling = false

    /// Falls back to the system appearance — deliberately not the app's, which is a preference
    /// about VoiceInk's own windows and has nothing to do with what is behind the light.
    static var systemPrefersLight: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() != "dark"
    }

    func reset() {
        isLightBackground = nil
    }

    /// Best answer available right now, without blocking on anything.
    var resolved: Bool {
        isLightBackground ?? Self.systemPrefersLight
    }

    /// Measures the background if it can. Safe to call on every take; does nothing when a sample is
    /// already in flight or the permission is absent.
    func sample() {
        guard !isSampling else { return }
        // Preflight only — never request. See the note above.
        guard CGPreflightScreenCaptureAccess() else {
            isLightBackground = nil
            return
        }

        isSampling = true
        Task { [weak self] in
            let measured = await Self.measureTopBandLuminance(
                bandFraction: self?.bandFraction ?? 0.22)
            guard let self else { return }
            self.isSampling = false
            guard let measured else { return }

            let current = self.isLightBackground
            // Hysteresis around the threshold, biased toward whatever is already showing.
            let threshold =
                switch current {
                case .some(true): self.lightThreshold - self.hysteresis
                case .some(false): self.lightThreshold + self.hysteresis
                case nil: self.lightThreshold
                }
            self.isLightBackground = measured > threshold
        }
    }

    /// Mean relative luminance of the top band of the active display, 0…1.
    private nonisolated static func measureTopBandLuminance(bandFraction: Double) async -> Double? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            // Thumbnail size. This is a luminance average, so resolution buys nothing and costs
            // real time — 64x40 is about 2,500 pixels to walk.
            configuration.width = 64
            configuration.height = 40
            configuration.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration)
            return meanLuminance(of: image, topFraction: bandFraction)
        } catch {
            return nil
        }
    }

    private nonisolated static func meanLuminance(of image: CGImage, topFraction: Double) -> Double?
    {
        let width = image.width
        let rows = max(1, Int(Double(image.height) * topFraction))
        guard width > 0, rows > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * rows * 4)
        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        // Draw the full image offset upward so only its top `rows` land in the context.
        context.draw(
            image,
            in: CGRect(
                x: 0, y: CGFloat(rows - image.height),
                width: CGFloat(width), height: CGFloat(image.height)))

        func linear(_ channel: UInt8) -> Double {
            let v = Double(channel) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }

        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total +=
                0.2126 * linear(pixels[index])
                + 0.7152 * linear(pixels[index + 1])
                + 0.0722 * linear(pixels[index + 2])
        }
        return total / Double(width * rows)
    }
}

import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Works out whether the ambient light is sitting on a light or dark background — by looking at
/// the window you are dictating into.
///
/// **Why not the app's appearance setting.** That was the first attempt and it was reading the
/// wrong variable: `@Environment(\.colorScheme)` inside the panel is *VoiceInk's own* appearance.
/// Wanting dark chrome for VoiceInk's windows on a Light Mode Mac is entirely normal and says
/// nothing about the white document the light is drawn over, which is how mint green ended up on a
/// white page.
///
/// **Why not the whole screen either.** Averaging the display mixes in wallpaper, menu bar and
/// whatever else is open. What matters is the thing being worked in: dictating into a dark editor
/// should give the dark scheme even on a bright desktop, and into a white document the light one
/// even on a dark desktop.
///
/// macOS does not expose another process's `NSAppearance`, so a window's theme cannot be asked for
/// directly. It can be *seen*, though — a dark-themed window renders dark pixels — and the app
/// already ships ScreenCaptureKit for context capture. So: find the frontmost app's largest
/// on-screen window, capture it at thumbnail size once per take, and average its luminance.
///
/// Four rules keep it honest:
///   * it never asks for permission. Prompting for Screen Recording to choose a colour would be a
///     wildly disproportionate trade, so without the grant it silently falls back.
///   * the fallback is the *system* appearance, not the app's — the better proxy of the two.
///   * VoiceInk's own windows are skipped. Measuring our own settings window would answer a
///     question nobody asked.
///   * hysteresis, so a window sitting near the midpoint cannot flip the palette mid-take.
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

        // Read on the main actor, then handed to the detached measurement.
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier

        isSampling = true
        Task { [weak self] in
            let measured = await Self.measureActiveWindowLuminance(
                frontmostPID: frontmostPID, ownPID: ownPID)
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

    /// Mean relative luminance of the window being worked in, 0…1. Falls back to the whole display
    /// when there is no usable window — dictating at the desktop, or into our own settings.
    private nonisolated static func measureActiveWindowLuminance(
        frontmostPID: pid_t?, ownPID: pid_t
    ) async -> Double? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)

            let filter: SCContentFilter
            if let window = activeWindow(in: content.windows, frontmostPID: frontmostPID, ownPID: ownPID) {
                filter = SCContentFilter(desktopIndependentWindow: window)
            } else if let display = content.displays.first {
                filter = SCContentFilter(display: display, excludingWindows: [])
            } else {
                return nil
            }

            let configuration = SCStreamConfiguration()
            // Thumbnail size. This is a luminance average, so resolution buys nothing and costs
            // real time — 64x40 is about 2,500 pixels to walk.
            configuration.width = 64
            configuration.height = 40
            configuration.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration)
            return meanLuminance(of: image)
        } catch {
            return nil
        }
    }

    /// The frontmost app's largest on-screen window. Largest rather than first because apps carry
    /// palettes, inspectors and toolbars that are on screen but are not what you are looking at.
    private nonisolated static func activeWindow(
        in windows: [SCWindow], frontmostPID: pid_t?, ownPID: pid_t
    ) -> SCWindow? {
        guard let frontmostPID, frontmostPID != ownPID else { return nil }

        return
            windows
            .filter { window in
                window.owningApplication?.processID == frontmostPID
                    && window.isOnScreen
                    && window.frame.width >= 240
                    && window.frame.height >= 160
            }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private nonisolated static func meanLuminance(of image: CGImage) -> Double? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.draw(
            image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

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
        return total / Double(width * height)
    }
}

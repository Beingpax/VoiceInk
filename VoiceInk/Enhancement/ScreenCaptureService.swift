import Foundation
import AppKit
import Vision
import ScreenCaptureKit

@MainActor
class ScreenCaptureService: ObservableObject {
    @Published var isCapturing = false
    @Published var lastCapturedText: String?

    private func findActiveWindow(in content: SCShareableContent) -> SCWindow? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if let frontmostPID,
           let window = content.windows.first(where: {
               $0.owningApplication?.processID == frontmostPID &&
               $0.owningApplication?.processID != currentPID &&
               $0.windowLayer == 0 &&
               $0.isOnScreen
           }) {
            return window
        }

        return content.windows.first {
            $0.owningApplication?.processID != currentPID &&
            $0.windowLayer == 0 &&
            $0.isOnScreen
        }
    }

    func captureAndExtractText() async -> String? {
        guard !isCapturing else { return nil }

        isCapturing = true
        defer {
            DispatchQueue.main.async { self.isCapturing = false }
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let window = findActiveWindow(in: content) else { return nil }

            let title = window.title ?? window.owningApplication?.applicationName ?? "Unknown"
            let appName = window.owningApplication?.applicationName ?? "Unknown"

            let filter = SCContentFilter(desktopIndependentWindow: window)

            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width) * 2
            configuration.height = Int(window.frame.height) * 2

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            var contextText = """
            Active Window: \(title)
            Application: \(appName)

            """

            let extractedText = await extractText(from: nsImage)
            if let extractedText, !extractedText.isEmpty {
                contextText += "Window Content:\n\(extractedText)"
            } else {
                contextText += "Window Content:\nNo text detected via OCR"
            }

            lastCapturedText = contextText
            return contextText

        } catch {
            return nil
        }
    }

    private func extractText(from image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let result: Result<String?, Error> = await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try requestHandler.perform([request])
                guard let observations = request.results else {
                    return .success(nil)
                }
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                return .success(text.isEmpty ? nil : text)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let text): return text
        case .failure: return nil
        }
    }
}

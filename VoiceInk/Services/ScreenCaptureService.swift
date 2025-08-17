import Foundation
import AppKit
import Vision
import os

class ScreenCaptureService: ObservableObject {
    @Published var isCapturing = false
    @Published var lastCapturedText: String?
    
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.VoiceInk",
        category: "aienhancement"
    )
    
    private func getActiveWindowInfo() -> (title: String, ownerName: String, windowID: CGWindowID)? {
        let windowListInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        
        // Find the frontmost window that isn't our own app
        if let frontWindow = windowListInfo.first(where: { info in
            let layer = info[kCGWindowLayer as String] as? Int32 ?? 0
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            // Exclude our own app and system UI elements
            return layer == 0 && ownerName != "VoiceInk" && !ownerName.contains("Dock") && !ownerName.contains("Menu Bar")
        }) {
            guard let windowID = frontWindow[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = frontWindow[kCGWindowOwnerName as String] as? String,
                  let title = frontWindow[kCGWindowName as String] as? String else {
                return nil
            }
            
            return (title: title, ownerName: ownerName, windowID: windowID)
        }
        
        return nil
    }
    
    func captureActiveWindow() -> NSImage? {
        guard let windowInfo = getActiveWindowInfo() else {
            logger.notice("❌ Failed to get window info for capture")
            return captureFullScreen()
        }
        
        // TODO: Replace deprecated CGWindowListCreateImage with ScreenCaptureKit
        // Capture the specific window
        /*
        let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowInfo.windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
        
        if let cgImage = cgImage {
            logger.notice("✅ Successfully captured window")
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } else {
            logger.notice("⚠️ Window-specific capture failed, trying full screen")
            return captureFullScreen()
        }
        */
        
        logger.notice("⚠️ Screen capture disabled - deprecated API")
        return nil
    }
    
    private func captureFullScreen() -> NSImage? {
        logger.notice("📺 Attempting full screen capture")
        
        // TODO: Replace deprecated CGWindowListCreateImage with ScreenCaptureKit
        /*
        if let screen = NSScreen.main {
            let rect = screen.frame
            let cgImage = CGWindowListCreateImage(
                rect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            )
            
            if let cgImage = cgImage {
                logger.notice("✅ Full screen capture successful")
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        */
        
        logger.notice("❌ Screen capture disabled - deprecated API")
        return nil
    }
    
    func extractText(from image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.notice("❌ Failed to convert NSImage to CGImage for text extraction")
            completion(nil)
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                self.logger.notice("❌ Text recognition error: \(error.localizedDescription, privacy: .public)")
                completion(nil)
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                self.logger.notice("❌ No text observations found")
                completion(nil)
                return
            }
            
            let text = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")
            
            if text.isEmpty {
                self.logger.notice("⚠️ Text extraction returned empty result")
                completion(nil)
            } else {
                self.logger.notice("✅ Text extraction successful, found \(text.count, privacy: .public) characters")
                completion(text)
            }
        }
        
        // Configure the recognition level
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        do {
            try requestHandler.perform([request])
        } catch {
            logger.notice("❌ Failed to perform text recognition: \(error.localizedDescription, privacy: .public)")
            completion(nil)
        }
    }
    
    func captureAndExtractText() async -> String? {
        guard !isCapturing else { 
            logger.notice("⚠️ Screen capture already in progress, skipping")
            return nil 
        }
        
        isCapturing = true
        defer { 
            DispatchQueue.main.async {
                self.isCapturing = false
            }
        }
        
        logger.notice("🎬 Starting screen capture")
        
        // Get window info
        guard let windowInfo = getActiveWindowInfo() else {
            logger.notice("❌ Failed to get window info")
            return nil
        }
        
        logger.notice("🎯 Found window: \(windowInfo.title, privacy: .public) (\(windowInfo.ownerName, privacy: .public))")
        
        // Start with window metadata
        var contextText = """
        Active Window: \(windowInfo.title)
        Application: \(windowInfo.ownerName)
        
        """
        
        // Capture and process window content
        if let capturedImage = captureActiveWindow() {
            let extractedText = await withCheckedContinuation({ continuation in
                extractText(from: capturedImage) { text in
                    continuation.resume(returning: text)
                }
            })
            
            if let extractedText = extractedText {
                contextText += "Window Content:\n\(extractedText)"
                logger.notice("✅ Captured text successfully")
                
                await MainActor.run {
                    self.lastCapturedText = contextText
                }
                
                return contextText
            }
        }
        
        logger.notice("❌ Capture attempt failed")
        return nil
    }
} 

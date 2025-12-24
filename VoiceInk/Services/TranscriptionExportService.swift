import Foundation
import AppKit
import SwiftData
import UniformTypeIdentifiers

/// Export format options for transcriptions
enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    case txt = "Plain Text"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        case .txt: return "txt"
        }
    }
    
    var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
        case .txt: return .plainText
        }
    }
    
    var defaultFilename: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        return "VoiceInk-transcriptions-\(timestamp).\(fileExtension)"
    }
}

/// Service for exporting transcriptions in multiple formats
class TranscriptionExportService {
    
    // MARK: - Public Export Methods
    
    /// Export transcriptions in the specified format with a save dialog
    func exportTranscriptions(_ transcriptions: [Transcription], format: ExportFormat) {
        guard !transcriptions.isEmpty else {
            showError("No transcriptions to export")
            return
        }
        
        do {
            let data: Data
            
            switch format {
            case .csv:
                let csvString = try generateCSV(for: transcriptions)
                guard let csvData = csvString.data(using: .utf8) else {
                    showError("Failed to encode CSV data")
                    return
                }
                data = csvData
                
            case .json:
                data = try generateJSON(for: transcriptions)
                
            case .txt:
                let textString = generatePlainText(for: transcriptions)
                guard let textData = textString.data(using: .utf8) else {
                    showError("Failed to encode text data")
                    return
                }
                data = textData
            }
            
            showSaveDialog(data: data, format: format)
            
        } catch {
            showError("Export failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - CSV Export
    
    private func generateCSV(for transcriptions: [Transcription]) throws -> String {
        var csvString = "Original Transcript,Enhanced Transcript,Enhancement Model,Prompt Name,Transcription Model,Power Mode,Enhancement Time,Transcription Time,Timestamp,Duration\n"
        
        for transcription in transcriptions {
            let originalText = escapeCSVString(transcription.text)
            let enhancedText = escapeCSVString(transcription.enhancedText ?? "")
            let enhancementModel = escapeCSVString(transcription.aiEnhancementModelName ?? "")
            let promptName = escapeCSVString(transcription.promptName ?? "")
            let transcriptionModel = escapeCSVString(transcription.transcriptionModelName ?? "")
            let powerMode = escapeCSVString(powerModeDisplay(name: transcription.powerModeName, emoji: transcription.powerModeEmoji))
            let enhancementTime = transcription.enhancementDuration ?? 0
            let transcriptionTime = transcription.transcriptionDuration ?? 0
            let timestamp = transcription.timestamp.ISO8601Format()
            let duration = transcription.duration
            
            let row = "\(originalText),\(enhancedText),\(enhancementModel),\(promptName),\(transcriptionModel),\(powerMode),\(enhancementTime),\(transcriptionTime),\(timestamp),\(duration)\n"
            csvString.append(row)
        }
        
        return csvString
    }
    
    private func escapeCSVString(_ string: String) -> String {
        let escapedString = string.replacingOccurrences(of: "\"", with: "\"\"")
        if escapedString.contains(",") || escapedString.contains("\n") || escapedString.contains("\"") {
            return "\"\(escapedString)\""
        }
        return escapedString
    }
    
    // MARK: - JSON Export
    
    private func generateJSON(for transcriptions: [Transcription]) throws -> Data {
        let exportData = transcriptions.map { transcription -> [String: Any] in
            var dict: [String: Any] = [
                "id": transcription.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: transcription.timestamp),
                "text": transcription.text,
                "duration": transcription.duration
            ]
            
            // Add optional fields only if they exist
            if let enhancedText = transcription.enhancedText, !enhancedText.isEmpty {
                dict["enhancedText"] = enhancedText
            }
            
            if let audioFileURL = transcription.audioFileURL {
                dict["audioFileURL"] = audioFileURL
            }
            
            if let transcriptionModelName = transcription.transcriptionModelName {
                dict["transcriptionModelName"] = transcriptionModelName
            }
            
            if let aiEnhancementModelName = transcription.aiEnhancementModelName {
                dict["aiEnhancementModelName"] = aiEnhancementModelName
            }
            
            if let promptName = transcription.promptName {
                dict["promptName"] = promptName
            }
            
            if let powerModeName = transcription.powerModeName {
                dict["powerModeName"] = powerModeName
            }
            
            if let powerModeEmoji = transcription.powerModeEmoji {
                dict["powerModeEmoji"] = powerModeEmoji
            }
            
            if let transcriptionDuration = transcription.transcriptionDuration {
                dict["transcriptionDuration"] = transcriptionDuration
            }
            
            if let enhancementDuration = transcription.enhancementDuration {
                dict["enhancementDuration"] = enhancementDuration
            }
            
            if let aiRequestSystemMessage = transcription.aiRequestSystemMessage, !aiRequestSystemMessage.isEmpty {
                dict["aiRequestSystemMessage"] = aiRequestSystemMessage
            }
            
            if let aiRequestUserMessage = transcription.aiRequestUserMessage, !aiRequestUserMessage.isEmpty {
                dict["aiRequestUserMessage"] = aiRequestUserMessage
            }
            
            return dict
        }
        
        let jsonObject: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "version": "1.0",
            "application": "VoiceInk",
            "transcriptionCount": transcriptions.count,
            "transcriptions": exportData
        ]
        
        return try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
    }
    
    // MARK: - Plain Text Export
    
    private func generatePlainText(for transcriptions: [Transcription]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        var output = "VoiceInk Transcriptions Export\n"
        output += "Export Date: \(dateFormatter.string(from: Date()))\n"
        output += "Total Transcriptions: \(transcriptions.count)\n"
        output += String(repeating: "=", count: 80) + "\n\n"
        
        for (index, transcription) in transcriptions.enumerated() {
            output += "[\(index + 1)] \(dateFormatter.string(from: transcription.timestamp))\n"
            
            // Add metadata
            if let model = transcription.transcriptionModelName {
                output += "Model: \(model)\n"
            }
            
            if let powerModeName = transcription.powerModeName {
                output += "Power Mode: "
                if let emoji = transcription.powerModeEmoji {
                    output += "\(emoji) "
                }
                output += "\(powerModeName)\n"
            }
            
            if let promptName = transcription.promptName {
                output += "Prompt: \(promptName)\n"
            }
            
            output += "Duration: \(formatDuration(transcription.duration))\n"
            
            if let transcriptionDuration = transcription.transcriptionDuration {
                output += "Transcription Time: \(formatDuration(transcriptionDuration))\n"
            }
            
            if let enhancementDuration = transcription.enhancementDuration {
                output += "Enhancement Time: \(formatDuration(enhancementDuration))\n"
            }
            
            output += "\n"
            
            // Add transcription text (prefer enhanced if available)
            if let enhancedText = transcription.enhancedText, !enhancedText.isEmpty {
                output += "Enhanced Text:\n"
                output += enhancedText
                output += "\n\nOriginal Text:\n"
                output += transcription.text
            } else {
                output += transcription.text
            }
            
            output += "\n\n" + String(repeating: "-", count: 80) + "\n\n"
        }
        
        return output
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        }
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }
        let minutes = Int(duration) / 60
        let seconds = duration.truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.1fs", minutes, seconds)
    }
    
    private func powerModeDisplay(name: String?, emoji: String?) -> String {
        switch (emoji?.trimmingCharacters(in: .whitespacesAndNewlines), name?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (.some(emojiValue), .some(nameValue)) where !emojiValue.isEmpty && !nameValue.isEmpty:
            return "\(emojiValue) \(nameValue)"
        case let (.some(emojiValue), _) where !emojiValue.isEmpty:
            return emojiValue
        case let (_, .some(nameValue)) where !nameValue.isEmpty:
            return nameValue
        default:
            return ""
        }
    }
    
    private func showSaveDialog(data: Data, format: ExportFormat) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format.contentType]
        savePanel.nameFieldStringValue = format.defaultFilename
        savePanel.canCreateDirectories = true
        
        savePanel.begin { result in
            guard result == .OK, let url = savePanel.url else { return }
            
            do {
                try data.write(to: url, options: .atomic)
                
                // Show success notification
                DispatchQueue.main.async {
                    NotificationManager.shared.showNotification(
                        title: "Export successful - Saved to \(url.lastPathComponent)",
                        type: .success
                    )
                }
            } catch {
                self.showError("Failed to save file: \(error.localizedDescription)")
            }
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async {
            NotificationManager.shared.showNotification(
                title: "Export failed: \(message)",
                type: .error
            )
        }
    }
}

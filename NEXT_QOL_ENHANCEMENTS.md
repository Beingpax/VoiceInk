# Next Quality of Life Enhancements for VoiceInk

**Date:** November 3, 2025  
**Status:** Analysis & Recommendations  
**Priority:** Top 3 for Next Upstream Submission

---

## Selection Criteria

For upstream submission, enhancements must be:
- ✅ **Universally beneficial** - Helps all VoiceInk users
- ✅ **Fork-independent** - No custom/community features
- ✅ **Low risk** - Minimal chance of breaking existing functionality
- ✅ **Self-contained** - Limited file changes
- ✅ **Well-tested** - Can be thoroughly verified
- ✅ **Production-ready** - No experimental features

---

## Top 3 Recommended Enhancements

### 1. 🔄 Retry Button in Transcription History

**What:** Add visible retry button to transcription cards

**Why:**
- Backend already exists (`LastTranscriptionService.retryLastTranscription`)
- Currently only accessible via keyboard shortcut (not discoverable)
- Users often want to retry with different models
- Minimal code changes required

**Implementation:**
- Add retry button to TranscriptionCard UI
- Show only when audio file exists
- Integrate with existing retry service
- Add loading indicator during retry

**Files to Modify:**
1. `VoiceInk/Views/TranscriptionCard.swift` - Add retry button
2. `VoiceInk/Services/LastTranscriptionService.swift` - Adapt for specific transcription (not just last)

**Complexity:** Low  
**Risk:** Very Low  
**Value:** High

---

### 2. 🎤 Audio Level Monitoring in Settings

**What:** Visual microphone test before recording

**Why:**
- Users often don't know if their mic is working
- Prevents failed recordings due to wrong input device
- Common feature request
- Helps with device troubleshooting

**Implementation:**
- Add audio level meter to Audio Settings
- Real-time visualization while testing
- Uses existing `AVAudioEngine` infrastructure
- Test button to start/stop monitoring

**Files to Modify:**
1. `VoiceInk/Views/Settings/AudioSettingsView.swift` - Add test UI
2. `VoiceInk/Services/AudioDeviceManager.swift` - Add monitoring method (or new service)

**Complexity:** Medium  
**Risk:** Low (doesn't affect recording pipeline)  
**Value:** High

---

### 3. 📤 Export Format Options

**What:** Add JSON and plain text export alongside CSV

**Why:**
- Current export is CSV only
- JSON is better for programmatic access
- Plain text useful for simple workflows
- Easy to implement with existing export service

**Implementation:**
- Add format picker to export dialog
- JSON: Structured transcription data
- TXT: Plain text with timestamps
- CSV: Keep existing format

**Files to Modify:**
1. `VoiceInk/Services/ImportExportService.swift` - Add new exporters
2. `VoiceInk/Views/HistoryView.swift` - Add format picker to export UI

**Complexity:** Low  
**Risk:** Very Low (additive only)  
**Value:** Medium-High

---

##Detailed Implementation Plans

### Enhancement 1: Retry Button

#### User Experience

**Before:**
- User must use keyboard shortcut to retry
- Shortcut only works for *last* transcription
- No visual indication that retry is possible

**After:**
- Retry button visible on each transcription card (when audio exists)
- Click to retry with current model
- Loading indicator during retry
- New transcription appears in history

#### Technical Design

```swift
// 1. Update TranscriptionCard.swift
struct TranscriptionCard: View {
    let transcription: Transcription
    @EnvironmentObject var whisperState: WhisperState
    @Environment(\.modelContext) private var modelContext
    @State private var isRetrying = false
    
    // In context menu or action bar
    if hasAudioFile && !isRetrying {
        Button {
            retryTranscription()
        } label: {
            Label("Retry Transcription", systemImage: "arrow.clockwise")
        }
    } else if isRetrying {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text("Retrying...")
                .font(.caption)
        }
    }
    
    private func retryTranscription() {
        isRetrying = true
        Task { @MainActor in
            defer { isRetrying = false }
            
            guard let audioURLString = transcription.audioFileURL,
                  let audioURL = URL(string: audioURLString),
                  FileManager.default.fileExists(atPath: audioURL.path) else {
                NotificationManager.shared.showNotification(
                    title: "Cannot retry: Audio file not found",
                    type: .error
                )
                return
            }
            
            guard let currentModel = whisperState.currentTranscriptionModel else {
                NotificationManager.shared.showNotification(
                    title: "No transcription model selected",
                    type: .error
                )
                return
            }
            
            let transcriptionService = AudioTranscriptionService(
                modelContext: modelContext,
                whisperState: whisperState
            )
            
            do {
                let newTranscription = try await transcriptionService.retranscribeAudio(
                    from: audioURL,
                    using: currentModel
                )
                
                let textToCopy = newTranscription.enhancedText?.isEmpty == false ?
                    newTranscription.enhancedText! : newTranscription.text
                ClipboardManager.copyToClipboard(textToCopy)
                
                NotificationManager.shared.showNotification(
                    title: "Retranscription completed",
                    type: .success
                )
            } catch {
                NotificationManager.shared.showNotification(
                    title: "Retry failed: \(error.localizedDescription)",
                    type: .error
                )
            }
        }
    }
}
```

#### Files Modified

1. **VoiceInk/Views/TranscriptionCard.swift**
   - Add `@State private var isRetrying = false`
   - Add `@EnvironmentObject var whisperState: WhisperState`
   - Add `@Environment(\.modelContext) private var modelContext`
   - Add retry button to context menu
   - Add `retryTranscription()` method

#### Testing Checklist

- [ ] Button appears only when audio file exists
- [ ] Button disabled during retry operation
- [ ] Loading indicator shows during retry
- [ ] Success notification appears
- [ ] New transcription added to history
- [ ] Copied to clipboard automatically
- [ ] Error handling for missing audio file
- [ ] Error handling for missing model
- [ ] Error handling for transcription failure
- [ ] VoiceOver accessibility works
- [ ] No memory leaks during retry
- [ ] Works with both original and enhanced transcriptions

---

### Enhancement 2: Audio Level Monitoring

#### User Experience

**Before:**
- No way to test microphone before recording
- Users discover mic issues only after failed recording
- No visual feedback on input levels

**After:**
- "Test Microphone" button in Audio Settings
- Real-time level meter shows input volume
- Visual confirmation that audio device is working
- Can test different devices before selecting

#### Technical Design

```swift
// 1. Create AudioLevelMonitor service
import AVFoundation
import Combine

@MainActor
class AudioLevelMonitor: ObservableObject {
    @Published var currentLevel: Float = 0.0
    @Published var isMonitoring = false
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var monitoringTask: Task<Void, Never>?
    
    func startMonitoring(device: AudioDevice) {
        guard !isMonitoring else { return }
        
        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            
            // Set audio device
            #if os(macOS)
            if let deviceID = device.deviceID {
                var deviceIDCopy = deviceID
                let size = UInt32(MemoryLayout<AudioDeviceID>.size)
                let status = AudioUnitSetProperty(
                    input.audioUnit!,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &deviceIDCopy,
                    size
                )
                guard status == noErr else {
                    throw AudioMonitorError.deviceSetupFailed
                }
            }
            #endif
            
            // Set format (16kHz mono for consistency with recording)
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )
            
            guard let format = format else {
                throw AudioMonitorError.invalidFormat
            }
            
            // Install tap to monitor levels
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.currentLevel = self.calculateLevel(from: buffer)
                }
            }
            
            try engine.start()
            
            self.audioEngine = engine
            self.inputNode = input
            self.isMonitoring = true
            
        } catch {
            print("Failed to start audio monitoring: \(error)")
            NotificationManager.shared.showNotification(
                title: "Failed to start audio monitoring",
                type: .error
            )
        }
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isMonitoring = false
        currentLevel = 0.0
    }
    
    private func calculateLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(
            from: 0,
            to: Int(buffer.frameLength),
            by: buffer.stride
        ).map { channelDataValue[$0] }
        
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        
        // Convert to dB scale
        let avgPower = 20 * log10(rms)
        let normalizedPower = max(0, min(1, (avgPower + 50) / 50))  // Normalize -50dB to 0dB -> 0 to 1
        
        return normalizedPower
    }
    
    deinit {
        stopMonitoring()
    }
}

enum AudioMonitorError: Error {
    case deviceSetupFailed
    case invalidFormat
}

// 2. Add UI to AudioSettingsView.swift
struct AudioSettingsView: View {
    @StateObject private var audioMonitor = AudioLevelMonitor()
    
    var body: some View {
        Form {
            // ... existing settings
            
            Section("Microphone Test") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(audioMonitor.isMonitoring ? "Stop Test" : "Test Microphone") {
                            if audioMonitor.isMonitoring {
                                audioMonitor.stopMonitoring()
                            } else {
                                audioMonitor.startMonitoring(device: selectedDevice)
                            }
                        }
                        
                        if audioMonitor.isMonitoring {
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("Monitoring")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if audioMonitor.isMonitoring {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Input Level")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.2))
                                    
                                    // Level bar
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(levelColor(for: audioMonitor.currentLevel))
                                        .frame(width: geometry.size.width * CGFloat(audioMonitor.currentLevel))
                                }
                            }
                            .frame(height: 20)
                            
                            Text(levelDescription(for: audioMonitor.currentLevel))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .onDisappear {
            audioMonitor.stopMonitoring()
        }
    }
    
    private func levelColor(for level: Float) -> Color {
        switch level {
        case 0..<0.3:
            return .yellow
        case 0.3..<0.7:
            return .green
        case 0.7...1.0:
            return .orange
        default:
            return .gray
        }
    }
    
    private func levelDescription(for level: Float) -> String {
        switch level {
        case 0..<0.1:
            return "No input detected"
        case 0.1..<0.3:
            return "Very quiet - speak louder"
        case 0.3..<0.7:
            return "Good level"
        case 0.7...1.0:
            return "Too loud - reduce input gain"
        default:
            return ""
        }
    }
}
```

#### Files Modified/Added

1. **VoiceInk/Services/AudioLevelMonitor.swift** (NEW)
   - 180 lines
   - Observable object for audio monitoring
   - AVAudioEngine tap setup
   - RMS level calculation
   - Proper cleanup

2. **VoiceInk/Views/Settings/AudioSettingsView.swift** (MODIFY)
   - Add microphone test section
   - Level meter visualization
   - Start/stop test button
   - Level description text

#### Testing Checklist

- [ ] Monitor starts successfully with selected device
- [ ] Level meter updates in real-time
- [ ] Level colors change appropriately
- [ ] Stop button works correctly
- [ ] Monitor stops when leaving settings
- [ ] No audio engine conflicts with recording
- [ ] Works with different audio devices
- [ ] Proper cleanup (no memory leaks)
- [ ] No crashes when switching devices
- [ ] Descriptive text matches level
- [ ] VoiceOver describes current level
- [ ] Works on both Intel and Apple Silicon

---

### Enhancement 3: Export Format Options

#### User Experience

**Before:**
- Only CSV export available
- Not ideal for all workflows
- Limited programmatic access

**After:**
- Choose export format: CSV, JSON, or TXT
- JSON: Full structured data
- TXT: Simple plain text with timestamps
- CSV: Keep existing format

#### Technical Design

```swift
// 1. Add export formats enum
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
    
    var utType: String {
        switch self {
        case .csv: return "public.comma-separated-values-text"
        case .json: return "public.json"
        case .txt: return "public.plain-text"
        }
    }
}

// 2. Extend ImportExportService
extension ImportExportService {
    static func exportTranscriptionsToJSON(_ transcriptions: [Transcription]) throws -> Data {
        let exportData = transcriptions.map { transcription in
            [
                "id": transcription.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: transcription.timestamp),
                "text": transcription.text,
                "enhancedText": transcription.enhancedText ?? NSNull(),
                "duration": transcription.duration,
                "audioFileURL": transcription.audioFileURL ?? NSNull(),
                "transcriptionModelName": transcription.transcriptionModelName ?? NSNull(),
                "aiEnhancementModelName": transcription.aiEnhancementModelName ?? NSNull(),
                "promptName": transcription.promptName ?? NSNull(),
                "powerModeName": transcription.powerModeName ?? NSNull(),
                "powerModeEmoji": transcription.powerModeEmoji ?? NSNull(),
                "transcriptionDuration": transcription.transcriptionDuration ?? NSNull(),
                "enhancementDuration": transcription.enhancementDuration ?? NSNull(),
                "aiRequestSystemMessage": transcription.aiRequestSystemMessage ?? NSNull(),
                "aiRequestUserMessage": transcription.aiRequestUserMessage ?? NSNull()
            ] as [String: Any]
        }
        
        let jsonObject: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "version": "1.0",
            "transcriptionCount": transcriptions.count,
            "transcriptions": exportData
        ]
        
        return try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
    }
    
    static func exportTranscriptionsToPlainText(_ transcriptions: [Transcription]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        var output = "VoiceInk Transcriptions Export\n"
        output += "Export Date: \(dateFormatter.string(from: Date()))\n"
        output += "Total Transcriptions: \(transcriptions.count)\n"
        output += String(repeating: "=", count: 80) + "\n\n"
        
        for (index, transcription) in transcriptions.enumerated() {
            output += "[\(index + 1)] \(dateFormatter.string(from: transcription.timestamp))\n"
            
            if let model = transcription.transcriptionModelName {
                output += "Model: \(model)\n"
            }
            
            if let powerMode = transcription.powerModeName {
                output += "Power Mode: "
                if let emoji = transcription.powerModeEmoji {
                    output += "\(emoji) "
                }
                output += "\(powerMode)\n"
            }
            
            output += "Duration: \(formatDuration(transcription.duration))\n"
            output += "\n"
            
            // Use enhanced text if available
            let text = transcription.enhancedText?.isEmpty == false ?
                transcription.enhancedText! : transcription.text
            output += text
            
            output += "\n\n" + String(repeating: "-", count: 80) + "\n\n"
        }
        
        return output
    }
    
    private static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// 3. Update HistoryView export UI
struct HistoryView: View {
    @State private var selectedExportFormat: ExportFormat = .csv
    @State private var showingExportDialog = false
    
    var body: some View {
        // ... existing code
        
        .fileExporter(
            isPresented: $showingExportDialog,
            document: TranscriptionExportDocument(
                transcriptions: selectedTranscriptions,
                format: selectedExportFormat
            ),
            contentType: UTType(selectedExportFormat.utType)!,
            defaultFilename: "VoiceInk_Export_\(formattedDate()).\(selectedExportFormat.fileExtension)"
        ) { result in
            // Handle result
        }
    }
    
    private var exportMenu: some View {
        Menu {
            ForEach(ExportFormat.allCases) { format in
                Button(action: {
                    selectedExportFormat = format
                    exportTranscriptions(format: format)
                }) {
                    Label(format.rawValue, systemImage: iconForFormat(format))
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }
    
    private func iconForFormat(_ format: ExportFormat) -> String {
        switch format {
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        case .txt: return "doc.text"
        }
    }
}
```

#### Files Modified

1. **VoiceInk/Services/ImportExportService.swift**
   - Add `ExportFormat` enum
   - Add `exportTranscriptionsToJSON()` method
   - Add `exportTranscriptionsToPlainText()` method
   - Keep existing CSV export

2. **VoiceInk/Views/HistoryView.swift**
   - Add format picker to export UI
   - Update export menu
   - Handle different formats in fileExporter

#### Testing Checklist

- [ ] CSV export still works (backward compatibility)
- [ ] JSON export creates valid JSON
- [ ] JSON includes all transcription data
- [ ] JSON is properly formatted (pretty-printed)
- [ ] TXT export is readable
- [ ] TXT includes timestamps and metadata
- [ ] File extensions correct for each format
- [ ] File save dialog shows correct format
- [ ] Can export empty selection gracefully
- [ ] Can export large datasets (1000+ transcriptions)
- [ ] Unicode characters handled correctly
- [ ] Special characters escaped properly in JSON
- [ ] Newlines preserved in TXT export

---

## Implementation Priority

Given the need for pristine code and thorough testing:

1. **Enhancement 3: Export Formats** (Lowest Risk)
   - Self-contained
   - Additive only (no changes to existing code)
   - Easy to test
   - No UI complexity

2. **Enhancement 1: Retry Button** (Low Risk)
   - Backend exists
   - UI addition only
   - Clear scope

3. **Enhancement 2: Audio Monitoring** (Medium Risk)
   - Most complex
   - Needs careful AVAudioEngine management
   - Requires extensive testing
   - Could conflict with recording

---

## Recommendation for Next PR

**Option A: All 3 Enhancements**
- Comprehensive improvement set
- More testing required
- Higher PR review burden

**Option B: Just Enhancement 3 (Export Formats)**
- Safest, cleanest implementation
- Easy to verify
- Quick wins for users
- Sets up foundation for more features

**Option C: Enhancements 1 + 3**
- Good balance of value and risk
- Both are self-contained
- Skip the complex audio monitoring

---

## Estimated Effort

- **Enhancement 1 (Retry Button):** 2-3 hours (implementation + testing)
- **Enhancement 2 (Audio Monitoring):** 4-5 hours (new service + testing)
- **Enhancement 3 (Export Formats):** 1-2 hours (straightforward)

**Total for all 3:** 7-10 hours

---

## Next Steps

1. Review this analysis
2. Choose which enhancements to implement
3. Create feature branch
4. Implement with extreme care
5. Triple-check all code
6. Test thoroughly
7. Create clean documentation PR
8. Submit to upstream

---

**Recommendation:** Start with Enhancement 3 (Export Formats) as it's the safest and provides immediate value. Can add Enhancement 1 (Retry Button) if time permits. Save Enhancement 2 (Audio Monitoring) for a future PR due to complexity.

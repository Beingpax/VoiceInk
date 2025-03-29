import SwiftData
import SwiftUI

struct ModelManagementView: View {
    @ObservedObject var whisperState: WhisperState
    @State private var modelToDelete: WhisperModel?
    @StateObject private var aiService = AIService()
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    @State private var isTestingConnection: Bool = false
    @State private var testConnectionResult: String? = nil
    @State private var isShowingEndpointInfo: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                serviceTypeSelectionSection
                defaultModelSection
                
                if whisperState.transcriptionServiceType == .local {
                    languageSelectionSection
                    availableModelsSection
                } else {
                    cloudServiceSection
                }
            }
            .padding(40)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .alert(item: $modelToDelete) { model in
            Alert(
                title: Text("Delete Model"),
                message: Text("Are you sure you want to delete the model '\(model.name)'?"),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await whisperState.deleteModel(model)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private var serviceTypeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcription Service")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Picker("Service Type", selection: $whisperState.transcriptionServiceType) {
                ForEach(TranscriptionServiceType.allCases) { serviceType in
                    Text(serviceType.description).tag(serviceType)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.vertical, 8)
            
            Text("Select which service to use for transcribing your audio")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }
    
    private var defaultModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Configuration")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if whisperState.transcriptionServiceType == .local {
                Text(whisperState.currentModel.flatMap { model in
                    PredefinedModels.models.first { $0.name == model.name }?.displayName
                } ?? "No model selected")
                    .font(.title2)
                    .fontWeight(.bold)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloud Transcription")
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }
    
    private var cloudServiceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cloud Transcription Settings")
                .font(.title3)
                .fontWeight(.semibold)
            
            // Cloud Model Selection
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Model")
                        .font(.headline)
                }
                // Custom model input
                TextField("Enter model name", text: $whisperState.cloudTranscriptionModelName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.vertical, 4)

                Text("Enter the AI model to use for transcription, document: https://platform.openai.com/docs/guides/speech-to-text#quickstart")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
            .padding(.vertical, 8)
            
            // API Key
            VStack(alignment: .leading, spacing: 10) {
                Text("API Key")
                    .font(.headline)
                
                SecureField("Enter API Key", text: $whisperState.cloudTranscriptionApiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Text("Enter the API key provided by your cloud transcription service provider.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
            .padding(.vertical, 8)
            
            // API Endpoint
            VStack(alignment: .leading, spacing: 10) {
                Text("API Endpoint")
                    .font(.headline)
                TextField("API Endpoint URL", text: $whisperState.cloudTranscriptionApiEndpoint)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Text("The URL endpoint for the cloud transcription API. document: https://platform.openai.com/docs/guides/speech-to-text#supported-languages")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
            .padding(.vertical, 8)
            
            // Test Connection Button
            Button(action: testCloudConnection) {
                if isTestingConnection {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Test Connection")
                }
            }
            .disabled(whisperState.cloudTranscriptionApiKey.isEmpty || whisperState.cloudTranscriptionApiEndpoint.isEmpty || isTestingConnection)
            .buttonStyle(GradientButtonStyle(isDownloaded: true, isCurrent: false))
            .frame(maxWidth: 200, alignment: .leading)
            .padding(.vertical, 8)
            
            if let result = testConnectionResult {
                Text(result)
                    .foregroundColor(result.contains("Success") ? .green : .red)
                    .font(.callout)
                    .padding(.vertical, 4)
            }
            
            languageSelectionSection
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }
    
    private var languageSelectionSection: some View {
        LanguageSelectionView(whisperState: whisperState, displayMode: .full)
    }
    
    private var availableModelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Available Models")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("(\(whisperState.predefinedModels.count))")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                
                Spacer()
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)], spacing: 16) {
                ForEach(whisperState.predefinedModels) { model in
                    modelCard(for: model)
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }
    
    private func modelCard(for model: PredefinedModel) -> some View {
        let isDownloaded = whisperState.availableModels.contains { $0.name == model.name }
        let isCurrent = whisperState.currentModel?.name == model.name
        
        return VStack(alignment: .leading, spacing: 12) {
            // Model name and details
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)
                    Text("\(model.size) • \(model.language)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                modelStatusBadge(isDownloaded: isDownloaded, isCurrent: isCurrent)
            }
            
            // Description
            Text(model.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            // Performance indicators
            HStack(spacing: 16) {
                performanceIndicator(label: "Speed", value: model.speed)
                performanceIndicator(label: "Accuracy", value: model.accuracy)
                ramUsageLabel(gb: model.ramUsage)
            }
            
            // Action buttons
            HStack {
                modelActionButton(isDownloaded: isDownloaded, isCurrent: isCurrent, model: model)
                
                if isDownloaded {
                    Menu {
                        Button(action: {
                            if let downloadedModel = whisperState.availableModels.first(where: { $0.name == model.name }) {
                                modelToDelete = downloadedModel
                            }
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button(action: {
                            if let downloadedModel = whisperState.availableModels.first(where: { $0.name == model.name }) {
                                NSWorkspace.shared.selectFile(downloadedModel.url.path, inFileViewerRootedAtPath: "")
                            }
                        }) {
                            Label("Show in Finder", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .frame(width: 30, height: 30)
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.9))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrent ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isCurrent ? 2 : 1)
        )
    }

    private func modelStatusBadge(isDownloaded: Bool, isCurrent: Bool) -> some View {
        Group {
            if isCurrent {
                Text("Default")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            } else if isDownloaded {
                Text("Downloaded")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.indigo)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }

    private func performanceIndicator(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 2) {
                ForEach(0..<5) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < Int(value * 5) ? performanceColor(value: value) : Color.secondary.opacity(0.2))
                        .frame(width: 16, height: 8)
                }
            }
            
            Text(String(format: "%.1f", value * 10))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func performanceColor(value: Double) -> Color {
        switch value {
        case 0.8...: return .green
        case 0.6..<0.8: return .yellow
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
    
    private func modelActionButton(isDownloaded: Bool, isCurrent: Bool, model: PredefinedModel) -> some View {
        Group {
            if isCurrent {
                Text("Default Model")
                    .foregroundColor(.white)
            } else if isDownloaded {
                Button("Set as Default") {
                    if let downloadedModel = whisperState.availableModels.first(where: { $0.name == model.name }) {
                        Task {
                            await whisperState.setDefaultModel(downloadedModel)
                        }
                    }
                }
                .foregroundColor(.white)
            } else if whisperState.downloadProgress[model.name] != nil {
                VStack {
                    ProgressView(value: whisperState.downloadProgress[model.name] ?? 0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .animation(.linear, value: whisperState.downloadProgress[model.name])
                    Text("\(Int((whisperState.downloadProgress[model.name] ?? 0) * 100))%")
                        .font(.caption)
                        .animation(.none)
                }
            } else {
                Button("Download Model") {
                    Task {
                        await whisperState.downloadModel(model)
                    }
                }
                .foregroundColor(.white)
            }
        }
        .buttonStyle(GradientButtonStyle(isDownloaded: isDownloaded, isCurrent: isCurrent))
        .frame(maxWidth: .infinity)
    }

    private func ramUsageLabel(gb: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RAM")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(formatRAMSize(gb))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
        }
    }

    private func formatRAMSize(_ gb: Double) -> String {
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%d MB", Int(gb * 1024))
        }
    }

    private func testCloudConnection() {
        // Reset previous test result
        testConnectionResult = nil
        
        // Basic emptiness checks
        guard !whisperState.cloudTranscriptionApiKey.isEmpty else {
            testConnectionResult = "Please enter an API key"
            return
        }
        
        guard !whisperState.cloudTranscriptionApiEndpoint.isEmpty else {
            testConnectionResult = "Please enter an API endpoint URL"
            return
        }
        
        // URL validation
        guard let url = URL(string: whisperState.cloudTranscriptionApiEndpoint) else {
            testConnectionResult = "Invalid API endpoint URL format"
            return
        }
        
        // Protocol validation
        guard url.scheme == "http" || url.scheme == "https" else {
            testConnectionResult = "API endpoint URL must start with http:// or https://"
            return
        }
        
        isTestingConnection = true
        
        Task {
            do {
                // Use the appropriate model name based on mode
                let modelName = whisperState.cloudTranscriptionModelName
                
                let service = try await whisperState.serviceFactory.createCloudService(
                    apiKey: whisperState.cloudTranscriptionApiKey,
                    endpoint: whisperState.cloudTranscriptionApiEndpoint
                )
                
                // Set the model name
                await service.setModel(modelName)
                
                // Set the appropriate language based on mode
                await service.setLanguage(whisperState.cloudTranscriptionLanguage)
                
                // Create a very small audio sample for testing and convert to WAV file
                let testSamples = [Float](repeating: 0.0, count: 1600) // 0.1 second at 16kHz
                
                // Create temporary WAV file
                let tempDirectory = FileManager.default.temporaryDirectory
                let tempFileURL = tempDirectory.appendingPathComponent("cloud_test_\(UUID().uuidString).wav")
                
                // Convert samples to WAV and write to temp file
                let wavData = try await convertSamplesToWavData(testSamples)
                try wavData.write(to: tempFileURL)
                
                // Set a timeout
                let task = Task {
                    // Use fullTranscribeFromURL instead of fullTranscribe
                    try await service.fullTranscribeFromURL(fileURL: tempFileURL)
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: tempFileURL)
                    await service.releaseResources()
                }
                
                // Wait with timeout
                let result = try await withThrowingTaskGroup(of: Bool.self) { group in
                    group.addTask {
                        _ = try await task.value
                        return true
                    }
                    
                    group.addTask {
                        try await Task.sleep(nanoseconds: 10000000000) // 10 seconds timeout
                        task.cancel()
                        // Make sure temp file is removed
                        try? FileManager.default.removeItem(at: tempFileURL)
                        return false
                    }
                    
                    return try await group.next() ?? false
                }
                
                await MainActor.run {
                    if result {
                        testConnectionResult = "Success! Connection to cloud service established."
                    } else {
                        testConnectionResult = "Connection timed out. Please check your settings."
                    }
                    isTestingConnection = false
                }
            } catch let error as CloudTranscriptionError {
                // Handle specific CloudTranscriptionError types
                await MainActor.run {
                    switch error {
                    case .emptyApiKey:
                        testConnectionResult = "Error: API key cannot be empty"
                    case .invalidEndpointURL:
                        testConnectionResult = "Error: Invalid API endpoint URL format"
                    case .authenticationFailed:
                        testConnectionResult = "Error: API key authentication failed"
                    case .rateLimitExceeded:
                        testConnectionResult = "Error: Rate limit exceeded"
                    case .serviceUnavailable:
                        testConnectionResult = "Error: Cloud service temporarily unavailable"
                    case .configurationError:
                        testConnectionResult = "Error: Service configuration error"
                    default:
                        testConnectionResult = "Error: \(error)"
                    }
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    testConnectionResult = "Error: \(error.localizedDescription)"
                    isTestingConnection = false
                }
            }
        }
    }
    
    /// Converts float samples to WAV format data
    /// - Parameter samples: Audio samples
    /// - Returns: WAV format data
    private func convertSamplesToWavData(_ samples: [Float]) async throws -> Data {
        // Create a memory buffer
        var data = Data()
        
        // WAV header (44 bytes)
        let fileSize = 36 + (samples.count * 2) // File size minus 8 bytes
        let sampleRate: UInt32 = 16000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(numChannels * bitsPerSample / 8)
        let blockAlign = numChannels * bitsPerSample / 8
        
        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // Chunk size
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // Format = PCM
        data.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        // data chunk
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(samples.count * 2).littleEndian) { Data($0) })
        
        // Sample data
        for sample in samples {
            let intValue = Int16(max(-32768, min(32767, sample * 32767)))
            data.append(withUnsafeBytes(of: intValue.littleEndian) { Data($0) })
        }
        
        return data
    }
}

struct GradientButtonStyle: ButtonStyle {
    let isDownloaded: Bool
    let isCurrent: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                Group {
                    if isCurrent {
                        LinearGradient(gradient: Gradient(colors: [Color.green, Color.green.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                    } else if isDownloaded {
                        LinearGradient(gradient: Gradient(colors: [Color.purple, Color.purple.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                    } else {
                        LinearGradient(gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                    }
                }
            )
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

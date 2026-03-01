import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import KeyboardShortcuts
import os

// MARK: - Recording State Machine
enum RecordingState: Equatable {
 case idle
 case starting
 case recording
 case transcribing
 case enhancing
 case busy
}

@MainActor
class WhisperState: NSObject, ObservableObject {
 @Published var recordingState: RecordingState = .idle
 @Published var isModelLoaded = false
 @Published var loadedLocalModel: WhisperModel?
 @Published var currentTranscriptionModel: (any TranscriptionModel)?
 @Published var isModelLoading = false
 @Published var availableModels: [WhisperModel] = []
 @Published var allAvailableModels: [any TranscriptionModel] = PredefinedModels.models
 @Published var clipboardMessage = ""
 @Published var miniRecorderError: String?
 @Published var shouldCancelRecording = false
 var partialTranscript: String = ""
 var currentSession: TranscriptionSession?
 private var modelCleanupTimer: Task<Void, Never>?
 var enhancementTask: Task<(String, TimeInterval, String?), Error>?
 var activeTranscriptionTask: Task<Void, Never>?


 @Published var recorderType: String = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini" {
 didSet {
 if isMiniRecorderVisible {
 if oldValue == "notch" {
 notchWindowManager?.hide()
 notchWindowManager = nil
 } else {
 miniWindowManager?.hide()
 miniWindowManager = nil
 }
 Task { @MainActor in
 try? await Task.sleep(nanoseconds: 50_000_000)
 showRecorderPanel()
 }
 }
 UserDefaults.standard.set(recorderType, forKey: "RecorderType")
 }
 }
 
 @Published var isMiniRecorderVisible = false {
 didSet {
 // Dispatch asynchronously to avoid "Publishing changes from within view updates" warning
 DispatchQueue.main.async { [self] in
 if isMiniRecorderVisible {
 showRecorderPanel()
 } else {
 hideRecorderPanel()
 }
 }
 }
 }
 
 var whisperContext: WhisperContext?
 let recorder = Recorder()
 var recordedFile: URL? = nil
 let whisperPrompt = WhisperPrompt()
 
 // Prompt detection service for trigger word handling
 private let promptDetectionService = PromptDetectionService()
 
 let modelContext: ModelContext
 
 internal var serviceRegistry: TranscriptionServiceRegistry!
 
 private var modelUrl: URL? {
 let possibleURLs = [
 Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "Models"),
 Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin"),
 Bundle.main.bundleURL.appendingPathComponent("Models/ggml-base.en.bin")
 ]
 
 for url in possibleURLs {
 if let url = url, FileManager.default.fileExists(atPath: url.path) {
 return url
 }
 }
 return nil
 }
 
 private enum LoadError: Error {
 case couldNotLocateModel
 }
 
 let modelsDirectory: URL
 let recordingsDirectory: URL
 let enhancementService: AIEnhancementService?
 var licenseViewModel: LicenseViewModel
 let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperState")
 var notchWindowManager: NotchWindowManager?
 var miniWindowManager: MiniWindowManager?
 
 // For model progress tracking
 @Published var downloadProgress: [String: Double] = [:]
 @Published var parakeetDownloadStates: [String: Bool] = [:]
 
 init(modelContext: ModelContext, enhancementService: AIEnhancementService? = nil) {
 self.modelContext = modelContext
 let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
 .appendingPathComponent("com.prakashjoshipax.VoiceInk")
 
 self.modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")
 self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")
 
 self.enhancementService = enhancementService
 self.licenseViewModel = LicenseViewModel()
 
 super.init()
 
 // Configure the session manager
 if let enhancementService = enhancementService {
 PowerModeSessionManager.shared.configure(whisperState: self, enhancementService: enhancementService)
 }

 // Initialize the transcription service registry
 self.serviceRegistry = TranscriptionServiceRegistry(whisperState: self, modelsDirectory: self.modelsDirectory)
 
 setupNotifications()
 createModelsDirectoryIfNeeded()
 createRecordingsDirectoryIfNeeded()
 loadAvailableModels()
 loadCurrentTranscriptionModel()
 refreshAllAvailableModels()
 }
 
 deinit {
 NotificationCenter.default.removeObserver(self)
 }
 
 private func createRecordingsDirectoryIfNeeded() {
 do {
 try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
 } catch {
 logger.error("Error creating recordings directory: \(error.localizedDescription, privacy: .public)")
 }
 }
 
 func toggleRecord(powerModeId: UUID? = nil) async {
 logger.notice("toggleRecord called – state=\(String(describing: self.recordingState), privacy: .public)")
 cancelScheduledModelCleanup()
 // Only allow toggle from .idle (start) or .recording (stop)
 guard recordingState == .idle || recordingState == .recording else {
 logger.notice("toggleRecord: ignored, state=\(String(describing: self.recordingState), privacy: .public)")
 return
 }
 if recordingState == .recording {
 partialTranscript = ""
 recordingState = .transcribing
 await recorder.stopRecording(restoreAudio: false)
 if let recordedFile {
 if !shouldCancelRecording {
 let audioAsset = AVURLAsset(url: recordedFile)
 let duration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))) ?? 0.0

 let transcription = Transcription(
 text: "",
 duration: duration,
 audioFileURL: recordedFile.absoluteString,
 transcriptionStatus: .pending
 )
 modelContext.insert(transcription)
 try? modelContext.save()
 NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)

 let task = Task { await self.transcribeAudio(on: transcription) }
 self.activeTranscriptionTask = task
 await task.value
 self.activeTranscriptionTask = nil
 } else {
 currentSession?.cancel()
 currentSession = nil
 try? FileManager.default.removeItem(at: recordedFile)
 recorder.restoreAudio()
 await MainActor.run {
 recordingState = .idle
 }
 scheduleModelCleanup()
 }
 } else {
 logger.error(" No recorded file found after stopping recording")
 currentSession?.cancel()
 currentSession = nil
 recorder.restoreAudio()
 await MainActor.run {
 recordingState = .idle
 }
 }
 } else {
 logger.notice("toggleRecord: entering start-recording branch")
 guard currentTranscriptionModel != nil else {
 await MainActor.run {
 NotificationManager.shared.showNotification(
 title: "No AI Model Selected",
 type: .error
 )
 }
 return
 }
 shouldCancelRecording = false
 partialTranscript = ""
 requestRecordPermission { [self] granted in
 if granted {
 Task {
 do {
 // --- Prepare permanent file URL ---
 let fileName = "\(UUID().uuidString).wav"
 let permanentURL = self.recordingsDirectory.appendingPathComponent(fileName)
 self.recordedFile = permanentURL

 // Buffer chunks from the start; session created after Power Mode resolves
 let pendingChunks = OSAllocatedUnfairLock(initialState: [Data]())
 self.recorder.onAudioChunk = { data in
 pendingChunks.withLock { $0.append(data) }
 }

 // Start recording immediately — no waiting for network
 try await self.recorder.startRecording(toOutputFile: permanentURL)

 await MainActor.run {
 self.recordingState = .recording
 }
 self.logger.notice("toggleRecord: recording started successfully, state=recording")

 // Power Mode resolves while recording runs (~50-200ms)
 await ActiveWindowService.shared.applyConfiguration(powerModeId: powerModeId)

 // Create session with the resolved model (skip if user already stopped)
 if self.recordingState == .recording, let model = self.currentTranscriptionModel {
 let session = self.serviceRegistry.createSession(for: model, onPartialTranscript: { [weak self] partial in
 Task { @MainActor in
 self?.partialTranscript = partial
 }
 })
 self.currentSession = session
 let realCallback = try await session.prepare(model: model)

 if let realCallback = realCallback {
 // Swap callback first so new chunks go straight to the session
 self.recorder.onAudioChunk = realCallback
 // Then flush anything that was buffered before the swap
 let buffered = pendingChunks.withLock { chunks -> [Data] in
 let result = chunks
 chunks.removeAll()
 return result
 }
 for chunk in buffered { realCallback(chunk) }
 } else {
 self.recorder.onAudioChunk = nil
 pendingChunks.withLock { $0.removeAll() }
 }
 }

 // Load model and capture context in background without blocking
 Task.detached { [weak self] in
 guard let self = self else { return }

 // Only load model if it's a local model and not already loaded
 if let model = await self.currentTranscriptionModel, model.provider == .local {
 if let localWhisperModel = await self.availableModels.first(where: { $0.name == model.name }),
 await self.whisperContext == nil {
 do {
 try await self.loadModel(localWhisperModel)
 } catch {
 await self.logger.error(" Model loading failed: \(error.localizedDescription, privacy: .public)")
 }
 }
 } else if let parakeetModel = await self.currentTranscriptionModel as? ParakeetModel {
 try? await self.serviceRegistry.parakeetTranscriptionService.loadModel(for: parakeetModel)
 }

 if let enhancementService = await self.enhancementService {
 async let clipboard: Void = MainActor.run {
 enhancementService.captureClipboardContext()
 }
 async let screen: Void = enhancementService.captureScreenContext()
 _ = await (clipboard, screen)
 }
 }

 } catch {
 self.logger.error(" Failed to start recording: \(error.localizedDescription, privacy: .public)")
 await NotificationManager.shared.showNotification(title: "Recording failed to start", type: .error)
 self.logger.notice("toggleRecord: calling dismissMiniRecorder from error handler")
 await self.dismissMiniRecorder()
 // Do not remove the file on a failed start, to preserve all recordings.
 self.recordedFile = nil
 }
 }
 } else {
 logger.error(" Recording permission denied.")
 }
 }
 }
 }
 
 private func requestRecordPermission(response: @escaping (Bool) -> Void) {
 response(true)
 }
 
 private func transcribeAudio(on transcription: Transcription) async {
 guard let urlString = transcription.audioFileURL, let url = URL(string: urlString) else {
 logger.error(" Invalid audio file URL in transcription object.")
 await MainActor.run {
 recordingState = .idle
 }
 transcription.text = "Transcription Failed: Invalid audio file URL"
 transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
 try? modelContext.save()
 return
 }

 if shouldCancelRecording {
 await MainActor.run {
 recordingState = .idle
 }
 scheduleModelCleanup()
 return
 }

 await MainActor.run {
 recordingState = .transcribing
 }

 // Play stop sound when transcription starts with a small delay
 Task {
 let isSystemMuteEnabled = UserDefaults.standard.bool(forKey: "isSystemMuteEnabled")
 if isSystemMuteEnabled {
 try? await Task.sleep(nanoseconds: 200_000_000) // 200 milliseconds delay
 }
 await MainActor.run {
 SoundManager.shared.playStopSound()
 }
 }

 defer {
 if shouldCancelRecording {
 Task {
 await self.scheduleModelCleanup()
 }
 }
 }

 logger.notice(" Starting transcription...")
 
 var finalPastedText: String?
 var promptDetectionResult: PromptDetectionService.PromptDetectionResult?

 do {
 guard let model = currentTranscriptionModel else {
 throw WhisperStateError.transcriptionFailed
 }

 let transcriptionStart = Date()
 var text: String
 if let session = currentSession {
 text = try await session.transcribe(audioURL: url)
 currentSession = nil
 } else {
 text = try await serviceRegistry.transcribe(audioURL: url, model: model)
 }
 logger.notice(" Transcript: \(text, privacy: .public)")
 text = TranscriptionOutputFilter.filter(text)
 logger.notice(" Output filter result: \(text, privacy: .public)")
 let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

 let powerModeManager = PowerModeManager.shared
 let activePowerModeConfig = powerModeManager.currentActiveConfiguration
 let powerModeName = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.name : nil
 let powerModeEmoji = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.emoji : nil

 if await checkCancellationAndCleanup() { return }

 text = text.trimmingCharacters(in: .whitespacesAndNewlines)

 if UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") {
 text = WhisperTextFormatter.format(text)
 logger.notice(" Formatted transcript: \(text, privacy: .public)")
 }

 text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
 logger.notice(" WordReplacement: \(text, privacy: .public)")

 let audioAsset = AVURLAsset(url: url)
 let actualDuration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))) ?? 0.0
 
 transcription.text = text
 transcription.duration = actualDuration
 transcription.transcriptionModelName = model.displayName
 transcription.transcriptionDuration = transcriptionDuration
 transcription.powerModeName = powerModeName
 transcription.powerModeEmoji = powerModeEmoji
 finalPastedText = text
 
 if let enhancementService = enhancementService, enhancementService.isConfigured {
 let detectionResult = await promptDetectionService.analyzeText(text, with: enhancementService)
 promptDetectionResult = detectionResult
 await promptDetectionService.applyDetectionResult(detectionResult, to: enhancementService)
 }

 if let enhancementService = enhancementService,
 enhancementService.isConfigured {
 let textForAI = promptDetectionResult?.processedText ?? text
 let formattedUserMessage = "\n<TRANSCRIPT>\n\(textForAI)\n</TRANSCRIPT>"

 // Determine effective mode: prompt detection forces synchronous enhancement
 let effectiveMode: EnhancementMode = if promptDetectionResult?.shouldEnableAI == true {
 .on
 } else {
 enhancementService.effectiveEnhancementMode
 }

 switch effectiveMode {
 case .on:
 if await checkCancellationAndCleanup() { return }

 await MainActor.run { self.recordingState = .enhancing }

 do {
 let task = Task {
 try await enhancementService.enhance(textForAI)
 }
 self.enhancementTask = task
 let (enhancedText, enhancementDuration, promptName) = try await task.value
 self.enhancementTask = nil
 logger.notice(" AI enhancement: \(enhancedText, privacy: .public)")
 transcription.enhancedText = enhancedText
 transcription.aiEnhancementModelName = enhancementService.getAIService()?.currentModel
 transcription.promptName = promptName
 transcription.enhancementDuration = enhancementDuration
 transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
 transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
 finalPastedText = enhancedText
 } catch is CancellationError {
 self.enhancementTask = nil
 transcription.enhancedText = nil
 if await checkCancellationAndCleanup() { return }
 } catch {
 self.enhancementTask = nil
 transcription.enhancedText = "Enhancement failed: \(error)"

 if await checkCancellationAndCleanup() { return }
 }

 case .background:
 // Snapshot system message before contexts are cleared by dismissMiniRecorder
 let systemMessage = await enhancementService.buildSystemMessageSnapshot()
 let job = BackgroundEnhancementJob(
 transcriptionId: transcription.id,
 text: textForAI,
 systemMessage: systemMessage,
 userMessage: formattedUserMessage,
 promptName: enhancementService.activePrompt?.title,
 aiModelName: enhancementService.getAIService()?.currentModel
 )
 EnhancementQueueService.shared.enqueue(job)
 // finalPastedText stays as raw text; pipeline proceeds immediately

 case .off:
 break
 }
 }

 transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue

 } catch is CancellationError {
 logger.notice("Transcription cancelled, cleaning up silently")
 modelContext.delete(transcription)
 try? modelContext.save()
 recorder.restoreAudio()
 await self.dismissMiniRecorder()
 scheduleModelCleanup()
 return
 } catch {
 let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
 let recoverySuggestion = (error as? LocalizedError)?.recoverySuggestion ?? ""
 let fullErrorText = recoverySuggestion.isEmpty ? errorDescription : "\(errorDescription) \(recoverySuggestion)"

 transcription.text = "Transcription Failed: \(fullErrorText)"
 transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
 }

 try? modelContext.save()

 NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)

 if await checkCancellationAndCleanup() { return }

 if var textToPaste = finalPastedText, transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue,
 !textToPaste.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
 if case .trialExpired = licenseViewModel.licenseState {
 textToPaste = """
 Your trial has expired. Upgrade to VoiceInk Pro at tryvoiceink.com/buy
 \n\(textToPaste)
 """
 }

 DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
 CursorPaster.pasteAtCursor(textToPaste + (CursorPaster.appendTrailingSpace ? " " : ""))

 let powerMode = PowerModeManager.shared
 if let activeConfig = powerMode.currentActiveConfiguration, activeConfig.isAutoSendEnabled {
 // Slight delay to ensure the paste operation completes
 DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
 CursorPaster.pressEnter()
 }
 }
 }

 // Restore audio after paste (and auto-send if applicable) completes
 let audioRestoreDelay: TimeInterval
 if let activeConfig = PowerModeManager.shared.currentActiveConfiguration, activeConfig.isAutoSendEnabled {
 audioRestoreDelay = 0.35
 } else {
 audioRestoreDelay = 0.15
 }
 DispatchQueue.main.asyncAfter(deadline: .now() + audioRestoreDelay) { [weak self] in
 self?.recorder.restoreAudio()
 }
 } else {
 // No text to paste -- restore audio immediately
 recorder.restoreAudio()
 }

 if let result = promptDetectionResult,
 let enhancementService = enhancementService,
 result.shouldEnableAI {
 await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
 }

 await self.dismissMiniRecorder()

 shouldCancelRecording = false
 }

 func getEnhancementService() -> AIEnhancementService? {
 return enhancementService
 }
 
 private func checkCancellationAndCleanup() async -> Bool {
 if shouldCancelRecording {
 recorder.restoreAudio()
 scheduleModelCleanup()
 return true
 }
 return false
 }

 private func cleanupAndDismiss() async {
 await dismissMiniRecorder()
 }

 func scheduleModelCleanup() {
 modelCleanupTimer?.cancel()
 modelCleanupTimer = Task {
 try? await Task.sleep(for: .seconds(60))
 guard !Task.isCancelled else { return }
 await cleanupModelResources()
 }
 }

 func cancelScheduledModelCleanup() {
 modelCleanupTimer?.cancel()
 modelCleanupTimer = nil
 }
}

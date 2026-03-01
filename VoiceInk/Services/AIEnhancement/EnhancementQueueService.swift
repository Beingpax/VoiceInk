import Foundation
import SwiftData
import os

struct BackgroundEnhancementJob {
    let transcriptionId: UUID
    let text: String
    let systemMessage: String
    let userMessage: String
    let promptName: String?
    let aiModelName: String?
}

class EnhancementQueueService {
    static let shared = EnhancementQueueService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "EnhancementQueue")
    private var aiService: AIService?
    private var modelContainer: ModelContainer?

    private struct QueueState {
        var jobs: [BackgroundEnhancementJob] = []
        var isProcessing = false
    }
    private let state = OSAllocatedUnfairLock(initialState: QueueState())

    private init() {}

    func configure(aiService: AIService, modelContainer: ModelContainer) {
        self.aiService = aiService
        self.modelContainer = modelContainer
    }

    func enqueue(_ job: BackgroundEnhancementJob) {
        let shouldStart = state.withLock { state -> Bool in
            state.jobs.append(job)
            if !state.isProcessing {
                state.isProcessing = true
                return true
            }
            return false
        }

        if shouldStart {
            Task.detached { [weak self] in
                await self?.processQueue()
            }
        }
    }

    private func processQueue() async {
        while true {
            let nextJob = state.withLock { state -> BackgroundEnhancementJob? in
                if state.jobs.isEmpty {
                    state.isProcessing = false
                    return nil
                }
                return state.jobs.removeFirst()
            }

            guard let job = nextJob else { return }
            await processJob(job)
        }
    }

    private func processJob(_ job: BackgroundEnhancementJob) async {
        guard let aiService = aiService, let modelContainer = modelContainer else {
            logger.error("EnhancementQueueService not configured")
            return
        }

        logger.notice("Starting background enhancement for transcription \(job.transcriptionId.uuidString, privacy: .public)")
        let startTime = Date()

        do {
            let result = try await AIEnhancementService.performEnhancementRequest(
                userMessage: job.userMessage,
                systemMessage: job.systemMessage,
                aiService: aiService,
                baseTimeout: 30
            )

            let duration = Date().timeIntervalSince(startTime)

            let context = ModelContext(modelContainer)
            let transcriptionId = job.transcriptionId
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate { $0.id == transcriptionId }
            )

            if let transcription = try context.fetch(descriptor).first {
                transcription.enhancedText = result
                transcription.enhancementDuration = duration
                transcription.aiEnhancementModelName = job.aiModelName
                transcription.promptName = job.promptName
                transcription.aiRequestSystemMessage = job.systemMessage
                transcription.aiRequestUserMessage = job.userMessage
                try context.save()

                logger.notice("Background enhancement completed for \(transcriptionId.uuidString, privacy: .public) in \(duration, privacy: .public)s")

                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .backgroundEnhancementCompleted,
                        object: nil,
                        userInfo: ["transcriptionId": transcriptionId]
                    )
                }
            } else {
                logger.warning("Transcription \(transcriptionId.uuidString, privacy: .public) not found for background enhancement update")
            }
        } catch {
            logger.error("Background enhancement failed for \(job.transcriptionId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

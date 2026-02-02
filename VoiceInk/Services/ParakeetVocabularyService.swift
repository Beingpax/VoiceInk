import Foundation
import FluidAudio
import SwiftData
import os.log

class ParakeetVocabularyService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ParakeetVocabulary")
    private let modelContext: ModelContext
    private var cachedCtcModels: CtcModels?
    private var cachedTokenizer: CtcTokenizer?
    private var lastConfiguredWordSet: Set<String>?
    private var notificationObserver: Any?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .vocabularyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lastConfiguredWordSet = nil
        }
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Configures vocabulary boosting on the AsrManager if CTC models are available and vocabulary words exist.
    func configureIfNeeded(on asrManager: AsrManager) async throws {
        let ctcDirectory = CtcModels.defaultCacheDirectory(for: .ctc110m)
        guard CtcModels.modelsExist(at: ctcDirectory) else { return }

        let currentWords = fetchVocabularyWords()
        guard !currentWords.isEmpty else {
            asrManager.disableVocabularyBoosting()
            lastConfiguredWordSet = nil
            return
        }

        let wordSet = Set(currentWords.map { $0.word })
        if wordSet == lastConfiguredWordSet { return }

        if cachedCtcModels == nil {
            cachedCtcModels = try await CtcModels.load(from: ctcDirectory)
        }

        guard let ctcModels = cachedCtcModels else { return }

        if cachedTokenizer == nil {
            cachedTokenizer = try await CtcTokenizer.load(from: ctcDirectory)
        }

        guard let tokenizer = cachedTokenizer else { return }

        let terms = currentWords.compactMap { word -> CustomVocabularyTerm? in
            let tokenIds = tokenizer.encode(word.word)
            guard !tokenIds.isEmpty else { return nil }
            return CustomVocabularyTerm(text: word.word, ctcTokenIds: tokenIds)
        }

        guard !terms.isEmpty else {
            asrManager.disableVocabularyBoosting()
            lastConfiguredWordSet = nil
            return
        }

        let vocabulary = CustomVocabularyContext(terms: terms)

        try await asrManager.configureVocabularyBoosting(
            vocabulary: vocabulary,
            ctcModels: ctcModels
        )
        lastConfiguredWordSet = wordSet
        logger.info("Vocabulary boosting configured with \(terms.count) terms")
    }

    func cleanup() {
        cachedCtcModels = nil
        cachedTokenizer = nil
        lastConfiguredWordSet = nil
    }

    private func fetchVocabularyWords() -> [VocabularyWord] {
        let descriptor = FetchDescriptor<VocabularyWord>(
            sortBy: [SortDescriptor(\VocabularyWord.word)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

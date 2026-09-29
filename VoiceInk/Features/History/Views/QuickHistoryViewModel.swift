import SwiftData
import SwiftUI

@MainActor
final class QuickHistoryViewModel: ObservableObject {
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var transcriptions: [Transcription] = []
    @Published var selectedID: UUID?
    @Published private(set) var keyboardSelectionID: UUID?
    @Published var isShowingDetail = false
    @Published var isShowingInfo = false
    @Published private(set) var isSearching = false

    private let modelContext: ModelContext
    private var searchTask: Task<Void, Never>?
    private let recentResultLimit = 30

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        reload()
    }

    var filteredTranscriptions: [Transcription] { transcriptions }

    var selectedTranscription: Transcription? {
        filteredTranscriptions.first { $0.id == selectedID }
    }

    func reload() {
        searchTask?.cancel()
        load(query: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func reload(selecting transcription: Transcription) {
        searchTask?.cancel()
        load(query: searchText.trimmingCharacters(in: .whitespacesAndNewlines), selecting: transcription.id)
    }

    func clearSearch() {
        searchText = ""
    }

    func transcriptionForPaste(preferredID: UUID? = nil) -> Transcription? {
        if isSearching {
            searchTask?.cancel()
            load(
                query: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                selecting: preferredID ?? selectedID
            )
        }

        if let preferredID {
            return filteredTranscriptions.first { $0.id == preferredID }
        }

        return selectedTranscription
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = true

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.load(query: query)
        }
    }

    private func load(query: String, selecting id: UUID? = nil) {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )

        descriptor.fetchLimit = recentResultLimit

        if !query.isEmpty {
            descriptor.predicate = #Predicate<Transcription> {
                $0.text.localizedStandardContains(query)
                    || ($0.enhancedText?.localizedStandardContains(query) ?? false)
            }
        }

        do {
            let results = try modelContext.fetch(descriptor)

            transcriptions = results
            if let id, results.contains(where: { $0.id == id }) {
                selectedID = id
                keyboardSelectionID = nil
            } else {
                selectFirstResult()
            }
        } catch {
            transcriptions = []
            selectedID = nil
        }
        isSearching = false
    }

    func moveSelection(by offset: Int) {
        let results = filteredTranscriptions
        guard !results.isEmpty else { return }
        guard let selectedID, let index = results.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = results.first?.id
            keyboardSelectionID = self.selectedID
            return
        }

        let nextIndex = min(max(index + offset, 0), results.count - 1)
        self.selectedID = results[nextIndex].id
        keyboardSelectionID = self.selectedID
    }

    private func selectFirstResult() {
        selectedID = filteredTranscriptions.first?.id
        keyboardSelectionID = nil
    }
}

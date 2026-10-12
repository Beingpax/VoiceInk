import SwiftUI

struct QuickHistoryView: View {
    @ObservedObject var viewModel: QuickHistoryViewModel
    let onPaste: (Transcription) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isSearchFocused: Bool

    private var hasSearchQuery: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isShowingDetail {
                detailView
            } else {
                historyView
            }
        }
        .frame(width: 680, height: 470)
        .background {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
            AppTheme.Surface.window.opacity(0.50)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .strokeBorder(AppTheme.Border.control.opacity(0.55), lineWidth: 1)
        }
        .onAppear {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onChange(of: viewModel.isShowingDetail) { _, isShowingDetail in
            isSearchFocused = !isShowingDetail
            if !isShowingDetail {
                viewModel.isShowingInfo = false
            }
        }
    }

    private var historyView: some View {
        QuickPanelScaffold {
            if viewModel.filteredTranscriptions.isEmpty {
                HistoryEmptyState(
                    hasSearchQuery: hasSearchQuery,
                    emptyMessage: "Your recent transcriptions will appear here."
                )
            } else {
                resultsList
            }
        } header: {
            searchHeader
        } footer: {
            keyboardHints
        }
    }

    private var searchHeader: some View {
        HistorySearchHeader(
            searchText: $viewModel.searchText,
            searchFocus: $isSearchFocused,
            isSearching: viewModel.isSearching
        ) {
            HistoryWindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            QuickPanelEscapeButton(help: "Dismiss", action: onDismiss)
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            HistoryList {
                ForEach(viewModel.filteredTranscriptions) { transcription in
                    HistoryTranscriptionRow(
                        transcription: transcription,
                        isSelected: viewModel.selectedID == transcription.id,
                        onSelect: { viewModel.selectedID = transcription.id },
                        onPaste: { onPaste(transcription) }
                    )
                    .id(transcription.id)
                }
            }
            .onChange(of: viewModel.keyboardSelectionID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let transcription = viewModel.selectedTranscription {
            TranscriptionDetailView(
                transcription: transcription,
                isInfoPresented: $viewModel.isShowingInfo,
                onBack: {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        viewModel.isShowingDetail = false
                    }
                },
                onTranscriptionUpdated: { viewModel.reload(selecting: $0) },
                presentation: .quickPanel,
                onPaste: { onPaste(transcription) }
            )
        }
    }

    private var keyboardHints: some View {
        HStack(spacing: 10) {
            HistoryCommandButton("Details", shortcut: "⌘↵") {
                if viewModel.selectedTranscription != nil {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        viewModel.isShowingDetail = true
                    }
                }
            }

            Spacer()

            HistoryCommandButton("Paste Text", shortcut: "↵") {
                if let transcription = viewModel.selectedTranscription {
                    onPaste(transcription)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: HistoryLayout.actionBarHeight)
    }
}

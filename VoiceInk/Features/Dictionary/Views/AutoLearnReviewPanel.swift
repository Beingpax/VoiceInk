import SwiftUI

struct AutoLearnReviewPanel: View {
    fileprivate enum ReviewComponent: Hashable {
        case replacement
        case vocabulary
    }

    let onClose: () -> Void

    @State private var proposals: [AutoLearnReviewProposal] = []
    @State private var selections: [UUID: Set<ReviewComponent>] = [:]
    @State private var isReviewing = false
    @State private var isApplying = false
    @State private var errorMessage: String?

    var body: some View {
        QuickPanelScaffold {
            reviewContent
        } header: {
            floatingHeader
        } footer: {
            footer
        }
        .task {
            await loadAndReview()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .autoLearnReviewProposalsDidChange)
        ) { _ in
            Task { await reloadProposals(selectNewItems: true) }
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        if proposals.isEmpty, !isReviewing {
            emptyState
        } else {
            reviewList
        }
    }

    private var floatingHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("Review Corrections")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.Text.primary)

                InfoTip(
                    message: "The arrow icon refers to Word Replacement. The book icon refers to Vocabulary.",
                    iconSize: .small,
                    iconColor: .secondary,
                    width: 320
                )
            }

            Spacer()

            AppIconButton(
                systemName: "xmark",
                help: "Close",
                size: 28,
                iconSize: 14,
                cornerRadius: AppTheme.Radius.control,
                action: onClose
            )
        }
        .padding(.horizontal, 20)
        .frame(height: QuickPanelMetrics.headerHeight)
    }

    private var reviewList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if isReviewing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Reviewing pending corrections…")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.Text.secondary)
                    }
                    .padding(.bottom, 2)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.Status.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                }

                ForEach(proposals) { proposal in
                    AutoLearnReviewProposalRow(
                        proposal: proposal,
                        selectedComponents: selections[proposal.id] ?? [],
                        isDisabled: isApplying,
                        onToggleAll: { isSelected in
                            selections[proposal.id] = isSelected
                                ? availableComponents(for: proposal)
                                : []
                        },
                        onToggleComponent: { component in
                            var selected = selections[proposal.id] ?? []
                            if selected.contains(component) {
                                selected.remove(component)
                            } else {
                                selected.insert(component)
                            }
                            selections[proposal.id] = selected
                        }
                    )
                }
            }
            .padding(16)
            .padding(.top, 68)
            .padding(.bottom, 58)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Corrections to Review", systemImage: "checkmark.circle")
        } description: {
            Text(errorMessage ?? "New manual-review suggestions will appear here.")
        }
        .padding(.top, 68)
        .padding(.bottom, 58)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            AppActionButton("Dismiss All", kind: .destructive) {
                dismiss(Set(proposals.map(\.id)))
            }
            .disabled(proposals.isEmpty || isApplying || isReviewing)

            Spacer()

            AppActionButton(applyButtonTitle, kind: .primary) {
                applySelections()
            }
            .disabled(selectedProposalCount == 0 || isApplying || isReviewing)
        }
        .padding(.horizontal, 20)
        .frame(height: QuickPanelMetrics.footerHeight)
    }

    private var applyButtonTitle: LocalizedStringKey {
        if !proposals.isEmpty, selectedProposalCount == proposals.count {
            return "Apply All (\(proposals.count))"
        }
        return "Apply Selected (\(selectedProposalCount))"
    }

    private var selectedProposalCount: Int {
        proposals.filter { !(selections[$0.id] ?? []).isEmpty }.count
    }

    @MainActor
    private func loadAndReview() async {
        isReviewing = true
        errorMessage = nil
        await reloadProposals(selectNewItems: true)
        await AutoLearnService.shared.preparePendingReviewForApproval()
        await reloadProposals(selectNewItems: true)
        isReviewing = false

        let pendingCount = (try? await AutoLearnService.shared.pendingReviewCount()) ?? 0
        if pendingCount > 0 {
            errorMessage = String(
                localized: "Some corrections could not be reviewed. Check the selected AI provider and try again."
            )
        }
    }

    @MainActor
    private func reloadProposals(selectNewItems: Bool) async {
        do {
            let loaded = try await AutoLearnService.shared.reviewProposals()
            let loadedIDs = Set(loaded.map(\.id))
            if selectNewItems {
                for proposal in loaded where selections[proposal.id] == nil {
                    selections[proposal.id] = availableComponents(for: proposal)
                }
            }
            selections = selections.filter { loadedIDs.contains($0.key) }
            proposals = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applySelections() {
        let reviewSelections = proposals.compactMap { proposal -> AutoLearnReviewSelection? in
            let selected = selections[proposal.id] ?? []
            guard !selected.isEmpty else { return nil }
            return AutoLearnReviewSelection(
                proposalID: proposal.id,
                includesReplacement: selected.contains(.replacement),
                includesVocabulary: selected.contains(.vocabulary)
            )
        }
        guard !reviewSelections.isEmpty else { return }
        Task { @MainActor in
            isApplying = true
            errorMessage = nil
            do {
                _ = try await AutoLearnService.shared.applyReviewProposals(reviewSelections)
                await reloadProposals(selectNewItems: false)
            } catch {
                errorMessage = error.localizedDescription
            }
            isApplying = false
        }
    }

    private func availableComponents(
        for proposal: AutoLearnReviewProposal
    ) -> Set<ReviewComponent> {
        var components = Set<ReviewComponent>()
        if proposal.addsReplacement {
            components.insert(.replacement)
        }
        if proposal.addsVocabulary {
            components.insert(.vocabulary)
        }
        return components
    }

    private func dismiss(_ proposalIDs: Set<UUID>) {
        guard !proposalIDs.isEmpty else { return }
        Task { @MainActor in
            isApplying = true
            errorMessage = nil
            do {
                try await AutoLearnService.shared.dismissReviewProposals(proposalIDs)
                await reloadProposals(selectNewItems: false)
            } catch {
                errorMessage = error.localizedDescription
            }
            isApplying = false
        }
    }
}

private struct AutoLearnReviewProposalRow: View {
    let proposal: AutoLearnReviewProposal
    let selectedComponents: Set<AutoLearnReviewPanel.ReviewComponent>
    let isDisabled: Bool
    let onToggleAll: (Bool) -> Void
    let onToggleComponent: (AutoLearnReviewPanel.ReviewComponent) -> Void

    var body: some View {
        HStack(spacing: 9) {
            Toggle(
                "Select correction",
                isOn: Binding(
                    get: { !selectedComponents.isEmpty },
                    set: onToggleAll
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .help(selectedComponents.isEmpty ? "Select correction" : "Deselect correction")
            .accessibilityLabel("Select correction")
            .accessibilityValue(selectedComponents.isEmpty ? "Not selected" : "Selected")

            correctionText
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(correctionSummary)

            HStack(spacing: 5) {
                if proposal.addsReplacement {
                    reviewButton(
                        "Word Replacement",
                        systemImage: "arrow.left.arrow.right",
                        component: .replacement
                    )
                }
                if proposal.addsVocabulary {
                    reviewButton(
                        "Vocabulary",
                        systemImage: "character.book.closed",
                        component: .vocabulary
                    )
                }
            }
        }
        .padding(10)
        .background(ProviderSurface(cornerRadius: 10))
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var correctionText: some View {
        if proposal.addsReplacement,
            let source = proposal.incorrectTextToReplace,
            let destination = proposal.correctedVocabularyTerm
        {
            HStack(spacing: 7) {
                Text(source)
                    .foregroundStyle(AppTheme.Text.secondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.Text.muted)
                Text(destination)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 13))
        } else if let term = proposal.correctedVocabularyTerm {
            Text(term)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private var correctionSummary: String {
        if proposal.addsReplacement,
            let source = proposal.incorrectTextToReplace,
            let destination = proposal.correctedVocabularyTerm
        {
            return "\(source) → \(destination)"
        }
        return proposal.correctedVocabularyTerm ?? proposal.correctedText
    }

    private func reviewButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        component: AutoLearnReviewPanel.ReviewComponent
    ) -> some View {
        let isSelected = selectedComponents.contains(component)
        return Button {
            onToggleComponent(component)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.Text.primary : AppTheme.Text.muted)
                .frame(width: 30, height: 26)
                .background(QuickPanelButtonBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .help(Text(title))
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

}

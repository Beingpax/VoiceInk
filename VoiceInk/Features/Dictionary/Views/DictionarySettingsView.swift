import SwiftUI

struct DictionarySettingsView: View {
    @State private var selectedSection: DictionarySection = .replacements
    @State private var isShowingSettings = false
    private let dictionaryInfoMessage: LocalizedStringKey =
        "Word Replacements run after transcription. Vocabulary is used with AI enhancement to better understand names, technical terms, and unique spellings in your transcript."

    enum DictionarySection: String, CaseIterable, Hashable {
        case replacements = "Word Replacements"
        case spellings = "Vocabulary"

        var description: String {
            switch self {
            case .spellings:
                return String(
                    localized:
                        "Vocabulary is used only with AI enhancement to preserve important names, technical terms, and unique spellings in the final output."
                )
            case .replacements:
                return String(
                    localized:
                        "Word Replacements run after transcription to replace misheard words, phrases, abbreviations, or boilerplate text."
                )
            }
        }

        var systemImage: String {
            switch self {
            case .spellings:
                return "character.book.closed"
            case .replacements:
                return "arrow.left.arrow.right"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    sectionSelector
                    selectedSectionForm
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 500)
        .sidePanel(isPresented: $isShowingSettings) {
            DictionarySettingsPanel {
                isShowingSettings = false
            }
        }
    }

    private var headerSection: some View {
        AppScreenHeader(title: "Dictionary", infoMessage: dictionaryInfoMessage) {
            settingsButton
        }
    }

    private var settingsButton: some View {
        AppIconButton(
            systemName: "gearshape.fill",
            help: "Dictionary Settings"
        ) {
            isShowingSettings.toggle()
        }
    }

    private var sectionSelector: some View {
        DictionarySectionSwitcher(selection: $selectedSection)
    }

    private var selectedSectionForm: some View {
        DictionaryGroupedSection {
            selectedSectionContent
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .spellings:
            VocabularyView()
        case .replacements:
            WordReplacementView()
        }
    }
}

private struct DictionaryGroupedSection<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(sectionBackground)
        .overlay(sectionBorder)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AppTheme.Surface.card)
    }

    private var sectionBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AppTheme.Border.control.opacity(0.16), lineWidth: 1)
    }
}

private struct DictionarySectionSwitcher: View {
    @Binding var selection: DictionarySettingsView.DictionarySection

    var body: some View {
        HStack(spacing: 10) {
            ForEach(DictionarySettingsView.DictionarySection.allCases, id: \.self) { section in
                DictionarySectionButton(
                    section: section,
                    isSelected: selection == section
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selection = section
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DictionarySectionButton: View {
    let section: DictionarySettingsView.DictionarySection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DictionarySectionButtonLabel(
                title: LocalizedStringKey(section.rawValue),
                icon: section.systemImage,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .help(section.description)
    }
}

private struct DictionarySectionButtonLabel: View {
    let title: LocalizedStringKey
    let icon: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
        }
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            AppCardBackground(isSelected: isSelected, cornerRadius: 22)
        )
        .contentShape(Rectangle())
    }
}

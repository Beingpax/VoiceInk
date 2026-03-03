import SwiftUI
import SwiftData

struct DictionarySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSection: DictionarySection = .replacements
    let whisperPrompt: WhisperPrompt
    
    enum DictionarySection: String, CaseIterable {
        case replacements = "Word Replacements"
        case spellings = "Vocabulary"
        
        var description: String {
            switch self {
            case .spellings:
                return "Add words to help VoiceInk recognize them properly"
            case .replacements:
                return "Automatically replace specific words/phrases with custom formatted text "
            }
        }
        
        var icon: String {
            switch self {
            case .spellings:
                return "character.book.closed.fill"
            case .replacements:
                return "arrow.2.squarepath"
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                mainContent
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var heroSection: some View {
        CompactHeroSection(
            icon: "brain.filled.head.profile",
            title: "Dictionary Settings",
            description: "Enhance VoiceInk's transcription accuracy by teaching it your vocabulary",
            maxDescriptionWidth: 500
        )
    }
    
    private var mainContent: some View {
        VStack(spacing: 40) {
            sectionSelector
            
            selectedSectionContent
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }
    
    private var sectionSelector: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Select Section")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: {
                        DictionaryImportExportService.shared.importDictionary(into: modelContext)
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Import vocabulary and word replacements")

                    Button(action: {
                        DictionaryImportExportService.shared.exportDictionary(from: modelContext)
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Export vocabulary and word replacements")
                }
            }

            HStack(spacing: 20) {
                ForEach(DictionarySection.allCases, id: \.self) { section in
                    SectionCard(
                        section: section,
                        isSelected: selectedSection == section,
                        action: { selectedSection = section }
                    )
                }
            }
        }
    }
    
    private var selectedSectionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch selectedSection {
            case .spellings:
                VocabularyView(whisperPrompt: whisperPrompt)
                    .background(CardBackground(isSelected: false))
            case .replacements:
                WordReplacementView()
                    .background(CardBackground(isSelected: false))
            }
        }
    }
}

struct SectionCard: View {
    let section: DictionarySettingsView.DictionarySection
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.rawValue)
                        .font(.headline)
                    
                    Text(section.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(CardBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
} 

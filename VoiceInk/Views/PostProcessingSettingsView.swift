import SwiftUI

struct PostProcessingSettingsView: View {
 @EnvironmentObject private var enhancementService: AIEnhancementService
 @State private var isVocabularyExtractionExpanded = false

 var body: some View {
  Form {
   Section {
    Toggle(isOn: $enhancementService.backgroundEnhancementEnabled) {
     HStack(spacing: 4) {
      Text("Post Processing")
      InfoTip(
       "Pastes raw text immediately and enhances in the background. Enhanced results appear in History."
      )
     }
    }
    .toggleStyle(.switch)
   } header: {
    Text("General")
   }

   Section {
    ExpandableSettingsRow(
     isExpanded: $isVocabularyExtractionExpanded,
     isEnabled: $enhancementService.vocabularyExtractionEnabled,
     label: "Vocabulary Extraction",
     infoMessage: "Analyzes AI corrections to detect new vocabulary and suggests additions to your dictionary."
    ) {
     Text("Compares your raw speech with AI-enhanced text to identify words that should be added to your custom dictionary for better transcription accuracy.")
      .font(.caption)
      .foregroundColor(.secondary)
    }
   } header: {
    Text("Features")
   }
   .opacity(enhancementService.backgroundEnhancementEnabled ? 1.0 : 0.5)
   .disabled(!enhancementService.backgroundEnhancementEnabled)
  }
  .formStyle(.grouped)
  .scrollContentBackground(.hidden)
  .background(Color(NSColor.controlBackgroundColor))
  .frame(minWidth: 500, minHeight: 400)
 }
}

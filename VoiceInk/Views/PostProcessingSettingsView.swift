import SwiftUI

struct PostProcessingSettingsView: View {
 @EnvironmentObject private var enhancementService: AIEnhancementService
 @AppStorage("autoGeneratePhoneticHints") private var autoGeneratePhoneticHints = false

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
    Toggle(isOn: $enhancementService.vocabularyExtractionEnabled) {
     HStack(spacing: 4) {
      Text("Vocabulary Extraction")
      InfoTip("Analyzes AI corrections to detect new vocabulary and suggests additions to your dictionary.")
     }
    }
    .toggleStyle(.switch)

    Toggle(isOn: $autoGeneratePhoneticHints) {
     HStack(spacing: 4) {
      Text("Auto-generate Phonetic Hints")
      InfoTip("Automatically discovers how Whisper mishears your vocabulary words and adds phonetic hints to improve future recognition.")
     }
    }
    .toggleStyle(.switch)
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

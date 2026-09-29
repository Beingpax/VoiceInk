import Foundation
import SwiftUI

/// Keeps the preset list while allowing hosted enhancement providers to use a new model ID.
struct EnhancementModelPicker: View {
    let title: LocalizedStringKey
    let provider: AIProvider
    let models: [String]
    let savedCustomModelID: String
    @Binding var draftModel: String

    @State private var isEditingCustomModel = false
    @State private var customModelDraft = ""

    private enum Option: Hashable {
        case preset(String)
        case custom
    }

    private var isCustomChoice: Bool {
        provider.supportsCustomModelID
            && (isEditingCustomModel || (!draftModel.isEmpty && !models.contains(draftModel)))
    }

    private var trimmedDraft: String {
        customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selection: Binding<Option> {
        Binding(
            get: {
                if isCustomChoice {
                    return .custom
                }
                return .preset(draftModel.isEmpty ? models.first ?? "" : draftModel)
            },
            set: { option in
                switch option {
                case .preset(let model):
                    isEditingCustomModel = false
                    draftModel = model
                case .custom:
                    customModelDraft = models.contains(draftModel) ? customModelDraft : draftModel
                    isEditingCustomModel = true
                    draftModel = trimmedDraft
                }
            }
        )
    }

    var body: some View {
        Group {
            Picker(title, selection: selection) {
                ForEach(models, id: \.self) { model in
                    Text(model).tag(Option.preset(model))
                }
                if provider.supportsCustomModelID {
                    Text("Custom…").tag(Option.custom)
                }
            }
            .onAppear(perform: syncCustomModelDraft)
            .onChange(of: provider) { _, _ in
                syncCustomModelDraft()
            }

            if isCustomChoice {
                TextField("Model ID", text: $customModelDraft)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customModelDraft) { _, newValue in
                        if isCustomChoice {
                            draftModel = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
            }
        }
    }

    private func syncCustomModelDraft() {
        isEditingCustomModel = provider.supportsCustomModelID
            && !draftModel.isEmpty && !models.contains(draftModel)
        customModelDraft = models.contains(draftModel) ? savedCustomModelID : draftModel
    }
}

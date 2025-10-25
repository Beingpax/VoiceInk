import SwiftUI

struct PronunciationGlossaryView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var isPresentingSheet = false
    @State private var ruleToEdit: PronunciationRule?

    var body: some View {
        VStack(alignment: .leading, spacing: viewModel.isMinimalistMode ? 8 : 12) {
            HStack {
                Label("Pronunciation Glossary", systemImage: "character.book.closed")
                    .font(.headline)

                Spacer()

                Button {
                    ruleToEdit = nil
                    isPresentingSheet = true
                } label: {
                    if viewModel.isMinimalistMode {
                        Image(systemName: "plus")
                            .imageScale(.large)
                            .accessibilityLabel("Add Rule")
                    } else {
                        Label("Add Rule", systemImage: "plus")
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if viewModel.pronunciationRules.isEmpty {
                Text("Define substitutions to improve pronunciation. Apply globally or per provider.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.pronunciationRules) { rule in
                    RuleRow(rule: rule, onEdit: {
                        ruleToEdit = rule
                        isPresentingSheet = true
                    })
                }
            }
        }
        .padding(viewModel.isMinimalistMode ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.pronunciationRules)
        .sheet(isPresented: $isPresentingSheet) {
            PronunciationRuleEditor(rule: $ruleToEdit)
                .environmentObject(viewModel)
        }
    }
}

private struct RuleRow: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let rule: PronunciationRule
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(rule.displayText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(rule.scope.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("→ \(rule.replacementText)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
                Button("Delete", role: .destructive) {
                    viewModel.removePronunciationRule(rule)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
        )
    }
}

private struct PronunciationRuleEditor: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var rule: PronunciationRule?

    @State private var displayText: String = ""
    @State private var replacement: String = ""
    @State private var scope: PronunciationScope = .global
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(rule == nil ? "Add Pronunciation Rule" : "Edit Pronunciation Rule")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Original text", text: $displayText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            TextField("Replacement", text: $replacement)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            Picker("Applies to", selection: bindingScope) {
                Text("All Providers").tag(PronunciationScope.global)
                ForEach(TTSProviderType.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(PronunciationScope.provider(provider))
                }
            }
            .pickerStyle(.menu)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(rule == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 280)
        .onAppear(perform: loadData)
    }

    private var bindingScope: Binding<PronunciationScope> {
        Binding {
            scope
        } set: { newValue in
            scope = newValue
        }
    }

    private func loadData() {
        if let rule {
            displayText = rule.displayText
            replacement = rule.replacementText
            scope = rule.scope
        }
    }

    private func save() {
        let trimmedOriginal = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedOriginal.isEmpty else {
            validationMessage = "Original text cannot be empty."
            return
        }

        guard !trimmedReplacement.isEmpty else {
            validationMessage = "Replacement cannot be empty."
            return
        }

        if var existingRule = rule {
            existingRule.displayText = trimmedOriginal
            existingRule.replacementText = trimmedReplacement
            existingRule.scope = scope
            viewModel.updatePronunciationRule(existingRule)
        } else {
            let newRule = PronunciationRule(displayText: trimmedOriginal, replacementText: trimmedReplacement, scope: scope)
            viewModel.addPronunciationRule(newRule)
        }

        dismiss()
    }
}

struct PronunciationGlossaryView_Previews: PreviewProvider {
    static var previews: some View {
        PronunciationGlossaryView()
            .environmentObject(TTSViewModel())
            .padding()
            .frame(width: 600)
    }
}

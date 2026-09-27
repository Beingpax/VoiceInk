import SwiftData
import SwiftUI

struct VocabularySectionEditor: View {
    let section: VocabularySection?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var sections: [VocabularySection]
    @State private var name: String
    @State private var sectionDescription: String
    @State private var errorMessage: String?

    init(section: VocabularySection?) {
        self.section = section
        _name = State(initialValue: section?.name ?? "")
        _sectionDescription = State(initialValue: section?.sectionDescription ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(section == nil ? "New vocabulary section" : "Edit vocabulary section")
                .font(.headline)

            TextField("Section name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 5) {
                Text("Description (optional)")
                    .font(.subheadline)
                TextField("When should these terms be used?", text: $sectionDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...3)
                Text("The description helps AI enhancement choose the right terms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    errorMessage = VocabularySectionService.save(
                        section,
                        name: name,
                        description: sectionDescription,
                        existing: sections,
                        context: modelContext
                    )
                    if errorMessage == nil { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 250)
        .alert("Section", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

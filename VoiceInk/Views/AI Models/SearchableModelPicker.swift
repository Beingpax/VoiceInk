import SwiftUI

/// A model picker that filters as you type, for provider lists too long to scroll.
struct SearchableModelPicker: View {
    let title: LocalizedStringKey
    let models: [String]
    @Binding var selection: String

    @State private var isPresented = false
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var matches: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return models }
        return models.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        LabeledContent(title) {
            Button {
                isPresented = true
            } label: {
                HStack(spacing: 6) {
                    Text(selection.isEmpty ? String(localized: "Select a model") : selection)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 320, alignment: .leading)
            }
            .buttonStyle(.bordered)
            // Anchored to the button itself, so widening the row below cannot drag the
            // popover's arrow away from the control.
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                popoverContent
            }
            // Model ids read left to right; the form's trailing alignment fights that.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search models"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit { commit(matches.first) }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            Divider()

            if matches.isEmpty {
                Text("No models match \u{201C}\(query)\u{201D}")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matches, id: \.self) { model in
                            row(for: model)
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 320)
        .multilineTextAlignment(.leading)
        .task {
            // The popover's window is not key when onAppear fires, so focus set there
            // is dropped. A hop past the presentation lets it stick.
            query = ""
            await Task.yield()
            isSearchFocused = true
        }
    }

    private func row(for model: String) -> some View {
        Button {
            commit(model)
        } label: {
            HStack(spacing: 8) {
                Text(model)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if model == selection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model == selection ? [.isSelected] : [])
    }

    private func commit(_ model: String?) {
        guard let model else { return }
        selection = model
        isPresented = false
    }
}

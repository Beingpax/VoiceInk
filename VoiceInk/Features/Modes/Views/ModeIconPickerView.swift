import SwiftUI

struct ModeIconView: View {
    let icon: ModeIcon
    var size: CGFloat = 18
    var color: Color = .primary

    var body: some View {
        Group {
            switch icon.kind {
            case .symbol:
                Image(systemName: icon.value)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(color)
            case .emoji:
                Text(icon.value)
                    .font(.system(size: size))
            }
        }
    }
}

struct ModeIconPickerView: View {
    @StateObject private var emojiManager = EmojiManager.shared
    @Binding var selectedIcon: ModeIcon
    @Binding var isPresented: Bool

    @State private var newEmojiText: String = ""
    @State private var isAddingCustomEmoji = false
    @FocusState private var isEmojiTextFieldFocused: Bool
    @State private var inputFeedbackMessage = ""

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    private var symbolOptions: [String] {
        ModeIcon.defaultSymbols
    }

    private var emojiOptions: [String] {
        var seen = Set<String>()
        var emojis: [String] = []

        for config in ModeManager.shared.configurations where config.icon.kind == .emoji {
            if seen.insert(config.icon.value).inserted {
                emojis.append(config.icon.value)
            }
        }

        for customEmoji in emojiManager.allEmojis where seen.insert(customEmoji).inserted {
            emojis.append(customEmoji)
        }

        if selectedIcon.kind == .emoji, seen.insert(selectedIcon.value).inserted {
            emojis.insert(selectedIcon.value, at: 0)
        }
        return emojis
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(symbolOptions, id: \.self) { symbol in
                        ModeIconButton(
                            icon: .symbol(symbol),
                            isSelected: selectedIcon == .symbol(symbol),
                            isRemovable: false,
                            removeAction: {}
                        ) {
                            selectedIcon = .symbol(symbol)
                            inputFeedbackMessage = ""
                            isPresented = false
                        }
                    }

                    ForEach(emojiOptions, id: \.self) { emoji in
                        ModeIconButton(
                            icon: .emoji(emoji),
                            isSelected: selectedIcon == .emoji(emoji),
                            isRemovable: canRemoveEmoji(emoji),
                            removeAction: {
                                removeCustomEmoji(emoji)
                            }
                        ) {
                            selectedIcon = .emoji(emoji)
                            inputFeedbackMessage = ""
                            isPresented = false
                        }
                    }

                    AddEmojiButton {
                        isAddingCustomEmoji.toggle()
                        newEmojiText = ""
                        inputFeedbackMessage = ""
                        if isAddingCustomEmoji {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isEmojiTextFieldFocused = true
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)

            if isAddingCustomEmoji {
                customEmojiEditor
            }
        }
        .padding()
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 340, minHeight: 170, idealHeight: 300, maxHeight: 380)
    }

    private var customEmojiEditor: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("+", text: $newEmojiText)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 70)
                    .focused($isEmojiTextFieldFocused)
                    .onChange(of: newEmojiText) { _, newValue in
                        inputFeedbackMessage = ""
                        let cleaned = newValue.firstValidEmojiCharacter()
                        if newEmojiText != cleaned {
                            newEmojiText = cleaned
                        }
                        if !newEmojiText.isEmpty && emojiManager.allEmojis.contains(newEmojiText) {
                            inputFeedbackMessage = String(localized: "Emoji already exists.")
                        } else if !newEmojiText.isEmpty && !newEmojiText.isValidEmoji {
                            inputFeedbackMessage = String(localized: "Invalid emoji.")
                        }
                    }
                    .onSubmit(attemptAddCustomEmoji)

                Button("Add") {
                    attemptAddCustomEmoji()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    newEmojiText.isEmpty || !newEmojiText.isValidEmoji || emojiManager.allEmojis.contains(newEmojiText))

                Button("Cancel") {
                    isAddingCustomEmoji = false
                    newEmojiText = ""
                    inputFeedbackMessage = ""
                }
                .buttonStyle(.bordered)
            }

            if !inputFeedbackMessage.isEmpty {
                Text(inputFeedbackMessage)
                    .font(.caption)
                    .foregroundColor(AppTheme.Status.error)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 5)
    }

    private func attemptAddCustomEmoji() {
        let trimmedEmoji = newEmojiText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmoji.isEmpty else {
            inputFeedbackMessage = String(localized: "Emoji cannot be empty.")
            return
        }
        guard trimmedEmoji.isValidEmoji else {
            inputFeedbackMessage = String(localized: "Invalid emoji.")
            return
        }
        guard !emojiManager.allEmojis.contains(trimmedEmoji) else {
            inputFeedbackMessage = String(localized: "Emoji already exists.")
            return
        }

        if emojiManager.addCustomEmoji(trimmedEmoji) {
            selectedIcon = .emoji(trimmedEmoji)
            inputFeedbackMessage = ""
            isAddingCustomEmoji = false
            newEmojiText = ""
            isPresented = false
        } else {
            inputFeedbackMessage = String(localized: "Could not add emoji.")
        }
    }

    private func canRemoveEmoji(_ emoji: String) -> Bool {
        emojiManager.isCustomEmoji(emoji) && !ModeManager.shared.isEmojiInUse(emoji)
    }

    private func removeCustomEmoji(_ emoji: String) {
        guard canRemoveEmoji(emoji) else { return }

        if emojiManager.removeCustomEmoji(emoji),
            selectedIcon == .emoji(emoji)
        {
            selectedIcon = .defaultIcon
        }
    }
}

private struct ModeIconButton: View {
    let icon: ModeIcon
    let isSelected: Bool
    let isRemovable: Bool
    let removeAction: () -> Void
    let selectAction: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: selectAction) {
                ModeIconView(icon: icon, size: icon.kind == .emoji ? 24 : 18, color: .primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? AppTheme.Accent.fill : AppTheme.Surface.control)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isSelected ? AppTheme.Accent.primary : Color.gray.opacity(0.25),
                                lineWidth: isSelected ? 2 : 1)
                    )
            }
            .buttonStyle(.plain)

            if isRemovable {
                Button(action: removeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, AppTheme.Status.error)
                        .font(.caption2)
                        .background(Circle().fill(Color.white.opacity(0.8)))
                }
                .buttonStyle(.borderless)
                .offset(x: 6, y: -6)
            }
        }
    }
}

private struct AddEmojiButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .strokeBorder(Color.gray.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Add custom emoji")
    }
}

extension String {
    var isValidEmoji: Bool {
        guard !isEmpty, count == 1, let char = first else { return false }
        let scalars = char.unicodeScalars
        if scalars.count > 1 {
            return scalars.contains { $0.properties.isEmoji }
        }
        return scalars.first?.properties.isEmojiPresentation == true
    }

    func firstValidEmojiCharacter() -> String {
        for char in self {
            if String(char).isValidEmoji {
                return String(char)
            }
        }
        return ""
    }
}

#if DEBUG
    struct ModeIconPickerView_Previews: PreviewProvider {
        static var previews: some View {
            ModeIconPickerView(
                selectedIcon: .constant(.defaultIcon),
                isPresented: .constant(true)
            )
            .environmentObject(EmojiManager.shared)
        }
    }
#endif

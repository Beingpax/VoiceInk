import SwiftUI

class WordReplacementManager: ObservableObject {
    @Published var replacements: [String: String] = UserDefaults.standard.wordReplacements {
        didSet {
            UserDefaults.standard.wordReplacements = replacements
        }
    }
    
    @Published var isEnabled: Bool = UserDefaults.standard.isWordReplacementEnabled {
        didSet {
            UserDefaults.standard.isWordReplacementEnabled = isEnabled
        }
    }
    
    init() {}
    
    func addReplacement(original: String, replacement: String) {
        replacements[original] = replacement
    }
    
    func removeReplacement(original: String) {
        replacements.removeValue(forKey: original)
    }
}

struct WordReplacementView: View {
    @StateObject private var manager = WordReplacementManager()
    @State private var showAddReplacementModal = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Info Section with Toggle
            GroupBox {
                HStack {
                    Label {
                        Text("Define word replacements to automatically replace specific words or phrases")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(alignment: .leading)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Toggle("Enable", isOn: $manager.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help("Enable automatic word replacement after transcription")
                }
            }
            
            VStack(spacing: 0) {
                // Header with action button
                HStack {
                    Text("Word Replacements")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: { showAddReplacementModal = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add new replacement")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))
                
                Divider()
                
                // Content
                if manager.replacements.isEmpty {
                    EmptyStateView(showAddModal: $showAddReplacementModal)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(manager.replacements.keys.sorted()), id: \.self) { original in
                                ReplacementRow(
                                    original: original,
                                    replacement: manager.replacements[original] ?? "",
                                    onDelete: { manager.removeReplacement(original: original) }
                                )
                                
                                if original != manager.replacements.keys.sorted().last {
                                    Divider()
                                        .padding(.leading, 32)
                                }
                            }
                        }
                        .background(Color(.controlBackgroundColor))
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showAddReplacementModal) {
            AddReplacementSheet(manager: manager)
        }
    }
}

struct EmptyStateView: View {
    @Binding var showAddModal: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.word.spacing")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text("No Replacements")
                .font(.headline)
            
            Text("Add word replacements to automatically replace text during AI enhancement.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
            
            Button("Add Replacement") {
                showAddModal = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AddReplacementSheet: View {
    @ObservedObject var manager: WordReplacementManager
    @Environment(\.dismiss) private var dismiss
    @State private var originalWord = ""
    @State private var replacementWord = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Text("Add Word Replacement")
                    .font(.headline)
                
                Spacer()
                
                Button("Add") {
                    addReplacement()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(originalWord.isEmpty || replacementWord.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.windowBackgroundColor).opacity(0.4))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Description
                    Text("Define a word or phrase to be automatically replaced during AI enhancement.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    // Form Content
                    VStack(spacing: 16) {
                        // Original Text Section
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Original Text")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            TextField("Enter word or phrase to replace", text: $originalWord)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                        }
                        .padding(.horizontal)
                        
                        // Replacement Text Section
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Replacement Text")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            TextEditor(text: $replacementWord)
                                .font(.body)
                                .frame(height: 100)
                                .padding(8)
                                .background(Color(.textBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(.separatorColor), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Example Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Example")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Original:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("my website link")
                                    .font(.callout)
                            }
                            
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Replacement:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("https://tryvoiceink.com")
                                    .font(.callout)
                            }
                        }
                        .padding(12)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.vertical)
            }
        }
        .frame(width: 460, height: 480)
    }
    
    private func addReplacement() {
        let trimmedOriginal = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacementWord.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedOriginal.isEmpty && !trimmedReplacement.isEmpty else { return }
        
        manager.addReplacement(original: trimmedOriginal, replacement: trimmedReplacement)
        dismiss()
    }
}

struct ReplacementRow: View {
    let original: String
    let replacement: String
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Original Text Container
            HStack {
                Text(original)
                    .font(.body)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
            }
            .frame(maxWidth: .infinity)
            
            // Arrow
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            
            // Replacement Text Container
            HStack {
                Text(replacement)
                    .font(.body)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
            }
            .frame(maxWidth: .infinity)
            
            // Delete Button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .help("Remove replacement")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(Color(.controlBackgroundColor))
    }
}

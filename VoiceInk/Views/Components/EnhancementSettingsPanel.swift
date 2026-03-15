import SwiftUI

struct EnhancementSettingsPanel: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @AppStorage("SkipShortEnhancement") private var isSkipShortEnhancementEnabled = false
    @AppStorage("ShortEnhancementWordThreshold") private var shortEnhancementWordThreshold = 5
    @State private var isShortEnhancementExpanded = false
    @State private var isHandlingToggleChange = false

    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("Enhancement Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Divider().opacity(0.5), alignment: .bottom
            )

            // Content
            Form {
                Section {
                    Toggle(isOn: $enhancementService.useClipboardContext) {
                        HStack(spacing: 4) {
                            Text("Clipboard Context")
                            InfoTip("Use clipboard text to understand context for better enhancement.")
                        }
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: $enhancementService.useScreenCaptureContext) {
                        HStack(spacing: 4) {
                            Text("Screen Context")
                            InfoTip("Capture on-screen text to understand context for better enhancement.")
                        }
                    }
                    .toggleStyle(.switch)
                } header: {
                    Text("Context")
                }

                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { isSkipShortEnhancementEnabled },
                                set: { newValue in
                                    isHandlingToggleChange = true
                                    isSkipShortEnhancementEnabled = newValue
                                    if newValue {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isShortEnhancementExpanded = true
                                        }
                                    } else {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isShortEnhancementExpanded = false
                                        }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        isHandlingToggleChange = false
                                    }
                                }
                            )) {
                                HStack(spacing: 4) {
                                    Text("Skip short transcriptions")
                                    InfoTip("Automatically skip AI enhancement when the transcription has very few words. Short phrases like \"yes\", \"thank you\", or quick commands don't benefit from enhancement.")
                                }
                            }
                            .toggleStyle(.switch)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(isSkipShortEnhancementEnabled && isShortEnhancementExpanded ? 90 : 0))
                                .opacity(isSkipShortEnhancementEnabled ? 1 : 0.4)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isHandlingToggleChange else { return }
                            if isSkipShortEnhancementEnabled {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShortEnhancementExpanded.toggle()
                                }
                            }
                        }

                        if isSkipShortEnhancementEnabled && isShortEnhancementExpanded {
                            Picker("Minimum words", selection: $shortEnhancementWordThreshold) {
                                ForEach(1...15, id: \.self) { count in
                                    Text("\(count) \(count == 1 ? "word" : "words")").tag(count)
                                }
                            }
                            .padding(.top, 12)
                            .padding(.leading, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isShortEnhancementExpanded)
                }

                Section {
                    EnhancementShortcutsView()
                } header: {
                    Text("Shortcuts")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}

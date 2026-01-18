import SwiftUI

enum ExpandableSection: Hashable {
    case soundFeedback
    case systemMute
    case pauseMedia
    case clipboardRestore
    case customCancel
    case middleClick
    case autoSwitchKeyboard
}

struct ExpandableToggleSection<Content: View>: View {
    let section: ExpandableSection
    let title: String
    let helpText: String
    @Binding var isEnabled: Bool
    @Binding var expandedSections: Set<ExpandableSection>
    let content: Content

    init(
        section: ExpandableSection,
        title: String,
        helpText: String,
        isEnabled: Binding<Bool>,
        expandedSections: Binding<Set<ExpandableSection>>,
        @ViewBuilder content: () -> Content
    ) {
        self.section = section
        self.title = title
        self.helpText = helpText
        self._isEnabled = isEnabled
        self._expandedSections = expandedSections
        self.content = content()
    }

    private var isExpanded: Bool {
        expandedSections.contains(section)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle(isOn: $isEnabled) {
                    Text(title)
                }
                .toggleStyle(.switch)
                .help(helpText)
                .onChange(of: isEnabled) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if newValue {
                            _ = expandedSections.insert(section)
                        } else {
                            expandedSections.remove(section)
                        }
                    }
                }

                if isEnabled {
                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isEnabled {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedSections.remove(section)
                        } else {
                            _ = expandedSections.insert(section)
                        }
                    }
                }
            }

            if isEnabled && isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 4)
            }
        }
    }
}

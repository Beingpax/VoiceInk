import SwiftUI

struct SidePanel<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panelWidth: CGFloat
    let dismissOnExitCommand: Bool
    @ViewBuilder let panelContent: () -> PanelContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.32)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    private func dismissPanel() {
        isPresented = false
    }

    private var dismissLayer: some View {
        Color.clear
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissPanel)
    }

    private var panelSurface: some View {
        panelContent()
            .frame(width: panelWidth)
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider(), alignment: .leading)
            .ignoresSafeArea()
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            content

            if isPresented {
                dismissLayer

                Group {
                    if dismissOnExitCommand {
                        panelSurface
                            .onExitCommand(perform: dismissPanel)
                    } else {
                        panelSurface
                    }
                }
                .transition(transition)
                .zIndex(1)
            }
        }
        .animation(animation, value: isPresented)
    }
}

extension View {
    func sidePanel<Content: View>(
        isPresented: Binding<Bool>,
        width: CGFloat = 400,
        dismissOnExitCommand: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(SidePanel(
            isPresented: isPresented,
            panelWidth: width,
            dismissOnExitCommand: dismissOnExitCommand,
            panelContent: content
        ))
    }
}

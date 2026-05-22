import SwiftUI

enum SidePanelLayout {
    static let defaultWidth: CGFloat = 400
}

struct SidePanel<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panelWidth: CGFloat
    @ViewBuilder let panelContent: () -> PanelContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.28)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing)
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            content

            if isPresented {
                HStack(spacing: 0) {
                    Color.black.opacity(0.035)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(animation) {
                                isPresented = false
                            }
                        }

                    panelContent()
                        .frame(width: panelWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                        .overlay(Divider(), alignment: .leading)
                        .shadow(color: .black.opacity(0.06), radius: 10, x: -2, y: 0)
                }
                .ignoresSafeArea()
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
        width: CGFloat = SidePanelLayout.defaultWidth,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(SidePanel(isPresented: isPresented, panelWidth: width, panelContent: content))
    }
}

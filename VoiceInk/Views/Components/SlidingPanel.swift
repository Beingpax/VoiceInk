import SwiftUI

struct SlidingPanel<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panelWidth: CGFloat
    @ViewBuilder let panelContent: () -> PanelContent

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content
                .disabled(isPresented)

            Color.black.opacity(isPresented ? 0.1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isPresented)
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.3)) {
                        isPresented = false
                    }
                }
                .animation(.smooth(duration: 0.3), value: isPresented)
                .zIndex(1)

            if isPresented {
                HStack(spacing: 0) {
                    Spacer()

                    panelContent()
                        .frame(width: panelWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                        .overlay(Divider(), alignment: .leading)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: -2, y: 0)
                }
                .ignoresSafeArea()
                .transition(.offset(x: panelWidth))
                .zIndex(2)
            }
        }
    }
}

extension View {
    func slidingPanel<Content: View>(
        isPresented: Binding<Bool>,
        width: CGFloat = 450,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(SlidingPanel(isPresented: isPresented, panelWidth: width, panelContent: content))
    }
}

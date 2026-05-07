#if os(macOS)
import SwiftUI

extension View {
    func bookLoomTrailingSidebar<Item: Identifiable, SidebarContent: View>(
        item: Binding<Item?>,
        width: CGFloat = 520,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping (Item) -> SidebarContent
    ) -> some View {
        modifier(
            BookLoomTrailingSidebarModifier(
                item: item,
                width: width,
                onDismiss: onDismiss,
                sidebarContent: content
            )
        )
    }
}

private struct BookLoomTrailingSidebarModifier<Item: Identifiable, SidebarContent: View>: ViewModifier {
    @Binding var item: Item?
    let width: CGFloat
    let onDismiss: () -> Void
    let sidebarContent: (Item) -> SidebarContent

    func body(content base: Content) -> some View {
        base
            .overlay {
                GeometryReader { proxy in
                    ZStack(alignment: .trailing) {
                        if let item {
                            Color.black.opacity(0.16)
                                .ignoresSafeArea()
                                .transition(.opacity)
                                .onTapGesture(perform: onDismiss)

                            sidebarContent(item)
                                .frame(width: panelWidth(for: proxy.size.width))
                                .frame(maxHeight: .infinity)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .shadow(color: .black.opacity(0.28), radius: 28, x: -10, y: 0)
                                .padding(.vertical, 14)
                                .padding(.trailing, 14)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .accessibilityAddTraits(.isModal)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .trailing)
                }
                .allowsHitTesting(item != nil)
            }
            .animation(.snappy(duration: 0.24), value: item?.id)
    }

    private func panelWidth(for availableWidth: CGFloat) -> CGFloat {
        min(width, max(320, availableWidth - 28))
    }
}
#endif

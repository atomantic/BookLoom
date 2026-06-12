import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension View {
    func bookLoomScreenBackground() -> some View {
        background(BookLoomScreenBackground().ignoresSafeArea())
    }

    func bookLoomCard(padding: CGFloat = 12, radius: CGFloat = 8) -> some View {
        modifier(BookLoomCardModifier(padding: padding, radius: radius))
    }

    func bookLoomListRow(top: CGFloat = 4, bottom: CGFloat = 4, horizontal: CGFloat = 14) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    func bookLoomListStyle(sectionSpacing: CGFloat = 14) -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            listStyle(.plain)
                .listSectionSpacing(sectionSpacing)
                .environment(\.defaultMinListRowHeight, 0)
        } else {
            listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 0)
        }
        #else
        listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
        #endif
    }

    /// Inline navigation title + opaque toolbar background. Without an opaque
    /// background, `bookLoomScreenBackground()` content scrolls under the
    /// transparent navbar and the inline title overlaps the first card text.
    @ViewBuilder
    func bookLoomNavigationBar() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    func bookLoomActionWidth(minWidth: CGFloat = 180) -> some View {
        modifier(BookLoomActionWidthModifier(minWidth: minWidth))
    }

    /// Show the pointing-hand cursor on hover for clickable controls on macOS.
    /// No-op on iOS where pointer affordances aren't applicable.
    func bookLoomPointerCursor() -> some View {
        #if os(macOS)
        // Set the cursor directly rather than push/pop: a hovered view can be
        // removed (e.g. an import row's swipe-to-remove) before the exit event
        // fires, which would strand a pushed cursor on the stack with no
        // matching pop. `set()` carries no such balance requirement.
        onHover { hovering in
            (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
        #else
        self
        #endif
    }
}

extension DynamicTypeSize {
    /// Start using roomier stacked layouts before iOS reaches the formal
    /// accessibility sizes. `xxxLarge` already makes three-column controls
    /// compress badly on narrow iPhones.
    var prefersExpandedControlLayout: Bool {
        self >= .xxLarge
    }

    /// Pick a roomier vertical stack at expanded text sizes and a compact
    /// horizontal one otherwise. Collapses the repeated
    /// `prefersExpandedControlLayout ? AnyLayout(VStackLayout(...)) : AnyLayout(HStackLayout(...))`
    /// computed properties scattered across the tab and detail views.
    func adaptiveLayout(expanded: VStackLayout, compact: HStackLayout) -> AnyLayout {
        prefersExpandedControlLayout ? AnyLayout(expanded) : AnyLayout(compact)
    }
}

struct BookLoomActionWidthModifier: ViewModifier {
    let minWidth: CGFloat
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    func body(content: Content) -> some View {
        if shouldFillAvailableWidth {
            content.frame(maxWidth: .infinity)
        } else {
            content
                .frame(minWidth: minWidth)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var shouldFillAvailableWidth: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }
}

private struct BookLoomScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        BookLoomStyle.screenGradient(for: colorScheme)
    }
}

private struct BookLoomCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(cardFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            }
    }

    private var cardFill: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.36)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? .white.opacity(0.16) : .white.opacity(0.50)
    }
}

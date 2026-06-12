#if os(iOS)
import SwiftUI

/// Regular-width iOS container (large iPad, iPad landscape, regular-width Split View).
///
/// Mirrors the macOS `NavigationSplitView` sidebar/detail structure but reuses the
/// existing iOS tab content views so there is no duplicated tab logic. Compact-width
/// iOS (iPhone, narrow multitasking) continues to use the `TabView` in `MainTabs`,
/// so all `selectedTab` / `NavigationPath` state is shared and behaves identically.
struct RegularWidthMainView: View {
    @Binding var selectedTab: MainTab
    @Binding var booksPath: NavigationPath
    @Binding var discussionsPath: NavigationPath
    @Binding var schedulePath: NavigationPath

    /// Maps the shared `selectedTab` onto the five sidebar destinations. The iPhone
    /// `.books` tab also surfaces polls, so any non-sidebar tab resolves to `.books`,
    /// matching how the screenshot/import routes already collapse onto that tab.
    private var sidebarSelection: Binding<MainTab?> {
        Binding(
            get: { selectedTab == .polls ? .books : selectedTab },
            set: { newValue in
                guard let newValue else { return }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("Shelf") {
                    RegularWidthSidebarRow(tab: .library)
                        .tag(MainTab.library)
                }

                Section("Book Club") {
                    RegularWidthSidebarRow(tab: .books)
                        .tag(MainTab.books)
                    RegularWidthSidebarRow(tab: .discussions)
                        .tag(MainTab.discussions)
                    RegularWidthSidebarRow(tab: .schedule)
                        .tag(MainTab.schedule)
                }

                Section {
                    RegularWidthSidebarRow(tab: .settings)
                        .tag(MainTab.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("BookLoom")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            switch selectedTab {
            case .library:
                NavigationStack {
                    LibraryTabView()
                }
            case .books, .polls:
                NavigationStack(path: $booksPath) {
                    BooksTabView(path: $booksPath)
                }
            case .discussions:
                NavigationStack(path: $discussionsPath) {
                    DiscussionsTabView()
                }
            case .schedule:
                NavigationStack(path: $schedulePath) {
                    ScheduleTabView()
                }
            case .settings:
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }
}

private struct RegularWidthSidebarRow: View {
    let tab: MainTab

    var body: some View {
        Label(tab.title, systemImage: tab.systemImage)
    }
}
#endif

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(MemberIdentity.self) private var memberIdentity
    @AppStorage(WelcomeReplay.storageKey) private var replayWelcome = false

    var body: some View {
        Group {
            if !AppLaunchOptions.isSampleDataEnabled && (replayWelcome || !memberIdentity.isConfigured) {
                MemberOnboardingView(isReplay: replayWelcome && memberIdentity.isConfigured)
            } else {
                MainTabs()
            }
        }
        .tint(BookLoomStyle.plum)
    }
}

private struct MainTabs: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(ActiveClubStore.self) private var activeClubStore
    @Environment(GoodreadsImportInbox.self) private var goodreadsInbox
    @Query(sort: \BookClub.createdAt, order: .reverse) private var clubs: [BookClub]
    @State private var coordinator = NavigationCoordinator()
    // Passive background sync; real-time updates arrive via the CloudKit push path
    // (CloudKitChangeInbox), so this only needs to be an occasional safety net.
    private let sharedSyncTimer = Timer.publish(every: 90, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var goodreadsInbox = goodreadsInbox
        @Bindable var coordinator = coordinator
        return Group {
            #if os(macOS)
            DesktopMainView(
                selectedTab: $coordinator.selectedTab,
                booksPath: $coordinator.booksPath,
                discussionsPath: $coordinator.discussionsPath,
                schedulePath: $coordinator.schedulePath
            )
            #else
            if horizontalSizeClass == .regular {
                RegularWidthMainView(
                    selectedTab: $coordinator.selectedTab,
                    booksPath: $coordinator.booksPath,
                    discussionsPath: $coordinator.discussionsPath,
                    schedulePath: $coordinator.schedulePath
                )
            } else {
            TabView(selection: $coordinator.selectedTab) {
                NavigationStack {
                    LibraryTabView()
                }
                .tabItem {
                    Label(MainTab.library.tabTitle(for: dynamicTypeSize), systemImage: "books.vertical.fill")
                }
                .tag(MainTab.library)

                NavigationStack(path: $coordinator.booksPath) {
                    BooksTabView(path: $coordinator.booksPath)
                }
                .tabItem {
                    Label(MainTab.books.tabTitle(for: dynamicTypeSize), systemImage: "person.2.fill")
                }
                .tag(MainTab.books)

                NavigationStack(path: $coordinator.discussionsPath) {
                    DiscussionsTabView()
                }
                .tabItem {
                    Label(MainTab.discussions.tabTitle(for: dynamicTypeSize), systemImage: "text.bubble.fill")
                }
                .tag(MainTab.discussions)

                NavigationStack(path: $coordinator.schedulePath) {
                    ScheduleTabView()
                }
                .tabItem {
                    Label(MainTab.schedule.tabTitle(for: dynamicTypeSize), systemImage: "calendar")
                }
                .tag(MainTab.schedule)

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label(MainTab.settings.tabTitle(for: dynamicTypeSize), systemImage: "gearshape.fill")
                }
                .tag(MainTab.settings)
            }
            }
            #endif
        }
        .task {
            activeClubStore.reconcileWithVisibleClubs(visibleClubs)
            await refreshSharedClubs()
            goodreadsInbox.refresh()
            goodreadsInbox.prefetchAll()
            #if os(iOS)
            goodreadsInbox.presentNextIfNeeded()
            #endif
            guard let route = AppLaunchOptions.screenshotRoute else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            navigateToScreenshotRoute(route)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshSharedClubs() }
            goodreadsInbox.refresh()
            goodreadsInbox.prefetchAll()
            #if os(iOS)
            goodreadsInbox.presentNextIfNeeded()
            #endif
        }
        .onReceive(sharedSyncTimer) { _ in
            guard scenePhase == .active else { return }
            Task { await refreshSharedClubs() }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        #if os(macOS)
        .bookLoomTrailingSidebar(
            item: $goodreadsInbox.presentedItem,
            width: 520,
            onDismiss: { goodreadsInbox.dismiss(saved: false) }
        ) { item in
            goodreadsImportView(for: item)
        }
        #else
        .modifier(
            GoodreadsImportPresentation(item: $goodreadsInbox.presentedItem) { item in
                goodreadsImportView(for: item)
            }
        )
        #endif
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "bookloom" else { return }
        switch url.host() {
        case "screenshot":
            guard AppLaunchOptions.isSampleDataEnabled else { return }
            let route = url.pathComponents.filter { $0 != "/" }.first ?? "books"
            navigateToScreenshotRoute(route)
        case "import":
            handleImportURL(url)
        default:
            break
        }
    }

    private func handleImportURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let goodreadsURL = URL(string: raw),
              let canonical = GoodreadsLinkExtractor.extract(from: goodreadsURL) else {
            return
        }
        SharedImportInbox.enqueue(canonical)
        #if os(macOS)
        coordinator.select(.library)
        goodreadsInbox.refresh()
        goodreadsInbox.prefetchAll()
        #else
        coordinator.select(.books)
        goodreadsInbox.refresh()
        goodreadsInbox.prefetchAll()
        goodreadsInbox.present(canonical)
        #endif
    }

    private var visibleClubs: [BookClub] {
        clubs.filter { !SchemaPrimeDataCleanup.isSchemaPrime($0) }
    }

    private func refreshSharedClubs() async {
        let targets = visibleClubs.filter(\.shareIsActive)
        guard !targets.isEmpty else { return }
        await SharedClubSync.refreshIfNeeded(
            targets,
            context: context,
            localMemberID: memberIdentity.memberID,
            localMemberName: memberIdentity.name
        )
    }

    private func goodreadsImportView(for item: SharedImportInbox.PendingImport) -> some View {
        GoodreadsImportSheet(
            pendingItem: item,
            clubs: visibleClubs,
            initiallyActiveClub: activeClubStore.resolveActiveClub(from: visibleClubs),
            onDismiss: handleGoodreadsImportCompletion
        )
    }

    private func handleGoodreadsImportCompletion(_ completion: GoodreadsImportCompletion) {
        goodreadsInbox.dismiss(saved: completion.didSave)
        if let primaryClub = completion.primaryClub {
            activeClubStore.setActiveClub(primaryClub)
            coordinator.select(.books)
        } else if completion.didSave {
            coordinator.select(.library)
        }
    }

    /// Resolves the club-derived navigation targets for `route` and hands them to
    /// the coordinator, which owns the actual tab/path mutations. Setting the
    /// active club (a side effect on `ActiveClubStore`) stays here in the view.
    private func navigateToScreenshotRoute(_ route: String) {
        let club = visibleClubs.first
        if let club {
            activeClubStore.setActiveClub(club)
        }
        coordinator.applyScreenshotRoute(
            route,
            hasClub: club != nil,
            presentFirstPendingImport: {
                if let firstPending = goodreadsInbox.pending.first {
                    goodreadsInbox.present(firstPending.url)
                }
            },
            pushCurrentRead: {
                if let current = club?.sections.current {
                    coordinator.pushBooks(current)
                }
            },
            pushFirstSelectionPoll: {
                if let poll = club?.recentSelectionPolls.first {
                    coordinator.pushBooks(poll)
                }
            },
            pushFirstMeeting: {
                if let meeting = club?.upcomingMeetings.first ?? club?.pastMeetings.first {
                    coordinator.pushSchedule(meeting)
                }
            }
        )
    }
}

#if os(iOS)
private struct GoodreadsImportPresentation<ImportContent: View>: ViewModifier {
    @Binding var item: SharedImportInbox.PendingImport?
    let importContent: (SharedImportInbox.PendingImport) -> ImportContent

    init(
        item: Binding<SharedImportInbox.PendingImport?>,
        @ViewBuilder importContent: @escaping (SharedImportInbox.PendingImport) -> ImportContent
    ) {
        _item = item
        self.importContent = importContent
    }

    func body(content: Content) -> some View {
        if AppLaunchOptions.screenshotRoute == "import" {
            content.fullScreenCover(item: $item, content: importContent)
        } else {
            content.sheet(item: $item, content: importContent)
        }
    }
}
#endif

enum MainTab: Hashable {
    case library
    case books
    case polls
    case discussions
    case schedule
    case settings

    static var defaultSelection: MainTab {
        #if os(macOS)
        return .library
        #else
        return .books
        #endif
    }

    var title: String {
        switch self {
        case .library: return "Shelf"
        case .books: return "Club"
        case .polls: return "Polls"
        case .discussions: return "Discussions"
        case .schedule: return "Schedule"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .books: return "person.2.fill"
        case .polls: return "list.number"
        case .discussions: return "text.bubble.fill"
        case .schedule: return "calendar"
        case .settings: return "gearshape.fill"
        }
    }

    func tabTitle(for dynamicTypeSize: DynamicTypeSize) -> String {
        guard dynamicTypeSize.prefersExpandedControlLayout else { return title }
        switch self {
        case .discussions: return "Chat"
        case .schedule: return "Events"
        default: return title
        }
    }
}

#if os(macOS)
private struct DesktopMainView: View {
    @Binding var selectedTab: MainTab
    @Binding var booksPath: NavigationPath
    @Binding var discussionsPath: NavigationPath
    @Binding var schedulePath: NavigationPath

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Shelf") {
                    DesktopSidebarRow(tab: .library)
                        .tag(MainTab.library)
                }

                Section("Book Club") {
                    DesktopSidebarRow(tab: .books)
                        .tag(MainTab.books)
                    DesktopSidebarRow(tab: .polls)
                        .tag(MainTab.polls)
                    DesktopSidebarRow(tab: .discussions)
                        .tag(MainTab.discussions)
                    DesktopSidebarRow(tab: .schedule)
                        .tag(MainTab.schedule)
                }

                Section {
                    DesktopSidebarRow(tab: .settings)
                        .tag(MainTab.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("BookLoom")
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            switch selectedTab {
            case .library:
                NavigationStack {
                    DesktopLibraryView()
                }
            case .books:
                NavigationStack(path: $booksPath) {
                    BooksTabView(path: $booksPath)
                }
            case .polls:
                NavigationStack {
                    PollsTabView()
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

private struct DesktopSidebarRow: View {
    let tab: MainTab

    var body: some View {
        Label(tab.title, systemImage: tab.systemImage)
    }
}
#endif

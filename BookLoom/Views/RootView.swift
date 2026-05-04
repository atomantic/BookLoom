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
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(ActiveClubStore.self) private var activeClubStore
    @Environment(GoodreadsImportInbox.self) private var goodreadsInbox
    @Query(sort: \BookClub.createdAt, order: .reverse) private var clubs: [BookClub]
    @State private var selectedTab = MainTab.books
    @State private var booksPath = NavigationPath()
    @State private var pollsPath = NavigationPath()
    @State private var schedulePath = NavigationPath()
    @State private var discussionsPath = NavigationPath()
    private let sharedSyncTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var goodreadsInbox = goodreadsInbox
        return TabView(selection: $selectedTab) {
            NavigationStack(path: $booksPath) {
                BooksTabView()
            }
            .tabItem {
                Label("Books", systemImage: "books.vertical.fill")
            }
            .tag(MainTab.books)

            NavigationStack(path: $pollsPath) {
                PollsTabView()
            }
            .tabItem {
                Label("Polls", systemImage: "list.number")
            }
            .tag(MainTab.polls)

            NavigationStack(path: $discussionsPath) {
                DiscussionsTabView()
            }
            .tabItem {
                Label("Discussions", systemImage: "text.bubble.fill")
            }
            .tag(MainTab.discussions)

            NavigationStack(path: $schedulePath) {
                ScheduleTabView()
            }
            .tabItem {
                Label("Schedule", systemImage: "calendar")
            }
            .tag(MainTab.schedule)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(MainTab.settings)
        }
        .task {
            activeClubStore.reconcileWithVisibleClubs(visibleClubs)
            await refreshSharedClubs()
            goodreadsInbox.refresh()
            goodreadsInbox.prefetchAll()
            goodreadsInbox.presentNextIfNeeded()
            guard let route = AppLaunchOptions.screenshotRoute else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            navigateToScreenshotRoute(route)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshSharedClubs() }
            goodreadsInbox.refresh()
            goodreadsInbox.prefetchAll()
            goodreadsInbox.presentNextIfNeeded()
        }
        .onReceive(sharedSyncTimer) { _ in
            guard scenePhase == .active else { return }
            Task { await refreshSharedClubs() }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .sheet(item: $goodreadsInbox.presentedItem) { item in
            GoodreadsImportSheet(
                pendingItem: item,
                clubs: visibleClubs,
                initiallyActiveClub: activeClubStore.resolveActiveClub(from: visibleClubs)
            ) { savedClub in
                goodreadsInbox.dismiss(saved: savedClub != nil)
                if let savedClub {
                    activeClubStore.setActiveClub(savedClub)
                    selectedTab = .books
                }
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "bookloom" else { return }
        switch url.host() {
        case "screenshot":
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
        selectedTab = .books
        goodreadsInbox.refresh()
        goodreadsInbox.prefetchAll()
        goodreadsInbox.present(canonical)
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

    private func navigateToScreenshotRoute(_ route: String) {
        booksPath = NavigationPath()
        pollsPath = NavigationPath()
        schedulePath = NavigationPath()
        discussionsPath = NavigationPath()

        guard let club = visibleClubs.first else {
            selectedTab = .books
            return
        }
        activeClubStore.setActiveClub(club)

        switch route {
        case "books", "clubs", "clubHome", "shelf":
            selectedTab = .books
        case "import":
            selectedTab = .books
            if let firstPending = goodreadsInbox.pending.first {
                goodreadsInbox.present(firstPending.url)
            }
        case "currentRead":
            selectedTab = .books
            if let current = club.sections.current {
                booksPath.append(current)
            }
        case "polls":
            selectedTab = .polls
        case "poll", "vote":
            selectedTab = .polls
            if let poll = club.recentSelectionPolls.first {
                pollsPath.append(poll)
            }
        case "schedule":
            selectedTab = .schedule
        case "meeting", "meetings":
            selectedTab = .schedule
            if let meeting = club.upcomingMeetings.first ?? club.pastMeetings.first {
                schedulePath.append(meeting)
            }
        case "discussion", "discussions":
            selectedTab = .discussions
        case "settings":
            selectedTab = .settings
        default:
            selectedTab = .books
        }
    }
}

private enum MainTab: Hashable {
    case books
    case polls
    case discussions
    case schedule
    case settings
}

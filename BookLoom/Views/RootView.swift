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
    @Query(sort: \BookClub.createdAt, order: .reverse) private var clubs: [BookClub]
    @State private var selectedTab = MainTab.books
    @State private var booksPath = NavigationPath()
    @State private var pollsPath = NavigationPath()
    @State private var schedulePath = NavigationPath()
    @State private var discussionsPath = NavigationPath()
    private let sharedSyncTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selectedTab) {
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
            guard let route = AppLaunchOptions.screenshotRoute else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            navigateToScreenshotRoute(route)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshSharedClubs() }
        }
        .onReceive(sharedSyncTimer) { _ in
            guard scenePhase == .active else { return }
            Task { await refreshSharedClubs() }
        }
        .onOpenURL { url in
            guard url.scheme == "bookloom", url.host() == "screenshot" else { return }
            let route = url.pathComponents.filter { $0 != "/" }.first ?? "books"
            navigateToScreenshotRoute(route)
        }
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
        case "books", "clubs", "clubHome":
            selectedTab = .books
        case "currentRead":
            selectedTab = .books
            if let current = club.sections.current {
                booksPath.append(current)
            }
        case "poll", "polls":
            selectedTab = .polls
            if let poll = club.recentSelectionPolls.first {
                pollsPath.append(poll)
            }
        case "meeting", "meetings", "schedule":
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

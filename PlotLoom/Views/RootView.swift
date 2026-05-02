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
        .tint(PlotLoomStyle.plum)
    }
}

private struct MainTabs: View {
    @Query(sort: \BookClub.createdAt, order: .reverse) private var clubs: [BookClub]
    @State private var selectedTab = 0
    @State private var clubPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $clubPath) {
                ClubsListView()
            }
            .tabItem {
                Label("Clubs", systemImage: "books.vertical.fill")
            }
            .tag(0)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(1)
        }
        .task {
            guard let route = AppLaunchOptions.screenshotRoute else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            navigateToScreenshotRoute(route)
        }
        .onOpenURL { url in
            guard url.scheme == "plotloom", url.host() == "screenshot" else { return }
            let route = url.pathComponents.filter { $0 != "/" }.first ?? "clubs"
            navigateToScreenshotRoute(route)
        }
    }

    private func navigateToScreenshotRoute(_ route: String) {
        selectedTab = 0
        clubPath = NavigationPath()

        guard route != "clubs", let club = clubs.first else { return }
        clubPath.append(club)

        switch route {
        case "clubHome", "proposals":
            return
        case "currentRead":
            if let current = club.sections.current {
                clubPath.append(current)
            }
        case "poll":
            if let poll = club.recentSelectionPolls.first {
                clubPath.append(poll)
            }
        case "meeting":
            if let meeting = club.upcomingMeetings.first ?? club.pastMeetings.first {
                clubPath.append(meeting)
            }
        default:
            return
        }
    }
}

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(MemberIdentity.self) private var memberIdentity
    @AppStorage(WelcomeReplay.storageKey) private var replayWelcome = false

    var body: some View {
        Group {
            if replayWelcome || !memberIdentity.isConfigured {
                MemberOnboardingView(isReplay: replayWelcome && memberIdentity.isConfigured)
            } else {
                MainTabs()
            }
        }
        .tint(PlotLoomStyle.plum)
    }
}

private struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack {
                ClubsListView()
            }
            .tabItem {
                Label("Clubs", systemImage: "books.vertical.fill")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
    }
}

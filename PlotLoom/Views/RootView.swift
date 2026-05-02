import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(MemberIdentity.self) private var memberIdentity

    var body: some View {
        if !memberIdentity.isConfigured {
            MemberOnboardingView()
        } else {
            MainTabs()
        }
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
        .tint(PlotLoomStyle.plum)
    }
}

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(MemberIdentity.self) private var memberIdentity
    @Query private var clubs: [BookClub]

    var body: some View {
        Group {
            if !memberIdentity.isConfigured {
                MemberOnboardingView()
            } else if let club = clubs.first {
                BookClubHomeView(club: club)
            } else {
                CreateOrJoinClubView()
            }
        }
    }
}

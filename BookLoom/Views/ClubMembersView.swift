import SwiftUI
import SwiftData

struct ClubMembersView: View {
    @Bindable var club: BookClub
    @State private var showingInvite = false

    var body: some View {
        let members = club.memberDigests
        let unnamedCount = max(0, club.displayedMemberCount - members.count)

        List {
            Section {
                MemberCountOverview(club: club)

                if members.isEmpty && unnamedCount == 0 {
                    InlineEmptyState(
                        systemImage: "person.2.fill",
                        title: "No Members Yet",
                        message: "Accepted members appear here as the club syncs."
                    )
                } else {
                    ForEach(members) { member in
                        ClubMemberRow(member: member)
                    }

                    ForEach(0..<unnamedCount, id: \.self) { _ in
                        UnnamedMemberRow()
                    }
                }
            } header: {
                SectionTitle(title: "Members", detail: "\(club.displayedMemberCount)")
            }
            .bookLoomListRow()

            Section {
                if club.isOwner {
                    Button {
                        showingInvite = true
                    } label: {
                        Label("Manage Sharing", systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ClubPermissionSummary()
                }
            } header: {
                SectionTitle(title: "Permissions")
            }
            .bookLoomListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationTitle("Members")
        .sheet(isPresented: $showingInvite) {
            InviteView(club: club)
        }
    }
}

private struct MembersIconRow: View {
    let icon: String
    let iconTint: Color
    let iconWeighted: Bool
    let title: String
    let subtitle: String
    var titleLineLimit: Int? = nil
    var subtitleWeighted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(iconWeighted ? .title3.weight(.semibold) : .title3)
                .foregroundStyle(iconTint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(titleLineLimit)
                Text(subtitle)
                    .font(subtitleWeighted ? .caption.weight(.medium) : .caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 10)
    }
}

private struct MemberCountOverview: View {
    let club: BookClub

    var body: some View {
        MembersIconRow(
            icon: "person.2.fill",
            iconTint: BookLoomStyle.sage,
            iconWeighted: true,
            title: memberCountLabel,
            subtitle: club.isOwner ? "Owner" : "Shared member",
            subtitleWeighted: true
        )
    }

    private var memberCountLabel: String {
        club.displayedMemberCount == 1 ? "1 accepted member" : "\(club.displayedMemberCount) accepted members"
    }
}

private struct ClubMemberRow: View {
    let member: ClubMemberDigest

    var body: some View {
        MembersIconRow(
            icon: "person.crop.circle.fill",
            iconTint: BookLoomStyle.indigo,
            iconWeighted: false,
            title: member.name,
            subtitle: activityLabel,
            titleLineLimit: 1
        )
    }

    private var activityLabel: String {
        member.activityCount == 1 ? "1 club activity" : "\(member.activityCount) club activities"
    }
}

private struct UnnamedMemberRow: View {
    var body: some View {
        MembersIconRow(
            icon: "person.crop.circle",
            iconTint: .secondary,
            iconWeighted: false,
            title: "Accepted Member",
            subtitle: "Name appears after club activity"
        )
    }
}

private struct ClubPermissionSummary: View {
    var body: some View {
        MembersIconRow(
            icon: "lock.fill",
            iconTint: BookLoomStyle.plum,
            iconWeighted: true,
            title: "Member",
            subtitle: "The owner manages invitations and permissions."
        )
    }
}

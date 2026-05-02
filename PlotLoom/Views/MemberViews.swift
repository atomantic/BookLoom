import SwiftUI

struct MemberSummaryCard: View {
    let club: BookClub

    var body: some View {
        let members = club.memberDigests

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(club.displayedMemberCount) members", systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlotLoomStyle.ink)
                Spacer()
                Label(syncLabel, systemImage: syncIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if members.isEmpty {
                Text("Member names appear after submissions, votes, RSVPs, ratings, or notes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(members.prefix(8)) { member in
                            TintedCapsuleLabel(
                                text: member.name,
                                tint: PlotLoomStyle.indigo,
                                horizontalPadding: 8,
                                verticalPadding: 5
                            )
                        }
                    }
                }
            }
        }
        .plotLoomCard(padding: 10)
    }

    private var syncLabel: String {
        if !club.isOwner { return "Shared" }
        return club.shareIsActive ? "iCloud on" : "Owner only"
    }

    private var syncIcon: String {
        if !club.isOwner { return "person.2.fill" }
        return club.shareIsActive ? "icloud.fill" : "lock.fill"
    }
}

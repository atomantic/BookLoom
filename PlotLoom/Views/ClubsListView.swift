import SwiftUI
import SwiftData

struct ClubsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BookClub.createdAt, order: .reverse) private var clubs: [BookClub]
    @State private var showingNewClubForm = false

    var body: some View {
        Group {
            if clubs.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ClubsOverviewHeader(clubs: clubs)
                            .plotLoomListRow(top: 6, bottom: 8)
                    }

                    ForEach(clubs) { club in
                        NavigationLink(value: club) {
                            ClubRow(club: club)
                        }
                        .plotLoomListRow()
                    }
                    .onDelete(perform: deleteClubs)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationDestination(for: BookClub.self) { club in
                    BookClubHomeView(club: club)
                }
            }
        }
        .plotLoomScreenBackground()
        .navigationTitle("Clubs")
        .toolbar {
            if !clubs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewClubForm = true
                    } label: {
                        Label("New Club", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewClubForm) {
            NavigationStack {
                NewClubFormView()
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                OnboardingHeroArtwork(maxHeight: 220)
                VStack(spacing: 6) {
                    Text("Create or Join a Club")
                        .font(.title.bold())
                        .foregroundStyle(PlotLoomStyle.ink)
                    Text("Create a club if you are starting one. If someone already made the club in PlotLoom, you can wait here and open their invite when it arrives.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    showingNewClubForm = true
                } label: {
                    Label("Create New Club", systemImage: "plus.circle.fill")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Label("No club needed until you create one or open an invite.", systemImage: "envelope.badge")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .plotLoomScreenBackground()
    }

    private func deleteClubs(at offsets: IndexSet) {
        for index in offsets {
            context.delete(clubs[index])
        }
    }
}

private struct ClubRow: View {
    let club: BookClub

    var body: some View {
        let sections = club.sections
        let metrics = club.metrics
        let currentTitle = sections.current?.displayTitle

        HStack(spacing: 12) {
            BookCoverTile(
                title: currentTitle ?? club.name,
                author: club.name,
                coverURL: sections.current?.coverImageURL,
                width: 46,
                height: 62
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(club.name)
                        .font(.headline)
                        .foregroundStyle(PlotLoomStyle.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !club.isOwner {
                        Label("Shared", systemImage: "person.2.fill")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(PlotLoomStyle.sage)
                            .help("Shared with you")
                    } else if club.shareIsActive {
                        Label("Sharing", systemImage: "icloud.fill")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(PlotLoomStyle.indigo)
                            .help("Sharing enabled")
                    }
                }

                if let currentTitle {
                    Label(currentTitle, systemImage: "book.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Label("\(metrics.proposedCount) proposed", systemImage: "tray.full.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    CountBadge(value: metrics.completedCount, label: "read", tint: PlotLoomStyle.indigo)
                    CountBadge(value: club.displayedMemberCount, label: "members", tint: PlotLoomStyle.sage)
                    CountBadge(value: metrics.noteCount, label: "notes", tint: PlotLoomStyle.plum)
                }
            }
        }
        .plotLoomCard(padding: 10)
    }
}

private struct ClubsOverviewHeader: View {
    let clubs: [BookClub]

    var body: some View {
        let totals = clubTotals

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BrandBadge(size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PlotLoom")
                        .font(.headline.bold())
                        .foregroundStyle(PlotLoomStyle.ink)
                    Text("Keep every club's next read in motion.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                MetricTile(value: "\(clubs.count)", label: "clubs", systemImage: "person.3.fill", tint: PlotLoomStyle.indigo)
                MetricTile(value: "\(totals.current)", label: "active reads", systemImage: "book.fill", tint: PlotLoomStyle.sage)
                MetricTile(value: "\(totals.proposed)", label: "proposals", systemImage: "sparkles", tint: PlotLoomStyle.plum)
            }
        }
        .plotLoomCard(padding: 12)
    }

    private var clubTotals: (current: Int, proposed: Int) {
        var current = 0
        var proposed = 0
        for club in clubs {
            let metrics = club.metrics
            current += metrics.currentCount
            proposed += metrics.proposedCount
        }
        return (current, proposed)
    }
}

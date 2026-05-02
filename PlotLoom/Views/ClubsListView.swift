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
                    ForEach(clubs) { club in
                        NavigationLink(value: club) {
                            ClubRow(club: club)
                        }
                    }
                    .onDelete(perform: deleteClubs)
                }
                .navigationDestination(for: BookClub.self) { club in
                    BookClubHomeView(club: club)
                }
            }
        }
        .navigationTitle("Book Clubs")
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
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("No book clubs yet")
                .font(.title2.bold())
            Text("Start one for your reading group, or accept an iCloud invite from someone who already has.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button {
                showingNewClubForm = true
            } label: {
                Label("Create Your First Club", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(club.name)
                    .font(.headline)
                Spacer()
                if !club.isOwner {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Shared with you")
                }
            }
            HStack(spacing: 8) {
                if let current = currentTitle {
                    Label(current, systemImage: "book.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(proposedCount) proposed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var currentTitle: String? {
        (club.submissions ?? [])
            .first { $0.status == .current }
            .map { $0.title.isEmpty ? "Untitled" : $0.title }
    }

    private var proposedCount: Int {
        (club.submissions ?? []).filter { $0.status == .proposed }.count
    }
}

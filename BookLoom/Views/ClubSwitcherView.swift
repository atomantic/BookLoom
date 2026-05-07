import SwiftUI
import SwiftData

/// Account-switcher style picker used by the toolbar club button. Presents
/// every visible club, marks the active one, and offers a "New Club" entry
/// at the bottom. Keeps the rest of the app focused on a single club at a
/// time so members never lose track of which club they're acting in.
struct ClubSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(ActiveClubStore.self) private var activeClubStore
    @Query(sort: \BookClub.createdAt, order: .reverse) private var clubs: [BookClub]

    let onDismiss: (() -> Void)?

    @State private var showingNewClubForm = false
    @State private var pendingDeleteClub: BookClub?
    @State private var clubCountBeforeCreate: Int?

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            #if os(macOS)
            if showingNewClubForm {
                NewClubFormView(
                    onCancel: { showingNewClubForm = false },
                    onCreated: handleCreatedClub
                )
            } else {
                switcherList
            }
            #else
            switcherList
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showingNewClubForm, onDismiss: handleNewClubFormDismiss) {
            NavigationStack {
                NewClubFormView()
            }
        }
        #endif
        .confirmationDialog(
            pendingDeleteClub.map { "Delete \($0.name)?" } ?? "Delete club?",
            isPresented: .presence(of: $pendingDeleteClub),
            titleVisibility: .visible
        ) {
            Button("Delete Club", role: .destructive) {
                confirmDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the club and its proposals, meetings, votes, ratings, and notes from this device.")
        }
    }

    private var switcherList: some View {
        List {
            Section {
                if visibleClubs.isEmpty {
                    InlineEmptyState(
                        systemImage: "books.vertical",
                        title: "No Clubs Yet",
                        message: "Create a club to get started, or wait for an invite to arrive."
                    )
                    .bookLoomListRow()
                } else {
                    ForEach(visibleClubs) { club in
                        ClubSwitcherRow(
                            club: club,
                            isActive: club.cloudZoneName == activeClubStore.activeClubZoneName,
                            onSelect: { select(club) }
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeleteClub = club
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .bookLoomListRow()
                    }
                }
            } header: {
                SectionTitle(title: "Your Clubs", detail: "\(visibleClubs.count)")
            }

            Section {
                Button(action: presentNewClubForm) {
                    Label("Create New Club", systemImage: "plus.circle.fill")
                }
                .buttonStyle(BookLoomProminentButtonStyle())
                .controlSize(.large)
                .bookLoomActionWidth(minWidth: 190)
                .bookLoomListRow()
            }
        }
        .bookLoomListStyle()
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationTitle("Switch Club")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done", action: close)
            }
        }
    }

    private var visibleClubs: [BookClub] {
        clubs.filter { !SchemaPrimeDataCleanup.isSchemaPrime($0) }
    }

    private func select(_ club: BookClub) {
        activeClubStore.setActiveClub(club)
        close()
    }

    private func presentNewClubForm() {
        clubCountBeforeCreate = visibleClubs.count
        showingNewClubForm = true
    }

    private func handleCreatedClub(_ club: BookClub) {
        clubCountBeforeCreate = nil
        activeClubStore.setActiveClub(club)
        close()
    }

    private func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func handleNewClubFormDismiss() {
        defer { clubCountBeforeCreate = nil }
        guard let priorCount = clubCountBeforeCreate else { return }
        let current = visibleClubs
        guard current.count > priorCount else { return }
        if let newest = current.first {
            activeClubStore.setActiveClub(newest)
            dismiss()
        }
    }

    private func confirmDelete() {
        guard let club = pendingDeleteClub else { return }
        pendingDeleteClub = nil
        let memberID = memberIdentity.memberID
        let zoneName = club.cloudZoneName
        let isActive = zoneName == activeClubStore.activeClubZoneName
        Task { @MainActor in
            await SharedClubSync.cleanupBeforeDelete(club, localMemberID: memberID)
            context.delete(club)
            try? context.save()
            if isActive {
                activeClubStore.clearActiveClub()
            }
        }
    }
}

private struct ClubSwitcherRow: View {
    let club: BookClub
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                BookCoverTile(
                    title: club.sections.current?.displayTitle ?? club.name,
                    author: club.name,
                    coverURL: club.sections.current?.coverImageURL,
                    width: 42,
                    height: 56
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(club.name)
                            .font(.headline)
                            .foregroundStyle(BookLoomStyle.ink)
                            .lineLimit(1)
                        if !club.isOwner {
                            Image(systemName: "person.2.fill")
                                .font(.caption2)
                                .foregroundStyle(BookLoomStyle.sage)
                                .accessibilityLabel("Shared club")
                        } else if club.shareIsActive {
                            Image(systemName: "icloud.fill")
                                .font(.caption2)
                                .foregroundStyle(BookLoomStyle.indigo)
                                .accessibilityLabel("Sharing enabled")
                        }
                    }
                    if let title = club.sections.current?.displayTitle {
                        Label(title, systemImage: "book.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Label("\(club.metrics.proposedCount) proposed", systemImage: "tray.full.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(BookLoomStyle.indigo)
                        .accessibilityLabel("Active club")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .bookLoomCard(padding: 10)
        }
        .buttonStyle(.plain)
    }
}

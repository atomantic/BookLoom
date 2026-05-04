import SwiftUI
import SwiftData

/// Wrapper that resolves the active club from the store and either renders
/// the supplied club-aware content or a "no club" empty state. Each top-level
/// tab (Books, Polls, Discussions, Schedule) wraps its content with this so
/// they all share the same switcher toolbar and onboarding behavior.
struct ClubScopedScaffold<Content: View>: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(ActiveClubStore.self) private var activeClubStore
    @Query(sort: \BookClub.createdAt, order: .reverse) private var allClubs: [BookClub]

    let title: String
    let content: (BookClub) -> Content

    @State private var showingSwitcher = false
    @State private var showingNewClubSheet = false
    @State private var clubCountBeforeCreate: Int?

    init(title: String, @ViewBuilder content: @escaping (BookClub) -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        let visible = visibleClubs
        return Group {
            if let club = activeClubStore.resolveActiveClub(from: visible) {
                content(club)
                    .navigationTitle(title)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: clubSwitcherPlacement) {
                            ClubSwitcherButton(club: club, action: { showingSwitcher = true })
                        }
                        ToolbarItem(placement: .secondaryAction) {
                            NavigationLink {
                                ClubManagementView(club: club)
                            } label: {
                                Label("Manage Club", systemImage: "gearshape.fill")
                            }
                        }
                    }
            } else {
                NoActiveClubView(onCreateClub: {
                    clubCountBeforeCreate = visible.count
                    showingNewClubSheet = true
                })
                    .navigationTitle(title)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            }
        }
        .sheet(isPresented: $showingSwitcher) {
            ClubSwitcherView()
        }
        .sheet(isPresented: $showingNewClubSheet, onDismiss: handleNewClubSheetDismiss) {
            NavigationStack {
                NewClubFormView()
            }
        }
        .task(id: clubReconcileSignature(visible)) {
            activeClubStore.reconcileWithVisibleClubs(visible)
        }
    }

    private func handleNewClubSheetDismiss() {
        defer { clubCountBeforeCreate = nil }
        guard let priorCount = clubCountBeforeCreate else { return }
        let current = visibleClubs
        guard current.count > priorCount else { return }
        if let newest = current.first {
            activeClubStore.setActiveClub(newest)
        }
    }

    private func clubReconcileSignature(_ clubs: [BookClub]) -> String {
        clubs.map(\.cloudZoneName).joined(separator: "|")
    }

    private var visibleClubs: [BookClub] {
        allClubs.filter { !SchemaPrimeDataCleanup.isSchemaPrime($0) }
    }

    private var clubSwitcherPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarLeading
        #else
        return .navigation
        #endif
    }
}

private struct ClubSwitcherButton: View {
    let club: BookClub
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill")
                    .font(.subheadline)
                    .foregroundStyle(BookLoomStyle.indigo)
                Text(club.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.18), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch club. Active club: \(club.name)")
    }
}

struct NoActiveClubView: View {
    let onCreateClub: () -> Void

    @Environment(GoodreadsImportInbox.self) private var goodreadsInbox

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if !goodreadsInbox.pending.isEmpty {
                    PendingImportInboxSection(inbox: goodreadsInbox)
                }
                OnboardingHeroArtwork(maxHeight: 220)
                VStack(spacing: 6) {
                    Text("Create or Join a Club")
                        .font(.title.bold())
                        .foregroundStyle(BookLoomStyle.ink)
                    Text("Create a club if you are starting one. If someone already made the club in BookLoom, you can wait here and open their invite when it arrives.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: onCreateClub) {
                    Label("Create New Club", systemImage: "plus.circle.fill")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                ClubDataPrivacyNote()
                    .frame(maxWidth: 420)
            }
            .padding(18)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .bookLoomScreenBackground()
    }
}

/// Wraps the shared `ImportInboxBanner` with a heading and the explanation
/// users need when they share from Goodreads before creating a club: they
/// won't be able to import yet, but the queued shares aren't lost — create
/// a club first, then come back and tap a row.
private struct PendingImportInboxSection: View {
    let inbox: GoodreadsImportInbox

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Import Inbox", detail: "\(inbox.pending.count)")
            Text("Books you shared from Goodreads are waiting here. Create a club, then tap a row to add them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ImportInboxBanner(
                pending: inbox.pending,
                onTap: { url in inbox.present(url) },
                onRemove: { url in inbox.remove(url) }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ClubDataPrivacyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.icloud.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(BookLoomStyle.indigo)
                .symbolRenderingMode(.hierarchical)

            Text("BookLoom does not store club data on third-party servers. Clubs live in your private iCloud data or in shared iCloud data when a club owner invites members.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bookLoomCard(padding: 10)
    }
}

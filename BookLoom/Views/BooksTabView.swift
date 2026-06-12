import SwiftUI
import SwiftData

/// Top-level Club tab. Scoped to the currently active club via the
/// ActiveClubStore. Replaces the per-club home page that used to be reached
/// by drilling into a club from a top-level Clubs list — now Club is the
/// primary destination and clubs are switched via the toolbar account-style
/// switcher.
struct BooksTabView: View {
    @Binding private var path: NavigationPath

    init(path: Binding<NavigationPath> = .constant(NavigationPath())) {
        _path = path
    }

    var body: some View {
        ClubScopedScaffold(title: "Club") { club in
            BooksTabContent(club: club, path: $path)
        }
    }
}

private struct BooksTabContent: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(GoodreadsImportInbox.self) private var goodreadsInbox
    @Bindable var club: BookClub
    @Binding var path: NavigationPath
    private let syncStatus = SharedClubSyncStatus.shared

    /// Scoped to the active club at the database level so the view never
    /// materializes other clubs' submissions/polls just to filter them out in
    /// memory. The downstream `clubSubmissions`/`clubPolls` filters remain as a
    /// belt-and-suspenders identity check.
    @Query private var submissions: [BookSubmission]
    @Query private var polls: [SelectionPoll]

    init(club: BookClub, path: Binding<NavigationPath>) {
        self.club = club
        _path = path

        let zone = club.cloudZoneName
        _submissions = Query(
            filter: #Predicate<BookSubmission> { $0.bookClub?.cloudZoneName == zone },
            sort: \.submittedAt
        )
        _polls = Query(
            filter: #Predicate<SelectionPoll> { $0.bookClub?.cloudZoneName == zone },
            sort: \.createdAt,
            order: .reverse
        )
    }

    @State private var showingPickConfirmation: Bool = false
    @State private var showingCompleteConfirmation: Bool = false
    @State private var showingMoveCurrentToProposalsConfirmation: Bool = false
    @State private var showingAddBook: Bool = false
    @State private var showingKeepInLibraryConfirmation: Bool = false
    @State private var pendingLibrarySubmission: BookSubmission?
    @State private var libraryTab: LibraryTab = .proposed
    @State private var librarySearchText: String = ""
    @State private var didResolveInitialLibraryTab = false

    /// Lazily created once the SwiftData context and member identity are
    /// available. Owns the sync orchestration and SwiftData mutations that used
    /// to live in this view's action methods (see #18).
    @State private var coordinator: ClubActionCoordinator?

    private func makeCoordinator() -> ClubActionCoordinator {
        if let coordinator { return coordinator }
        let created = ClubActionCoordinator(context: context, memberIdentity: memberIdentity)
        coordinator = created
        return created
    }

    var body: some View {
        let displayedSections = sections
        let filteredProposed = filteredSubmissions(displayedSections.proposed)
        let filteredCompleted = filteredSubmissions(displayedSections.completed)
        let filteredImports = filteredImportItems(goodreadsInbox.pending)

        List {
            Section {
                BooksHeader(club: club, sections: displayedSections)
                    .bookLoomListRow(top: 6, bottom: 8)

                if let syncIssue = syncStatus.issue(for: club) {
                    SyncStatusBanner(issue: syncIssue)
                        .bookLoomListRow(top: 4, bottom: 8)
                }

                if let current = displayedSections.current {
                    CurrentSubmissionRow(
                        submission: current,
                        onMarkRead: { showingCompleteConfirmation = true },
                        onMoveBack: { showingMoveCurrentToProposalsConfirmation = true }
                    )
                    .swipeActions(edge: .trailing) {
                        Button {
                            markComplete(current)
                        } label: {
                            Label("Complete", systemImage: "checkmark.seal.fill")
                        }
                        .tint(BookLoomStyle.sage)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            moveCurrentToProposals(current)
                        } label: {
                            Label("Move Back", systemImage: "tray.full.fill")
                        }
                        .tint(BookLoomStyle.plum)
                    }
                    .bookLoomListRow(top: 10, bottom: 10)
                } else {
                    InlineEmptyState(
                        systemImage: "shuffle.circle.fill",
                        title: "No Current Book",
                        message: "Add proposals, then pick one when the group is ready."
                    )
                    .bookLoomListRow(top: 10, bottom: 10)
                }

                if let poll = activePoll {
                    ActivePollCard(poll: poll, candidates: clubSubmissions)
                        .bookLoomListRow(top: 2, bottom: 8)
                }

                LibrarySearchField(text: $librarySearchText)
                    .bookLoomListRow(top: 8, bottom: 6)

                LibraryTabPicker(
                    selection: $libraryTab,
                    proposedCount: displayedSections.proposed.count,
                    readCount: displayedSections.completed.count,
                    importCount: goodreadsInbox.pending.count
                )
                .bookLoomListRow(top: 4, bottom: 6)

                LibraryActionBar(
                    selectedTab: libraryTab,
                    canPickRandom: !displayedSections.proposed.isEmpty,
                    canVote: activePoll != nil || displayedSections.proposed.count >= 2,
                    onAddBook: { showingAddBook = true },
                    onPickRandom: { showingPickConfirmation = true },
                    onVote: openOrCreatePoll
                )
                .bookLoomListRow(top: 2, bottom: 6)

                switch libraryTab {
                case .proposed:
                    if displayedSections.proposed.isEmpty {
                        InlineEmptyState(
                            systemImage: "tray.full",
                            title: "No Proposals",
                            message: "Tap Add Book to build the next pick list."
                        )
                        .bookLoomListRow()
                    } else if filteredProposed.isEmpty {
                        InlineEmptyState(
                            systemImage: "magnifyingglass",
                            title: "No Matching Proposals",
                            message: "Try another title, author, or member."
                        )
                        .bookLoomListRow()
                    } else {
                        ForEach(filteredProposed) { submission in
                            BooksTabRow(submission: submission)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(submission)
                                    } label: {
                                        Label("Delete", systemImage: "trash.fill")
                                    }

                                    Button {
                                        assignCurrent(submission)
                                    } label: {
                                        Label("Set Current", systemImage: "book.fill")
                                    }
                                    .tint(BookLoomStyle.sage)

                                    Button {
                                        markComplete(submission)
                                        libraryTab = .read
                                        offerToKeepInLibrary(submission)
                                    } label: {
                                        Label("Mark Read", systemImage: "checkmark.seal.fill")
                                    }
                                    .tint(BookLoomStyle.indigo)
                                }
                                .swipeActions(edge: .leading) {
                                    if GoodreadsImportInbox.canMoveToShelf(submission) {
                                        Button {
                                            moveSubmissionToImports(submission)
                                        } label: {
                                            Label("Move to Imports", systemImage: "tray.and.arrow.down.fill")
                                        }
                                        .tint(BookLoomStyle.indigo)
                                    }
                                }
                                .bookLoomListRow()
                        }
                        .onDelete { offsets in
                            delete(filteredProposed, at: offsets)
                        }
                    }
                case .read:
                    if displayedSections.completed.isEmpty {
                        InlineEmptyState(
                            systemImage: "checkmark.seal",
                            title: "No Books Read Yet",
                            message: "Books the club finishes show up here."
                        )
                        .bookLoomListRow()
                    } else if filteredCompleted.isEmpty {
                        InlineEmptyState(
                            systemImage: "magnifyingglass",
                            title: "No Matching Read Books",
                            message: "Try another title, author, or member."
                        )
                        .bookLoomListRow()
                    } else {
                        ForEach(filteredCompleted) { submission in
                            BooksTabRow(submission: submission)
                                .bookLoomListRow()
                        }
                        .onDelete { offsets in
                            delete(filteredCompleted, at: offsets)
                        }
                    }
                case .imports:
                    if goodreadsInbox.pending.isEmpty {
                        InlineEmptyState(
                            systemImage: "tray",
                            title: "No Imports",
                            message: "Books shared from Goodreads, pasted into Add, or moved out of club proposals land here until you choose where they go."
                        )
                        .bookLoomListRow()
                    } else if filteredImports.isEmpty {
                        InlineEmptyState(
                            systemImage: "magnifyingglass",
                            title: "No Matching Imports",
                            message: "Try another title, author, or link."
                        )
                        .bookLoomListRow()
                    } else {
                        ImportInboxBanner(
                            pending: filteredImports,
                            onTap: { url in goodreadsInbox.present(url) },
                            onRemove: { url in goodreadsInbox.remove(url) }
                        )
                        .bookLoomListRow()
                    }
                }
            }
        }
        .bookLoomListStyle()
        .refreshable {
            refreshShelfFromSharedQueue(selectShelfWhenPending: false)
            await syncClubForCurrentRole()
        }
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationDestination(for: BookSubmission.self) { sub in
            SubmissionDetailView(submission: sub)
        }
        .navigationDestination(for: SelectionPoll.self) { poll in
            SelectionPollDetailView(poll: poll, candidates: clubSubmissions)
        }
        .sheet(isPresented: $showingAddBook) {
            AddSubmissionView(club: club)
        }
        .toolbar {
            if club.shareIsActive {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        Task { await syncClubForCurrentRole() }
                    } label: {
                        Label("Refresh Club", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .confirmationDialog(
            "Pick the next book?",
            isPresented: $showingPickConfirmation,
            titleVisibility: .visible
        ) {
            Button("Pick Random Book") {
                pickRandomNext()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if displayedSections.current != nil {
                Text("This will mark the current book as completed and pick a random proposal as the next read.")
            } else {
                Text("This will pick a random proposal as the current read.")
            }
        }
        .confirmationDialog(
            "Mark the current book as read?",
            isPresented: $showingCompleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark Read") {
                if let current = displayedSections.current {
                    markComplete(current)
                    offerToKeepInLibrary(current)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves the current book into reading history and clears the current slot.")
        }
        .confirmationDialog(
            "Move the current book back to proposals?",
            isPresented: $showingMoveCurrentToProposalsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move Back to Proposals") {
                if let current = displayedSections.current {
                    moveCurrentToProposals(current)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the current book and returns it to the proposal list.")
        }
        .confirmationDialog(
            "Keep this book on your Shelf?",
            isPresented: $showingKeepInLibraryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save to Shelf") {
                if let pendingLibrarySubmission {
                    saveToPersonalLibrary(pendingLibrarySubmission)
                }
                pendingLibrarySubmission = nil
            }
            Button("Not Now", role: .cancel) {
                pendingLibrarySubmission = nil
            }
        } message: {
            Text("Club read history and your Shelf are separate. Save a Shelf copy if you own, borrowed, or listened to this book.")
        }
        .task(id: club.cloudZoneName) {
            if let forced = screenshotInitialLibraryTab {
                libraryTab = forced
                refreshShelfFromSharedQueue(selectShelfWhenPending: false)
            } else {
                refreshShelfFromSharedQueue(selectShelfWhenPending: !didResolveInitialLibraryTab)
            }
            didResolveInitialLibraryTab = true
            await syncClubForCurrentRole()
        }
        .onChange(of: libraryTab) { _, tab in
            guard tab == .imports else { return }
            refreshShelfFromSharedQueue(selectShelfWhenPending: false)
        }
        .onChange(of: goodreadsInbox.pending.count) { oldValue, newValue in
            guard screenshotInitialLibraryTab == nil else { return }
            if oldValue == 0, newValue > 0 {
                libraryTab = .imports
            }
        }
    }

    private var sections: BookClubSubmissionSections {
        BookClubSubmissionSections(submissions: clubSubmissions)
    }

    /// During screenshot capture (`-screenshotRoute`), pin the club book segment
    /// so each screen captures the same view regardless of pending Shelf items.
    private var screenshotInitialLibraryTab: LibraryTab? {
        guard let route = AppLaunchOptions.screenshotRoute else { return nil }
        switch route {
        case "shelf", "import", "imports": return .imports
        case "books", "clubs", "clubHome": return .proposed
        default: return nil
        }
    }

    private var clubSubmissions: [BookSubmission] {
        submissions.filter { $0.bookClub?.persistentModelID == club.persistentModelID }
    }

    private var clubPolls: [SelectionPoll] {
        polls.filter { $0.bookClub?.persistentModelID == club.persistentModelID }
    }

    private var activePoll: SelectionPoll? {
        clubPolls.first(where: \.isOpen)
    }

    private var librarySearchQuery: String {
        librarySearchText.trimmed
    }

    private func filteredSubmissions(_ submissions: [BookSubmission]) -> [BookSubmission] {
        let query = librarySearchQuery
        guard !query.isEmpty else { return submissions }
        return submissions.filter { submission in
            matchesSearch(submission.displayTitle, query: query)
                || matchesSearch(submission.displayAuthor, query: query)
                || matchesSearch(submission.displaySubmitter, query: query)
                || matchesSearch(submission.isbn, query: query)
                || matchesSearch(submission.externalID, query: query)
        }
    }

    private func filteredImportItems(_ items: [SharedImportInbox.PendingImport]) -> [SharedImportInbox.PendingImport] {
        let query = librarySearchQuery
        guard !query.isEmpty else { return items }
        return items.filter { item in
            matchesSearch(item.displayTitle, query: query)
                || matchesSearch(item.displayAuthor, query: query)
                || matchesSearch(item.url.absoluteString, query: query)
        }
    }

    private func matchesSearch(_ value: String?, query: String) -> Bool {
        guard let value, !value.trimmed.isEmpty else { return false }
        return value.localizedCaseInsensitiveContains(query)
    }

    private func syncClubForCurrentRole() async {
        await makeCoordinator().synchronizeIfNeeded(club)
    }

    private func refreshShelfFromSharedQueue(selectShelfWhenPending: Bool) {
        goodreadsInbox.refresh()
        goodreadsInbox.prefetchAll()
        if selectShelfWhenPending, !goodreadsInbox.pending.isEmpty {
            libraryTab = .imports
        }
    }

    private func pickRandomNext() {
        makeCoordinator().pickRandomNext(in: club, from: sections.proposed)
    }

    private func openOrCreatePoll() {
        guard let poll = makeCoordinator().openOrCreatePoll(
            in: club,
            activePoll: activePoll,
            proposed: sections.proposed
        ) else { return }
        path.append(poll)
    }

    private func assignCurrent(_ submission: BookSubmission) {
        makeCoordinator().assignCurrent(submission, in: club)
    }

    private func markComplete(_ submission: BookSubmission) {
        makeCoordinator().markComplete(submission, in: club)
    }

    private func offerToKeepInLibrary(_ submission: BookSubmission) {
        guard !makeCoordinator().hasPersonalLibraryCopy(of: submission) else { return }
        pendingLibrarySubmission = submission
        showingKeepInLibraryConfirmation = true
    }

    private func saveToPersonalLibrary(_ submission: BookSubmission) {
        makeCoordinator().saveToPersonalLibrary(submission)
    }

    private func moveCurrentToProposals(_ submission: BookSubmission) {
        makeCoordinator().moveCurrentToProposals(submission, in: club)
    }

    private func delete(_ items: [BookSubmission], at offsets: IndexSet) {
        makeCoordinator().delete(items, at: offsets, in: club)
    }

    private func delete(_ submission: BookSubmission, shouldSave: Bool = true) {
        makeCoordinator().delete(submission, in: club, shouldSave: shouldSave)
    }

    private func moveSubmissionToImports(_ submission: BookSubmission) {
        guard makeCoordinator().moveSubmissionToImports(submission, inbox: goodreadsInbox, in: club) else { return }
        libraryTab = .imports
    }
}

private struct BooksHeader: View {
    let club: BookClub
    let sections: BookClubSubmissionSections
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let memberCount = club.displayedMemberCount
        let sharing = sharingDescriptor

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                BrandBadge(size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(club.name)
                        .font(.headline.bold())
                        .foregroundStyle(BookLoomStyle.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Label(sharing.label, systemImage: sharing.icon)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            metricsLayout {
                MetricTile(value: "\(sections.proposed.count)", label: "proposed", systemImage: "tray.full.fill", tint: BookLoomStyle.plum)
                MetricTile(value: "\(sections.completed.count)", label: "read", systemImage: "checkmark.seal.fill", tint: BookLoomStyle.indigo)
                NavigationLink {
                    ClubManagementView(club: club)
                } label: {
                    MetricTile(value: "\(memberCount)", label: memberMetricLabel(for: memberCount), systemImage: "person.2.fill", tint: BookLoomStyle.sage)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage club, \(memberCount) \(memberMetricLabel(for: memberCount))")
            }
        }
        .bookLoomCard(padding: 12)
    }

    /// Stack metric tiles vertically when accessibility text sizes would
    /// otherwise compress each label to a single character.
    private var metricsLayout: AnyLayout {
        dynamicTypeSize.adaptiveLayout(expanded: VStackLayout(spacing: 8), compact: HStackLayout(spacing: 10))
    }

    private func memberMetricLabel(for count: Int) -> String {
        count == 1 ? "member" : "members"
    }

    private var sharingDescriptor: (label: String, icon: String) {
        if !club.isOwner {
            return ("Shared with you", "person.2.fill")
        }
        return club.shareIsActive
            ? ("Sharing enabled", "icloud.fill")
            : ("Owner", "person.crop.circle.fill")
    }
}

private struct BooksTabRow: View {
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var submission: BookSubmission

    var body: some View {
        NavigationLink(value: submission) {
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    BookCoverTile(
                        title: submission.displayTitle,
                        author: submission.displayAuthor,
                        coverURL: submission.coverImageURL,
                        width: 74,
                        height: 104
                    )

                    CompactBookStatusBadge(status: submission.status)
                        .offset(x: 8, y: -8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(submission.displayTitle)
                            .font(.headline.bold())
                            .foregroundStyle(BookLoomStyle.ink)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 4)
                            .fixedSize(horizontal: false, vertical: true)
                        if !submission.displayAuthor.isEmpty {
                            Text(submission.displayAuthor)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    PersonalRatingLine(stars: ownRating?.stars)

                    metadataLayout {
                        Label(submission.displaySubmitter, systemImage: "person.fill")
                        if !(submission.notes ?? []).isEmpty {
                            Label("\((submission.notes ?? []).count)", systemImage: "note.text")
                        }
                        if let completedAt = submission.completedAt, submission.status == .completed {
                            Label(completedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.prefersExpandedControlLayout ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .bookLoomCard(padding: 12)
        .accessibilityHint(submission.status.displayName)
    }

    private var ownRating: Rating? {
        (submission.ratings ?? [])
            .first { $0.matches(memberID: memberIdentity.memberID, memberName: memberIdentity.name) }
    }

    private var metadataLayout: AnyLayout {
        dynamicTypeSize.adaptiveLayout(expanded: VStackLayout(alignment: .leading, spacing: 4), compact: HStackLayout(spacing: 12))
    }
}

private struct CompactBookStatusBadge: View {
    let status: BookSubmissionStatus

    var body: some View {
        Image(systemName: status.systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(status.tint)
            .frame(width: 30, height: 30)
            .background(BookLoomStyle.paper.opacity(0.94), in: Circle())
            .overlay {
                Circle()
                    .stroke(status.tint.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: BookLoomStyle.ink.opacity(0.16), radius: 4, y: 2)
            .accessibilityLabel(status.displayName)
    }
}

private struct PersonalRatingLine: View {
    let stars: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text("Your rating")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: index <= (stars ?? 0) ? "star.fill" : "star")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(index <= (stars ?? 0) ? BookLoomStyle.gold : Color.secondary.opacity(0.32))
                }
            }
            .accessibilityLabel(stars.map { "\($0) out of 5 stars" } ?? "Not rated")
        }
    }
}

private struct CurrentSubmissionRow: View {
    @Bindable var submission: BookSubmission
    let onMarkRead: () -> Void
    let onMoveBack: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: submission) {
                contentLayout {
                    BookCoverTile(
                        title: submission.displayTitle,
                        author: submission.displayAuthor,
                        coverURL: submission.coverImageURL,
                        width: 72,
                        height: 98
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        StatusPill(status: .current)
                        Text(submission.displayTitle)
                            .font(.headline.bold())
                            .foregroundStyle(BookLoomStyle.ink)
                            .lineLimit(dynamicTypeSize.prefersExpandedControlLayout ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !submission.displayAuthor.isEmpty {
                            Text(submission.displayAuthor)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(dynamicTypeSize.prefersExpandedControlLayout ? nil : 1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        metadataLayout {
                            Label(submission.ratingSummary.displayValue, systemImage: "star.fill")
                            Label("\((submission.notes ?? []).count) notes", systemImage: "note.text")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.prefersExpandedControlLayout ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if !dynamicTypeSize.prefersExpandedControlLayout {
                        Spacer(minLength: 0)
                    }
                }
            }
            .buttonStyle(.plain)

            actionLayout {
                BookLoomActionButton(
                    title: "Mark Read",
                    systemImage: "checkmark.seal.fill",
                    tint: BookLoomStyle.sage,
                    prominent: true,
                    action: onMarkRead
                )
                BookLoomActionButton(
                    title: "Move Back",
                    systemImage: "tray.full.fill",
                    tint: BookLoomStyle.plum,
                    prominent: false,
                    action: onMoveBack
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .bookLoomCard(padding: 12)
    }

    private var contentLayout: AnyLayout {
        dynamicTypeSize.adaptiveLayout(expanded: VStackLayout(alignment: .leading, spacing: 12), compact: HStackLayout(spacing: 14))
    }

    private var metadataLayout: AnyLayout {
        dynamicTypeSize.adaptiveLayout(expanded: VStackLayout(alignment: .leading, spacing: 4), compact: HStackLayout(spacing: 12))
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.adaptiveLayout(expanded: VStackLayout(spacing: 8), compact: HStackLayout(spacing: 8))
    }
}

struct LibrarySearchField: View {
    @Binding var text: String
    let placeholder: String
    let clearAccessibilityLabel: String

    init(
        text: Binding<String>,
        placeholder: String = "Search club books",
        clearAccessibilityLabel: String = "Clear club book search"
    ) {
        _text = text
        self.placeholder = placeholder
        self.clearAccessibilityLabel = clearAccessibilityLabel
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearAccessibilityLabel)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(BookLoomStyle.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LibraryActionBar: View {
    let selectedTab: LibraryTab
    let canPickRandom: Bool
    let canVote: Bool
    let onAddBook: () -> Void
    let onPickRandom: () -> Void
    let onVote: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        actionLayout {
            Button(action: onAddBook) {
                actionLabel(
                    title: "Add",
                    systemImage: "plus",
                    background: BookLoomStyle.indigo,
                    foreground: Color.white
                )
            }
            .buttonStyle(.plain)

            if selectedTab == .proposed {
                Button(action: onPickRandom) {
                    actionLabel(
                        title: "Random",
                        systemImage: "shuffle",
                        background: canPickRandom ? BookLoomStyle.plum.opacity(0.16) : Color.secondary.opacity(0.10),
                        foreground: canPickRandom ? BookLoomStyle.plum : Color.secondary
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canPickRandom)

                Button(action: onVote) {
                    actionLabel(
                        title: "Vote",
                        systemImage: "checklist",
                        background: canVote ? BookLoomStyle.sage.opacity(0.18) : Color.secondary.opacity(0.10),
                        foreground: canVote ? BookLoomStyle.sage : Color.secondary
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canVote)
            }
        }
    }

    private func actionLabel(title: String, systemImage: String, background: Color, foreground: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(actionFont)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, dynamicTypeSize.prefersExpandedControlLayout ? 12 : 8)
            .frame(maxWidth: dynamicTypeSize.prefersExpandedControlLayout ? .infinity : nil)
            .bookLoomActionWidth(minWidth: 132)
            .frame(minHeight: dynamicTypeSize.prefersExpandedControlLayout ? 52 : 40)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
            .accessibilityLabel(title)
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.adaptiveLayout(expanded: VStackLayout(spacing: 8), compact: HStackLayout(spacing: 8))
    }

    private var actionFont: Font {
        dynamicTypeSize.prefersExpandedControlLayout
            ? .body.weight(.bold)
            : .footnote.weight(.semibold)
    }
}

private struct ActivePollCard: View {
    @Bindable var poll: SelectionPoll
    let candidates: [BookSubmission]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let tally = SelectionPollScorer.tally(votes: poll.votes ?? [], candidateIDs: poll.candidateIDs)
        let leader = tally.leader.flatMap { result in
            candidates.first { $0.selectionID == result.id }
        }

        NavigationLink(value: poll) {
            VStack(alignment: .leading, spacing: 10) {
                headerLayout {
                    Label("Voting Open", systemImage: "checklist")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BookLoomStyle.ink)
                    if !dynamicTypeSize.prefersExpandedControlLayout {
                        Spacer()
                    }
                    TintedCapsuleLabel(
                        text: "\(poll.candidateIDs.count) books",
                        tint: BookLoomStyle.sage,
                        horizontalPadding: 7,
                        verticalPadding: 3
                    )
                }

                if let leader {
                    Text(tally.hasTie ? "Current tie includes \(leader.displayTitle)." : "Current leader: \(leader.displayTitle).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("Rank the proposed books to help choose the next read.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Label("\((poll.votes ?? []).count) ballots cast", systemImage: "person.2.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .bookLoomCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private var headerLayout: AnyLayout {
        dynamicTypeSize.adaptiveLayout(expanded: VStackLayout(alignment: .leading, spacing: 6), compact: HStackLayout(alignment: .firstTextBaseline))
    }
}

private struct SyncStatusBanner: View {
    let issue: SyncIssue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.systemImage)
                .foregroundStyle(iconTint)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 10)
    }

    private var iconTint: Color {
        switch issue.severity {
        case .offline: return .secondary
        case .warning: return .orange
        }
    }
}

private enum LibraryTab: CaseIterable, Identifiable {
    case proposed
    case read
    case imports
    var id: Self { self }
    var title: String {
        switch self {
        case .proposed: return "Proposed"
        case .read: return "Read"
        case .imports: return "Imports"
        }
    }
}

private struct LibraryTabPicker: View {
    @Binding var selection: LibraryTab
    let proposedCount: Int
    let readCount: Int
    let importCount: Int

    var body: some View {
        AdaptiveSegmentedControl(
            "Club book view",
            selection: $selection,
            options: LibraryTab.allCases
        ) { tab in
            Text(label(for: tab, count: count(for: tab)))
        }
    }

    private func label(for tab: LibraryTab, count: Int) -> String {
        count > 0 ? "\(tab.title) (\(count))" : tab.title
    }

    private func count(for tab: LibraryTab) -> Int {
        switch tab {
        case .proposed: proposedCount
        case .read: readCount
        case .imports: importCount
        }
    }
}

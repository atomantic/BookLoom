import SwiftUI
import SwiftData

/// Top-level Books tab. Scoped to the currently active club via the
/// ActiveClubStore. Replaces the per-club home page that used to be reached
/// by drilling into a club from a top-level Clubs list — now Books is the
/// primary destination and clubs are switched via the toolbar account-style
/// switcher.
struct BooksTabView: View {
    var body: some View {
        ClubScopedScaffold(title: "Books") { club in
            BooksTabContent(club: club)
        }
    }
}

private struct BooksTabContent: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(GoodreadsImportInbox.self) private var goodreadsInbox
    @Bindable var club: BookClub
    @ObservedObject private var syncStatus = SharedClubSyncStatus.shared
    @Query(sort: \BookSubmission.submittedAt) private var submissions: [BookSubmission]

    @State private var showingPickConfirmation: Bool = false
    @State private var showingCompleteConfirmation: Bool = false
    @State private var showingMoveCurrentToProposalsConfirmation: Bool = false
    @State private var libraryTab: LibraryTab = .read
    @State private var didResolveInitialLibraryTab = false

    var body: some View {
        let displayedSections = sections

        List {
            Section {
                BooksHeader(club: club, sections: displayedSections)
                    .bookLoomListRow(top: 6, bottom: 8)
            }

            if let syncIssue = syncStatus.issue(for: club) {
                Section {
                    SyncStatusBanner(issue: syncIssue)
                        .bookLoomListRow(top: 4, bottom: 8)
                }
            }

            Section {
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
                        .tint(.green)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            moveCurrentToProposals(current)
                        } label: {
                            Label("Move Back", systemImage: "tray.full.fill")
                        }
                        .tint(BookLoomStyle.plum)
                    }
                } else {
                    InlineEmptyState(
                        systemImage: "shuffle.circle.fill",
                        title: "No Current Book",
                        message: "Add proposals, then pick one when the group is ready."
                    )
                }
            } header: {
                SectionTitle(title: "Currently Reading")
            }
            .bookLoomListRow()

            Section {
                ProposedActionBar(
                    club: club,
                    canPickRandom: !displayedSections.proposed.isEmpty,
                    onPickRandom: { showingPickConfirmation = true }
                )
                .bookLoomListRow(top: 4, bottom: 6)

                if displayedSections.proposed.isEmpty {
                    InlineEmptyState(
                        systemImage: "tray.full",
                        title: "No Proposals",
                        message: "Tap Add Book to build the next pick list."
                    )
                    .bookLoomListRow()
                } else {
                    ForEach(displayedSections.proposed) { submission in
                        BooksTabRow(submission: submission)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    assignCurrent(submission)
                                } label: {
                                    Label("Set Current", systemImage: "book.fill")
                                }
                                .tint(BookLoomStyle.sage)

                                Button {
                                    markComplete(submission)
                                    libraryTab = .read
                                } label: {
                                    Label("Mark Read", systemImage: "checkmark.seal.fill")
                                }
                                .tint(BookLoomStyle.indigo)
                            }
                            .swipeActions(edge: .leading) {
                                if GoodreadsImportInbox.canMoveToShelf(submission) {
                                    Button {
                                        moveSubmissionToShelf(submission)
                                    } label: {
                                        Label("Move to Shelf", systemImage: "tray.and.arrow.down.fill")
                                    }
                                    .tint(BookLoomStyle.indigo)
                                }
                            }
                            .bookLoomListRow()
                    }
                    .onDelete { offsets in
                        delete(displayedSections.proposed, at: offsets)
                    }
                }
            } header: {
                SectionTitle(title: "Proposed", detail: "\(displayedSections.proposed.count)")
            }

            Section {
                LibraryTabPicker(
                    selection: $libraryTab,
                    readCount: displayedSections.completed.count,
                    shelfCount: goodreadsInbox.pending.count
                )
                .bookLoomListRow(top: 4, bottom: 6)

                switch libraryTab {
                case .read:
                    if displayedSections.completed.isEmpty {
                        InlineEmptyState(
                            systemImage: "checkmark.seal",
                            title: "No Books Read Yet",
                            message: "Books the club finishes show up here."
                        )
                        .bookLoomListRow()
                    } else {
                        ForEach(displayedSections.completed) { submission in
                            BooksTabRow(submission: submission)
                                .bookLoomListRow()
                        }
                        .onDelete { offsets in
                            delete(displayedSections.completed, at: offsets)
                        }
                    }
                case .shelf:
                    if goodreadsInbox.pending.isEmpty {
                        InlineEmptyState(
                            systemImage: "tray",
                            title: "Shelf is Empty",
                            message: "Books shared from Goodreads (or pasted via Add Book) land here until you add them to the club."
                        )
                        .bookLoomListRow()
                    } else {
                        ImportInboxBanner(
                            pending: goodreadsInbox.pending,
                            onTap: { url in goodreadsInbox.present(url) },
                            onRemove: { url in goodreadsInbox.remove(url) }
                        )
                        .bookLoomListRow()
                    }
                }
            } header: {
                SectionTitle(title: "Library")
            }
        }
        .listStyle(.plain)
        .refreshable {
            refreshShelfFromSharedQueue(selectShelfWhenPending: false)
            await syncClubForCurrentRole()
        }
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationDestination(for: BookSubmission.self) { sub in
            SubmissionDetailView(submission: sub)
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
                if let current = sections.current {
                    markComplete(current)
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
                if let current = sections.current {
                    moveCurrentToProposals(current)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the current book and returns it to the proposal list.")
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
            guard tab == .shelf else { return }
            refreshShelfFromSharedQueue(selectShelfWhenPending: false)
        }
        .onChange(of: goodreadsInbox.pending.count) { oldValue, newValue in
            guard screenshotInitialLibraryTab == nil else { return }
            if oldValue == 0, newValue > 0 {
                libraryTab = .shelf
            }
        }
    }

    private var sections: BookClubSubmissionSections {
        BookClubSubmissionSections(submissions: clubSubmissions)
    }

    /// During screenshot capture (`-screenshotRoute`), pin the Library segment
    /// so each screen captures the same view regardless of pending Shelf items.
    private var screenshotInitialLibraryTab: LibraryTab? {
        guard let route = AppLaunchOptions.screenshotRoute else { return nil }
        switch route {
        case "shelf", "import": return .shelf
        case "books", "clubs", "clubHome": return .read
        default: return nil
        }
    }

    private var clubSubmissions: [BookSubmission] {
        submissions.filter { $0.bookClub?.persistentModelID == club.persistentModelID }
    }

    private func syncClubForCurrentRole() async {
        await SharedClubSync.synchronizeIfNeeded(
            club,
            context: context,
            localMemberID: memberIdentity.memberID,
            localMemberName: memberIdentity.name
        )
    }

    private func refreshShelfFromSharedQueue(selectShelfWhenPending: Bool) {
        goodreadsInbox.refresh()
        goodreadsInbox.prefetchAll()
        if selectShelfWhenPending, !goodreadsInbox.pending.isEmpty {
            libraryTab = .shelf
        }
    }

    private func pickRandomNext() {
        guard let pick = BookPicker.pickNext(from: sections.proposed) else { return }
        assignCurrent(pick)
    }

    private func assignCurrent(_ submission: BookSubmission) {
        SelectionPollCoordinator.promoteWinner(submission, in: club, actorMemberID: memberIdentity.memberID)
        DiscussionPromptLibrary.ensureStarterPrompts(for: submission, context: context)
        saveClubChanges()
    }

    private func markComplete(_ submission: BookSubmission) {
        BookSubmissionStatusEditor.markComplete(submission, in: club, actorMemberID: memberIdentity.memberID)
        saveClubChanges()
    }

    private func moveCurrentToProposals(_ submission: BookSubmission) {
        BookSubmissionStatusEditor.moveToProposals(submission, in: club, actorMemberID: memberIdentity.memberID)
        saveClubChanges()
    }

    private func delete(_ items: [BookSubmission], at offsets: IndexSet) {
        for index in offsets {
            context.delete(items[index])
        }
        saveClubChanges()
    }

    private func moveSubmissionToShelf(_ submission: BookSubmission) {
        guard goodreadsInbox.moveSubmissionToShelf(submission, context: context) else { return }
        saveClubChanges()
        libraryTab = .shelf
    }

    private func saveClubChanges() {
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
        } catch {
            assertionFailure("Failed to save club changes: \(error.localizedDescription)")
        }
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
                    MetricTile(value: "\(memberCount)", label: "members", systemImage: "person.2.fill", tint: BookLoomStyle.sage)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage club, \(memberCount) members")
            }
        }
        .bookLoomCard(padding: 12)
    }

    /// Stack metric tiles vertically when accessibility text sizes would
    /// otherwise compress each label to a single character.
    private var metricsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
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

                    HStack(spacing: 12) {
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
                    .lineLimit(1)
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
}

private struct CompactBookStatusBadge: View {
    let status: BookSubmissionStatus

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(BookLoomStyle.paper.opacity(0.94), in: Circle())
            .overlay {
                Circle()
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: BookLoomStyle.ink.opacity(0.16), radius: 4, y: 2)
            .accessibilityLabel(status.displayName)
    }

    private var systemImage: String {
        switch status {
        case .proposed: "tray.full.fill"
        case .current: "book.fill"
        case .completed: "checkmark.seal.fill"
        case .skipped: "forward.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .proposed: BookLoomStyle.plum
        case .current: BookLoomStyle.sage
        case .completed: BookLoomStyle.indigo
        case .skipped: BookLoomStyle.coral
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: submission) {
                HStack(spacing: 14) {
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
                            .lineLimit(2)
                        if !submission.displayAuthor.isEmpty {
                            Text(submission.displayAuthor)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 12) {
                            Label(submission.ratingSummary.displayValue, systemImage: "star.fill")
                            Label("\((submission.notes ?? []).count) notes", systemImage: "note.text")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                CurrentActionButton(
                    title: "Mark Read",
                    systemImage: "checkmark.seal.fill",
                    tint: BookLoomStyle.sage,
                    prominent: true,
                    action: onMarkRead
                )
                CurrentActionButton(
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
}

private struct CurrentActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(prominent ? tint : tint.opacity(0.16), in: Capsule())
                .foregroundStyle(prominent ? Color.white : tint)
        }
        .buttonStyle(.plain)
    }
}

private struct ProposedActionBar: View {
    let club: BookClub
    let canPickRandom: Bool
    let onPickRandom: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        layout {
            NavigationLink {
                AddSubmissionView(club: club)
            } label: {
                actionLabel(
                    title: "Add Book",
                    systemImage: "plus",
                    background: BookLoomStyle.indigo,
                    foreground: Color.white
                )
            }
            .buttonStyle(.plain)

            Button(action: onPickRandom) {
                actionLabel(
                    title: "Pick Random",
                    systemImage: "shuffle",
                    background: canPickRandom ? BookLoomStyle.plum.opacity(0.16) : Color.secondary.opacity(0.10),
                    foreground: canPickRandom ? BookLoomStyle.plum : Color.secondary
                )
            }
            .buttonStyle(.plain)
            .disabled(!canPickRandom)
        }
    }

    private func actionLabel(title: String, systemImage: String, background: Color, foreground: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }
}

private struct SyncStatusBanner: View {
    let issue: SyncIssue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.systemImage)
                .foregroundStyle(iconTint)
                .font(.title3)
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
    case read
    case shelf
    var id: Self { self }
    var title: String {
        switch self {
        case .read: return "Read"
        case .shelf: return "Shelf"
        }
    }
}

private struct LibraryTabPicker: View {
    @Binding var selection: LibraryTab
    let readCount: Int
    let shelfCount: Int

    var body: some View {
        Picker("Library view", selection: $selection) {
            Text(label(for: .read, count: readCount)).tag(LibraryTab.read)
            Text(label(for: .shelf, count: shelfCount)).tag(LibraryTab.shelf)
        }
        .pickerStyle(.segmented)
    }

    private func label(for tab: LibraryTab, count: Int) -> String {
        count > 0 ? "\(tab.title) (\(count))" : tab.title
    }
}

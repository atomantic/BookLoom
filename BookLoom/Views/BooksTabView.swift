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
    @Bindable var club: BookClub
    @ObservedObject private var syncStatus = SharedClubSyncStatus.shared
    @Query(sort: \BookSubmission.submittedAt) private var submissions: [BookSubmission]

    @State private var activeSheet: BooksTabSheet?
    @State private var showingPickConfirmation: Bool = false
    @State private var showingManualPickDialog: Bool = false
    @State private var showingCompleteConfirmation: Bool = false
    @State private var showingMoveCurrentToProposalsConfirmation: Bool = false

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
                    NavigationLink(value: current) {
                        CurrentSubmissionRow(submission: current)
                    }
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
                    BooksActionCard(
                        title: "Finished this book",
                        message: "Move the current book to reading history.",
                        buttonTitle: "Mark Read",
                        systemImage: "checkmark.seal.fill",
                        isDisabled: false
                    ) {
                        showingCompleteConfirmation = true
                    }
                    BooksActionCard(
                        title: "Not reading this yet",
                        message: "Return the current book to proposals without marking it read.",
                        buttonTitle: "Move Back to Proposals",
                        systemImage: "tray.full.fill",
                        isDisabled: false
                    ) {
                        showingMoveCurrentToProposalsConfirmation = true
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
                if displayedSections.proposed.isEmpty {
                    InlineEmptyState(
                        systemImage: "tray.full",
                        title: "No Proposals",
                        message: "Add a book to build the next pick list."
                    )
                } else {
                    BooksActionCard(
                        title: "Choose current book",
                        message: displayedSections.current == nil
                            ? "Set one proposal as the club's current read."
                            : "Set one proposal as current and move the existing current book to reading history.",
                        buttonTitle: "Choose Book",
                        systemImage: "book.closed.fill",
                        isDisabled: false
                    ) {
                        showingManualPickDialog = true
                    }

                    ForEach(displayedSections.proposed) { submission in
                        NavigationLink(value: submission) {
                            BooksTabRow(submission: submission)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                assignCurrent(submission)
                            } label: {
                                Label("Set Current", systemImage: "book.fill")
                            }
                            .tint(BookLoomStyle.sage)
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
            .bookLoomListRow()

            if !displayedSections.completed.isEmpty {
                Section {
                    ForEach(displayedSections.completed) { submission in
                        NavigationLink(value: submission) {
                            BooksTabRow(submission: submission)
                        }
                        .bookLoomListRow()
                    }
                    .onDelete { offsets in
                        delete(displayedSections.completed, at: offsets)
                    }
                } header: {
                    SectionTitle(title: "Reading History", detail: "\(displayedSections.completed.count)")
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await syncClubForCurrentRole()
        }
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationDestination(for: BookSubmission.self) { sub in
            SubmissionDetailView(submission: sub)
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task { await syncClubForCurrentRole() }
                } label: {
                    Label(syncDescriptor.label, systemImage: syncDescriptor.icon)
                }
                .disabled(!club.shareIsActive)
            }
            ToolbarItem {
                NavigationLink {
                    AddSubmissionView(club: club)
                } label: {
                    Label("Add Book", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPickConfirmation = true
                } label: {
                    Label("Pick Random", systemImage: "shuffle")
                }
                .disabled(displayedSections.proposed.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                NavigationLink {
                    ClubMembersView(club: club)
                } label: {
                    Label("Members", systemImage: "person.2.fill")
                }
            }
            if club.isOwner {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        activeSheet = .invite
                    } label: {
                        Label("Invite Members", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .invite:
                InviteView(club: club)
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
            "Choose the current book",
            isPresented: $showingManualPickDialog,
            titleVisibility: .visible
        ) {
            ForEach(sections.proposed) { submission in
                Button(submission.displayTitle) {
                    assignCurrent(submission)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if sections.current != nil {
                Text("The current book will move to reading history.")
            } else {
                Text("Select a proposal to set as the club's current read.")
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
            await syncClubForCurrentRole()
        }
    }

    private var sections: BookClubSubmissionSections {
        BookClubSubmissionSections(submissions: clubSubmissions)
    }

    private var clubSubmissions: [BookSubmission] {
        submissions.filter { $0.bookClub?.persistentModelID == club.persistentModelID }
    }

    private var syncDescriptor: (label: String, icon: String) {
        if !club.isOwner {
            return ("Refresh Club", "arrow.triangle.2.circlepath")
        }
        return club.shareIsActive ? ("Publish Changes", "arrow.up.icloud.fill") : ("Owner Device", "lock.fill")
    }

    private func syncClubForCurrentRole() async {
        await SharedClubSync.synchronizeIfNeeded(
            club,
            context: context,
            localMemberID: memberIdentity.memberID,
            localMemberName: memberIdentity.name
        )
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
        let now = Date.now
        submission.status = .completed
        submission.completedAt = now
        club.recordStatusOverride(
            StatusOverrideEntry(
                submissionSelectionID: submission.selectionID,
                statusRaw: BookSubmissionStatus.completed.rawValue,
                pickedAt: submission.pickedAt,
                completedAt: now,
                occurredAt: now,
                actorMemberID: memberIdentity.memberID
            )
        )
        saveClubChanges()
    }

    private func moveCurrentToProposals(_ submission: BookSubmission) {
        let now = Date.now
        submission.status = .proposed
        submission.pickedAt = nil
        submission.completedAt = nil
        club.recordStatusOverride(
            StatusOverrideEntry(
                submissionSelectionID: submission.selectionID,
                statusRaw: BookSubmissionStatus.proposed.rawValue,
                pickedAt: nil,
                completedAt: nil,
                occurredAt: now,
                actorMemberID: memberIdentity.memberID
            )
        )
        saveClubChanges()
    }

    private func delete(_ items: [BookSubmission], at offsets: IndexSet) {
        for index in offsets {
            context.delete(items[index])
        }
        saveClubChanges()
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

private enum BooksTabSheet: Identifiable {
    case invite

    var id: Int {
        switch self {
        case .invite: 0
        }
    }
}

private struct BooksHeader: View {
    let club: BookClub
    let sections: BookClubSubmissionSections

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
                        .lineLimit(1)
                    Label(sharing.label, systemImage: sharing.icon)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                MetricTile(value: "\(sections.proposed.count)", label: "proposed", systemImage: "tray.full.fill", tint: BookLoomStyle.plum)
                MetricTile(value: "\(sections.completed.count)", label: "read", systemImage: "checkmark.seal.fill", tint: BookLoomStyle.indigo)
                MetricTile(value: "\(memberCount)", label: "members", systemImage: "person.2.fill", tint: BookLoomStyle.sage)
            }
        }
        .bookLoomCard(padding: 12)
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
    @Bindable var submission: BookSubmission

    var body: some View {
        HStack(spacing: 12) {
            BookCoverTile(
                title: submission.displayTitle,
                author: submission.displayAuthor,
                coverURL: submission.coverImageURL,
                width: 48,
                height: 64
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(submission.displayTitle)
                            .font(.headline)
                            .foregroundStyle(BookLoomStyle.ink)
                            .lineLimit(2)
                        if !submission.displayAuthor.isEmpty {
                            Text(submission.displayAuthor)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 10)
                    StatusPill(status: submission.status)
                }

                HStack(spacing: 10) {
                    Label(submission.displaySubmitter, systemImage: "person.fill")
                    if submission.ratingSummary.count > 0 {
                        Label(submission.ratingSummary.displayValue, systemImage: "star.fill")
                    }
                    if !(submission.notes ?? []).isEmpty {
                        Label("\((submission.notes ?? []).count)", systemImage: "note.text")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .bookLoomCard(padding: 10)
    }
}

private struct CurrentSubmissionRow: View {
    @Bindable var submission: BookSubmission

    var body: some View {
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
        .bookLoomCard(padding: 12)
    }
}

private struct BooksActionCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BookLoomStyle.ink)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Label(buttonTitle, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
        }
        .bookLoomCard(padding: 10)
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

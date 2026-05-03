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

    @State private var showingPickConfirmation: Bool = false
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
                        NavigationLink(value: submission) {
                            BooksTabRow(submission: submission)
                        }
                        .buttonStyle(.plain)
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

            if !displayedSections.completed.isEmpty {
                Section {
                    ForEach(displayedSections.completed) { submission in
                        NavigationLink(value: submission) {
                            BooksTabRow(submission: submission)
                        }
                        .buttonStyle(.plain)
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
            await syncClubForCurrentRole()
        }
    }

    private var sections: BookClubSubmissionSections {
        BookClubSubmissionSections(submissions: clubSubmissions)
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
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
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

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink {
                AddSubmissionView(club: club)
            } label: {
                Label("Add Book", systemImage: "plus")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(BookLoomStyle.indigo, in: Capsule())
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)

            Button(action: onPickRandom) {
                Label("Pick Random", systemImage: "shuffle")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        canPickRandom ? BookLoomStyle.plum.opacity(0.16) : Color.secondary.opacity(0.10),
                        in: Capsule()
                    )
                    .foregroundStyle(canPickRandom ? BookLoomStyle.plum : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canPickRandom)
        }
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

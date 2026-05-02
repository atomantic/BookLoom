import SwiftUI
import SwiftData

struct BookClubHomeView: View {
    @Environment(\.modelContext) private var context
    @Bindable var club: BookClub
    @Query(sort: \BookSubmission.submittedAt) private var submissions: [BookSubmission]
    @Query(sort: \ClubMeeting.scheduledAt) private var meetings: [ClubMeeting]
    @Query(sort: \SelectionPoll.createdAt, order: .reverse) private var polls: [SelectionPoll]

    @State private var showingInvite: Bool = false
    @State private var showingPickConfirmation: Bool = false
    @State private var showingMeetingForm: Bool = false
    @State private var showingPollForm: Bool = false

    var body: some View {
        let displayedSections = sections
        let upcoming = upcomingMeetings
        let recentPolls = visiblePolls

        List {
            Section {
                ClubHomeHeader(club: club, sections: displayedSections)
                    .bookLoomListRow(top: 6, bottom: 8)
            }

            Section {
                MemberSummaryCard(club: club)
            } header: {
                SectionTitle(title: "Members")
            }
            .bookLoomListRow()

            Section {
                if let current = displayedSections.current {
                    NavigationLink(value: current) {
                        CurrentSubmissionRow(submission: current, meeting: nextMeeting(for: current))
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            markComplete(current)
                        } label: {
                            Label("Complete", systemImage: "checkmark.seal.fill")
                        }
                        .tint(.green)
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
                if upcoming.isEmpty {
                    MeetingActionCard(
                        title: "No Meeting Scheduled",
                        message: displayedSections.current == nil ? "Pick a current book before scheduling the next discussion." : "Add the next discussion date, host, reminders, and agenda.",
                        buttonTitle: "Schedule Meeting",
                        systemImage: "calendar.badge.plus",
                        isDisabled: displayedSections.current == nil
                    ) {
                        showingMeetingForm = true
                    }
                } else {
                    ForEach(upcoming.prefix(2)) { meeting in
                        NavigationLink(value: meeting) {
                            MeetingRow(meeting: meeting)
                        }
                        .bookLoomListRow()
                    }
                    MeetingActionCard(
                        title: "Add another meeting",
                        message: "Schedule future discussions or planning sessions.",
                        buttonTitle: "Schedule",
                        systemImage: "calendar.badge.plus",
                        isDisabled: displayedSections.current == nil
                    ) {
                        showingMeetingForm = true
                    }
                }
            } header: {
                SectionTitle(title: "Meetings", detail: "\(clubMeetings.count)")
            }
            .bookLoomListRow()

            Section {
                if recentPolls.isEmpty {
                    MeetingActionCard(
                        title: "No Active Vote",
                        message: displayedSections.proposed.count < 2 ? "Add at least two proposals to start a ranked vote." : "Let members rank their top three proposals before picking.",
                        buttonTitle: "Start Poll",
                        systemImage: "list.number",
                        isDisabled: displayedSections.proposed.count < 2
                    ) {
                        showingPollForm = true
                    }
                } else {
                    ForEach(recentPolls.prefix(2)) { poll in
                        NavigationLink(value: poll) {
                            SelectionPollRow(poll: poll, candidates: displayedSections.proposed + displayedSections.completed + [displayedSections.current].compactMap { $0 })
                        }
                        .bookLoomListRow()
                    }
                    MeetingActionCard(
                        title: "New ranked vote",
                        message: "Create a fresh poll from the current proposal list.",
                        buttonTitle: "Start Poll",
                        systemImage: "list.number",
                        isDisabled: displayedSections.proposed.count < 2
                    ) {
                        showingPollForm = true
                    }
                }
            } header: {
                SectionTitle(title: "Vote", detail: "\(clubPolls.count)")
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
                    ForEach(displayedSections.proposed) { submission in
                        NavigationLink(value: submission) {
                            SubmissionRow(submission: submission)
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
                            SubmissionRow(submission: submission)
                        }
                        .bookLoomListRow()
                    }
                    .onDelete { offsets in
                        delete(displayedSections.completed, at: offsets)
                    }
                } header: {
                    SectionTitle(title: "Read", detail: "\(displayedSections.completed.count)")
                }
            }

            if !pastMeetings.isEmpty {
                Section {
                    ForEach(pastMeetings.prefix(4)) { meeting in
                        NavigationLink(value: meeting) {
                            MeetingRow(meeting: meeting)
                        }
                        .bookLoomListRow()
                    }
                } header: {
                    SectionTitle(title: "Past Meetings", detail: "\(pastMeetings.count)")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationTitle(club.name)
        .navigationDestination(for: BookSubmission.self) { sub in
            SubmissionDetailView(submission: sub)
        }
        .navigationDestination(for: ClubMeeting.self) { meeting in
            MeetingDetailView(meeting: meeting)
        }
        .navigationDestination(for: SelectionPoll.self) { poll in
            SelectionPollDetailView(poll: poll, candidates: clubSubmissions)
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Label(syncDescriptor.label, systemImage: syncDescriptor.icon)
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
            if club.isOwner {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingInvite = true
                    } label: {
                        Label("Invite Members", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingInvite) {
            InviteView(club: club)
        }
        .sheet(isPresented: $showingMeetingForm) {
            ScheduleMeetingView(club: club, currentSubmission: displayedSections.current)
        }
        .sheet(isPresented: $showingPollForm) {
            StartPollView(club: club, candidates: displayedSections.proposed)
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
        .task(id: club.cloudZoneName) {
            await SharedClubSync.refreshIfNeeded(club, context: context)
        }
    }

    private var sections: BookClubSubmissionSections {
        BookClubSubmissionSections(submissions: clubSubmissions)
    }

    private var clubSubmissions: [BookSubmission] {
        submissions.filter { $0.bookClub?.persistentModelID == club.persistentModelID }
    }

    private var clubMeetings: [ClubMeeting] {
        meetings.filter { $0.bookClub?.persistentModelID == club.persistentModelID }
    }

    private var clubPolls: [SelectionPoll] {
        polls.filter { $0.bookClub?.persistentModelID == club.persistentModelID }
    }

    private var upcomingMeetings: [ClubMeeting] {
        clubMeetings
            .filter { !$0.isCompleted && $0.scheduledAt >= .now }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var pastMeetings: [ClubMeeting] {
        clubMeetings
            .filter { $0.isCompleted || $0.scheduledAt < .now }
            .sorted { ($0.completedAt ?? $0.scheduledAt) > ($1.completedAt ?? $1.scheduledAt) }
    }

    private var visiblePolls: [SelectionPoll] {
        let openPolls = clubPolls.filter(\.isOpen)
        if !openPolls.isEmpty {
            return openPolls.sorted { $0.createdAt > $1.createdAt }
        }
        return Array(clubPolls.sorted { $0.createdAt > $1.createdAt }.prefix(1))
    }

    private func nextMeeting(for submission: BookSubmission) -> ClubMeeting? {
        upcomingMeetings.first { $0.bookSubmission?.persistentModelID == submission.persistentModelID }
    }

    private var syncDescriptor: (label: String, icon: String) {
        if !club.isOwner {
            return ("Shared club", "person.2.fill")
        }
        return club.shareIsActive ? ("iCloud sharing on", "icloud.fill") : ("Owner device", "lock.fill")
    }

    private func pickRandomNext() {
        if let current = sections.current {
            current.status = .completed
            current.completedAt = .now
        }
        guard let pick = BookPicker.pickNext(from: sections.proposed) else { return }
        pick.status = .current
        pick.pickedAt = .now
        DiscussionPromptLibrary.ensureStarterPrompts(for: pick, context: context)
        saveClubChanges()
    }

    private func markComplete(_ submission: BookSubmission) {
        submission.status = .completed
        submission.completedAt = .now
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
            try SharedClubSync.saveAndPublish(context: context, club: club)
        } catch {
            assertionFailure("Failed to save club changes: \(error.localizedDescription)")
        }
    }
}

private struct SubmissionRow: View {
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
    let meeting: ClubMeeting?

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

                if let meeting {
                    Label(meeting.scheduledAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BookLoomStyle.indigo)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 12)
    }
}

private struct MeetingActionCard: View {
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

private struct ClubHomeHeader: View {
    let club: BookClub
    let sections: BookClubSubmissionSections

    var body: some View {
        let sharing = sharingDescriptor
        let memberCount = club.displayedMemberCount

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

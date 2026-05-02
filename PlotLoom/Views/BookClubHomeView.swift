import SwiftUI
import SwiftData

struct BookClubHomeView: View {
    @Environment(\.modelContext) private var context
    @Bindable var club: BookClub
    @Query(sort: \BookSubmission.submittedAt) private var submissions: [BookSubmission]

    @State private var showingInvite: Bool = false
    @State private var showingPickConfirmation: Bool = false

    var body: some View {
        let displayedSections = sections

        List {
            Section {
                ClubHomeHeader(club: club, sections: displayedSections)
                    .plotLoomListRow(top: 8, bottom: 12)
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
            .plotLoomListRow()

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
                        .plotLoomListRow()
                    }
                    .onDelete { offsets in
                        delete(displayedSections.proposed, at: offsets)
                    }
                }
            } header: {
                SectionTitle(title: "Proposed", detail: "\(displayedSections.proposed.count)")
            }
            .plotLoomListRow()

            if !displayedSections.completed.isEmpty {
                Section {
                    ForEach(displayedSections.completed) { submission in
                        NavigationLink(value: submission) {
                            SubmissionRow(submission: submission)
                        }
                        .plotLoomListRow()
                    }
                    .onDelete { offsets in
                        delete(displayedSections.completed, at: offsets)
                    }
                } header: {
                    SectionTitle(title: "Read", detail: "\(displayedSections.completed.count)")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .plotLoomScreenBackground()
        .navigationTitle(club.name)
        .navigationDestination(for: BookSubmission.self) { sub in
            SubmissionDetailView(submission: sub)
        }
        .toolbar {
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
    }

    private var sections: BookClubSubmissionSections {
        BookClubSubmissionSections(submissions: clubSubmissions)
    }

    private var clubSubmissions: [BookSubmission] {
        submissions.filter { $0.bookClub?.persistentModelID == club.persistentModelID }
    }

    private func pickRandomNext() {
        if let current = sections.current {
            markComplete(current)
        }
        guard let pick = BookPicker.pickNext(from: sections.proposed) else { return }
        pick.status = .current
        pick.pickedAt = .now
    }

    private func markComplete(_ submission: BookSubmission) {
        submission.status = .completed
        submission.completedAt = .now
    }

    private func delete(_ items: [BookSubmission], at offsets: IndexSet) {
        for index in offsets {
            context.delete(items[index])
        }
    }
}

private struct SubmissionRow: View {
    @Bindable var submission: BookSubmission

    var body: some View {
        HStack(spacing: 14) {
            BookCoverTile(title: submission.displayTitle, author: submission.displayAuthor, coverURL: submission.coverImageURL)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(submission.displayTitle)
                            .font(.headline)
                            .foregroundStyle(PlotLoomStyle.ink)
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
        .plotLoomCard(padding: 14)
    }
}

private struct CurrentSubmissionRow: View {
    @Bindable var submission: BookSubmission

    var body: some View {
        HStack(spacing: 18) {
            BookCoverTile(title: submission.displayTitle, author: submission.displayAuthor, coverURL: submission.coverImageURL, width: 86, height: 118)

            VStack(alignment: .leading, spacing: 10) {
                StatusPill(status: .current)
                Text(submission.displayTitle)
                    .font(.title3.bold())
                    .foregroundStyle(PlotLoomStyle.ink)
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
        .plotLoomCard(padding: 16)
    }
}

private struct ClubHomeHeader: View {
    let club: BookClub
    let sections: BookClubSubmissionSections

    var body: some View {
        let sharing = sharingDescriptor
        let memberCount = club.displayedMemberCount

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                BrandBadge(size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(club.name)
                        .font(.title2.bold())
                        .foregroundStyle(PlotLoomStyle.ink)
                        .lineLimit(2)
                    Label(sharing.label, systemImage: sharing.icon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                MetricTile(value: "\(sections.proposed.count)", label: "proposed", systemImage: "tray.full.fill", tint: PlotLoomStyle.plum)
                MetricTile(value: "\(sections.completed.count)", label: "read", systemImage: "checkmark.seal.fill", tint: PlotLoomStyle.indigo)
                MetricTile(value: "\(memberCount)", label: "members", systemImage: "person.2.fill", tint: PlotLoomStyle.sage)
            }
        }
        .plotLoomCard(padding: 18)
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

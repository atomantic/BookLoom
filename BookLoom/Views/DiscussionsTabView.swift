import SwiftUI
import SwiftData

/// Top-level Discussions tab. Surfaces discussion prompts for the active
/// club. The current read leads the page (since that's where the active
/// conversation happens), with previously-read books listed below if they
/// have prompts attached.
struct DiscussionsTabView: View {
    var body: some View {
        ClubScopedScaffold(title: "Discussions") { club in
            DiscussionsTabContent(club: club)
        }
    }
}

private struct DiscussionsTabContent: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @Bindable var club: BookClub
    @Query(sort: \BookSubmission.submittedAt) private var submissions: [BookSubmission]

    @State private var draftPrompt: String = ""
    @State private var presentedDiscussion: BookSubmission?

    var body: some View {
        let sections = club.sections
        let history = sections.completed.filter { !$0.activeDiscussionPrompts.isEmpty }
        let proposalsWithPrompts = sections.proposed.filter { !$0.activeDiscussionPrompts.isEmpty }

        List {
            if let current = sections.current {
                Section {
                    DiscussionBookCard(submission: current, accentLabel: "Currently Reading")
                        .bookLoomListRow(top: 6, bottom: 8)

                    DiscussionPromptCard(
                        submission: current,
                        draftPrompt: $draftPrompt,
                        onStartDiscussion: { presentedDiscussion = current }
                    )
                    .bookLoomListRow()
                } header: {
                    SectionTitle(title: "Current Read")
                }
            } else {
                Section {
                    InlineEmptyState(
                        systemImage: "text.bubble",
                        title: "No Current Read",
                        message: "Pick a current book in the Books tab to start adding discussion prompts."
                    )
                    .bookLoomListRow()
                }
            }

            if !proposalsWithPrompts.isEmpty {
                Section {
                    ForEach(proposalsWithPrompts) { submission in
                        NavigationLink(value: submission) {
                            DiscussionBookSummaryRow(submission: submission)
                        }
                        .buttonStyle(.plain)
                        .bookLoomListRow()
                    }
                } header: {
                    SectionTitle(title: "Proposals with Prompts", detail: "\(proposalsWithPrompts.count)")
                }
            }

            if !history.isEmpty {
                Section {
                    ForEach(history) { submission in
                        NavigationLink(value: submission) {
                            DiscussionBookSummaryRow(submission: submission)
                        }
                        .buttonStyle(.plain)
                        .bookLoomListRow()
                    }
                } header: {
                    SectionTitle(title: "Past Reads", detail: "\(history.count)")
                }
            }
        }
        .bookLoomListStyle()
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationDestination(for: BookSubmission.self) { submission in
            SubmissionDetailView(submission: submission)
        }
        .sheet(item: $presentedDiscussion) { submission in
            DiscussionModeView(
                submissionTitle: submission.displayTitle,
                prompts: submission.activeDiscussionPrompts
            )
        }
    }
}

private struct DiscussionBookCard: View {
    @Bindable var submission: BookSubmission
    let accentLabel: String

    var body: some View {
        HStack(spacing: 14) {
            BookCoverTile(
                title: submission.displayTitle,
                author: submission.displayAuthor,
                coverURL: submission.coverImageURL,
                width: 64,
                height: 88
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(accentLabel.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BookLoomStyle.indigo)
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
                Label("\(submission.activeDiscussionPrompts.count) prompts", systemImage: "text.bubble")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 12)
    }
}

private struct DiscussionBookSummaryRow: View {
    @Bindable var submission: BookSubmission

    var body: some View {
        StandardBookCardRow(
            title: submission.displayTitle,
            author: submission.displayAuthor,
            coverURL: submission.coverImageURL,
            indicators: [
                BookCardIndicator(
                    "\(submission.activeDiscussionPrompts.count) prompts",
                    systemImage: "text.bubble",
                    visibleText: "\(submission.activeDiscussionPrompts.count)",
                    tint: BookLoomStyle.plum
                )
            ],
            showsDisclosure: true,
            coverWidth: 58,
            coverHeight: 82
        )
    }
}

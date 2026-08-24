import Foundation
import SwiftData

@MainActor
enum MemberShareSnapshotStore {
    /// Build a per-author snapshot from the local SwiftData state. Only
    /// includes items where the local member is the author/contributor.
    /// `includeClubMeta` should be true for the club owner so they publish
    /// canonical club metadata; non-owner participants pass false.
    static func snapshot(
        from club: BookClub,
        context: ModelContext,
        authorMemberID: String,
        authorName: String,
        includeClubMeta: Bool,
        capturedAt: Date = .now
    ) -> MemberShareSnapshot {
        let clubID = club.persistentModelID
        let submissions = fetchedClubChildren(
            predicate: #Predicate<BookSubmission> { $0.bookClub?.persistentModelID == clubID },
            fallback: club.submissions ?? [],
            context: context
        )
        let meetings = fetchedClubChildren(
            predicate: #Predicate<ClubMeeting> { $0.bookClub?.persistentModelID == clubID },
            fallback: club.meetings ?? [],
            context: context
        )
        let polls = fetchedClubChildren(
            predicate: #Predicate<SelectionPoll> { $0.bookClub?.persistentModelID == clubID },
            fallback: club.selectionPolls ?? [],
            context: context
        )

        // Backfill stable IDs for legacy rows whose property may have been
        // migrated in as the empty string. Without this every export of a
        // poll/meeting/prompt would key on "" and collide on merge.
        backfillStableIDs(submissions: submissions, meetings: meetings, polls: polls)

        var submissionPayloads: [MemberShareSnapshot.SubmissionPayload] = []
        var ratingPayloads: [MemberShareSnapshot.RatingPayload] = []
        var notePayloads: [MemberShareSnapshot.NotePayload] = []
        var promptPayloads: [MemberShareSnapshot.PromptPayload] = []

        for submission in submissions.sorted(by: { $0.submittedAt < $1.submittedAt }) {
            if isAuthor(authorMemberID, of: submission.submittedByMemberID) {
                submissionPayloads.append(submissionPayload(submission, authorFallback: authorMemberID))
            }
            for rating in (submission.ratings ?? []) where isAuthor(authorMemberID, of: rating.memberID) {
                ratingPayloads.append(
                    MemberShareSnapshot.RatingPayload(
                        submissionSelectionID: submission.selectionID,
                        memberID: rating.memberID.trimmedOrNil ?? authorMemberID,
                        memberName: rating.memberName.trimmedOrNil ?? authorName,
                        stars: rating.stars,
                        createdAt: rating.createdAt
                    )
                )
            }
            for note in (submission.notes ?? []) where isAuthor(authorMemberID, of: note.memberID) {
                notePayloads.append(
                    MemberShareSnapshot.NotePayload(
                        submissionSelectionID: submission.selectionID,
                        memberID: note.memberID.trimmedOrNil ?? authorMemberID,
                        memberName: note.memberName.trimmedOrNil ?? authorName,
                        text: note.text,
                        createdAt: note.createdAt
                    )
                )
            }
            for prompt in (submission.discussionPrompts ?? []) where isAuthor(authorMemberID, of: prompt.createdByMemberID) {
                promptPayloads.append(
                    MemberShareSnapshot.PromptPayload(
                        promptID: prompt.promptID,
                        submissionSelectionID: submission.selectionID,
                        createdByMemberID: prompt.createdByMemberID.trimmedOrNil ?? authorMemberID,
                        question: prompt.question,
                        orderIndex: prompt.orderIndex,
                        sourceRaw: prompt.sourceRaw,
                        createdAt: prompt.createdAt,
                        isArchived: prompt.isArchived
                    )
                )
            }
        }

        var meetingPayloads: [MemberShareSnapshot.MeetingPayload] = []
        var rsvpPayloads: [MemberShareSnapshot.RSVPPayload] = []
        for meeting in meetings.sorted(by: { $0.scheduledAt < $1.scheduledAt }) {
            if isAuthor(authorMemberID, of: meeting.hostMemberID) {
                meetingPayloads.append(meetingPayload(meeting))
            }
            for rsvp in (meeting.rsvps ?? []) where isAuthor(authorMemberID, of: rsvp.memberID) {
                rsvpPayloads.append(
                    MemberShareSnapshot.RSVPPayload(
                        meetingID: meeting.meetingID,
                        memberID: rsvp.memberID.trimmedOrNil ?? authorMemberID,
                        memberName: rsvp.memberName.trimmedOrNil ?? authorName,
                        statusRaw: rsvp.statusRaw,
                        bringingNote: rsvp.bringingNote,
                        updatedAt: rsvp.updatedAt
                    )
                )
            }
        }

        var pollPayloads: [MemberShareSnapshot.PollPayload] = []
        var votePayloads: [MemberShareSnapshot.VotePayload] = []
        for poll in polls.sorted(by: { $0.createdAt < $1.createdAt }) {
            if isAuthor(authorMemberID, of: poll.createdByMemberID) {
                pollPayloads.append(
                    MemberShareSnapshot.PollPayload(
                        pollID: poll.pollID,
                        createdByMemberID: poll.createdByMemberID.trimmedOrNil ?? authorMemberID,
                        title: poll.title,
                        createdAt: poll.createdAt,
                        closesAt: poll.closesAt,
                        statusRaw: poll.statusRaw,
                        isAnonymousResults: poll.isAnonymousResults,
                        candidateIDsRaw: poll.candidateIDsRaw,
                        winnerSubmissionID: poll.winnerSubmissionID
                    )
                )
            }
            for vote in (poll.votes ?? []) where isAuthor(authorMemberID, of: vote.memberID) {
                votePayloads.append(
                    MemberShareSnapshot.VotePayload(
                        pollID: poll.pollID,
                        memberID: vote.memberID.trimmedOrNil ?? authorMemberID,
                        memberName: vote.memberName.trimmedOrNil ?? authorName,
                        rankedSubmissionIDsRaw: vote.rankedSubmissionIDsRaw,
                        updatedAt: vote.updatedAt
                    )
                )
            }
        }

        let clubMeta: MemberShareSnapshot.ClubMeta? = includeClubMeta
            ? MemberShareSnapshot.ClubMeta(
                name: club.name,
                createdAt: club.createdAt,
                cloudZoneName: club.cloudZoneName,
                shareParticipantCount: club.shareParticipantCount,
                creatorMemberID: club.creatorMemberID.trimmedOrNil,
                adminMemberIDs: club.adminMemberIDs.sorted(),
                removedMemberIDs: club.removedMemberIDs.sorted(),
                memberIdentityBindings: club.memberIdentityBindings
                    .map { MemberShareSnapshot.MemberIdentityBinding(memberID: $0.key, cloudKitUserRecordName: $0.value) }
                    .sorted { $0.memberID < $1.memberID },
                inviteURLString: nil,
                nameUpdatedAt: club.nameUpdatedAt > .distantPast ? club.nameUpdatedAt : nil
            )
            : nil

        let nameProposal: MemberShareSnapshot.NameProposal? = {
            guard !includeClubMeta else { return nil }
            guard club.isAdmin(memberID: authorMemberID) else { return nil }
            guard club.nameUpdatedAt > .distantPast, !club.name.isEmpty else { return nil }
            return MemberShareSnapshot.NameProposal(
                name: club.name,
                updatedAt: club.nameUpdatedAt,
                proposerMemberID: authorMemberID
            )
        }()

        let statusOverrides = club.statusOverrideLog
            .filter { isAuthor(authorMemberID, of: $0.actorMemberID) }
            .map {
                MemberShareSnapshot.StatusOverride(
                    submissionSelectionID: $0.submissionSelectionID,
                    statusRaw: $0.statusRaw,
                    pickedAt: $0.pickedAt,
                    completedAt: $0.completedAt,
                    occurredAt: $0.occurredAt
                )
            }
        let detailsOverrides = club.submissionDetailsOverrideLog
            .filter { isAuthor(authorMemberID, of: $0.actorMemberID) }
            .map {
                MemberShareSnapshot.SubmissionDetailsOverride(
                    submissionSelectionID: $0.submissionSelectionID,
                    title: $0.title,
                    author: $0.author,
                    isbn: $0.isbn,
                    bookDescription: $0.bookDescription,
                    publishedYear: $0.publishedYear,
                    coverURL: $0.coverURL,
                    externalProvider: $0.externalProvider,
                    externalID: $0.externalID,
                    updatedAt: $0.updatedAt,
                    actorMemberID: $0.actorMemberID
                )
            }
        let deletedSubmissions = club.submissionDeletionLog
            .filter { isAuthor(authorMemberID, of: $0.actorMemberID) }
            .map {
                MemberShareSnapshot.SubmissionDeletion(
                    submissionSelectionID: $0.submissionSelectionID,
                    deletedAt: $0.deletedAt,
                    actorMemberID: $0.actorMemberID
                )
            }

        return MemberShareSnapshot(
            capturedAt: capturedAt,
            authorMemberID: authorMemberID,
            authorName: authorName,
            clubMeta: clubMeta,
            nameProposal: nameProposal,
            submissions: submissionPayloads,
            statusOverrides: statusOverrides,
            detailsOverrides: detailsOverrides,
            deletedSubmissions: deletedSubmissions,
            ratings: ratingPayloads,
            notes: notePayloads,
            prompts: promptPayloads,
            polls: pollPayloads,
            votes: votePayloads,
            meetings: meetingPayloads,
            rsvps: rsvpPayloads
        )
    }

    // MARK: - Builder helpers

    private static func submissionPayload(_ submission: BookSubmission, authorFallback: String) -> MemberShareSnapshot.SubmissionPayload {
        MemberShareSnapshot.SubmissionPayload(
            selectionID: submission.selectionID,
            title: submission.title,
            author: submission.author,
            isbn: submission.isbn,
            submittedBy: submission.submittedBy,
            submittedByMemberID: submission.submittedByMemberID.trimmedOrNil ?? authorFallback,
            submittedAt: submission.submittedAt,
            initialStatusRaw: submission.statusRaw,
            initialPickedAt: submission.pickedAt,
            initialCompletedAt: submission.completedAt,
            bookDescription: submission.bookDescription,
            publishedYear: submission.publishedYear,
            coverURL: submission.coverURL,
            externalProvider: submission.externalProvider,
            externalID: submission.externalID
        )
    }

    private static func meetingPayload(_ meeting: ClubMeeting) -> MemberShareSnapshot.MeetingPayload {
        MemberShareSnapshot.MeetingPayload(
            meetingID: meeting.meetingID,
            title: meeting.title,
            scheduledAt: meeting.scheduledAt,
            hostName: meeting.hostName,
            hostMemberID: meeting.hostMemberID,
            location: meeting.location,
            meetingURL: meeting.meetingURL,
            reminderOffsetsRaw: meeting.reminderOffsetsRaw,
            agenda: meeting.agenda,
            createdAt: meeting.createdAt,
            completedAt: meeting.completedAt,
            submissionSelectionID: meeting.bookSubmission?.selectionID
        )
    }

    private static func backfillStableIDs(
        submissions: [BookSubmission],
        meetings: [ClubMeeting],
        polls: [SelectionPoll]
    ) {
        for submission in submissions {
            if submission.selectionID.isEmpty {
                submission.selectionID = UUID().uuidString
            }
            for prompt in submission.discussionPrompts ?? [] where prompt.promptID.isEmpty {
                prompt.promptID = UUID().uuidString
            }
        }
        for meeting in meetings where meeting.meetingID.isEmpty {
            meeting.meetingID = UUID().uuidString
        }
        for poll in polls where poll.pollID.isEmpty {
            poll.pollID = UUID().uuidString
        }
    }

    /// Works around a SwiftData faulting case where `club.<children>` returns
    /// an empty array immediately after a CloudKit-driven merge even though
    /// the rows are present in the store. We fetch the child rows scoped to
    /// this club via `predicate` (so SQLite filters server-side rather than
    /// loading every row) and fall back to the relationship array if the fetch
    /// fails or comes back empty — the fallback is the documented faulting
    /// workaround, not error-swallowing, so a failed read here degrades to the
    /// in-memory relationship rather than aborting snapshot capture.
    private static func fetchedClubChildren<T: PersistentModel>(
        predicate: Predicate<T>,
        fallback: [T],
        context: ModelContext
    ) -> [T] {
        guard let fetched = try? context.fetch(FetchDescriptor<T>(predicate: predicate)) else {
            return fallback
        }
        return fetched.isEmpty ? fallback : fetched
    }

    // MARK: - Shared helpers

    static func isAuthor(_ localMemberID: String, of recordedMemberID: String) -> Bool {
        guard !localMemberID.isEmpty else { return false }
        return recordedMemberID == localMemberID
    }
}

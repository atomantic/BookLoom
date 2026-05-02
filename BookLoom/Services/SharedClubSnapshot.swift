import Foundation
import SwiftData

struct SharedClubSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let capturedAt: Date
    let club: ClubPayload
    let submissions: [SubmissionPayload]
    let meetings: [MeetingPayload]
    let polls: [PollPayload]

    init(
        schemaVersion: Int = Self.schemaVersion,
        capturedAt: Date = .now,
        club: ClubPayload,
        submissions: [SubmissionPayload],
        meetings: [MeetingPayload],
        polls: [PollPayload]
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.club = club
        self.submissions = submissions
        self.meetings = meetings
        self.polls = polls
    }

    struct ClubPayload: Codable, Equatable, Sendable {
        let name: String
        let createdAt: Date
        let cloudZoneName: String
        let shareParticipantCount: Int
    }

    struct SubmissionPayload: Codable, Equatable, Sendable {
        let selectionID: String
        let title: String
        let author: String
        let isbn: String
        let submittedBy: String
        let submittedByMemberID: String
        let submittedAt: Date
        let statusRaw: String
        let pickedAt: Date?
        let completedAt: Date?
        let bookDescription: String
        let publishedYear: Int?
        let coverURL: String
        let externalProvider: String
        let externalID: String
        let ratings: [RatingPayload]
        let notes: [NotePayload]
        let discussionPrompts: [PromptPayload]
    }

    struct RatingPayload: Codable, Equatable, Sendable {
        let memberID: String
        let memberName: String
        let stars: Int
        let createdAt: Date
    }

    struct NotePayload: Codable, Equatable, Sendable {
        let memberID: String
        let memberName: String
        let text: String
        let createdAt: Date
    }

    struct PromptPayload: Codable, Equatable, Sendable {
        let question: String
        let orderIndex: Int
        let sourceRaw: String
        let createdAt: Date
        let isArchived: Bool
    }

    struct MeetingPayload: Codable, Equatable, Sendable {
        let title: String
        let scheduledAt: Date
        let hostName: String
        let hostMemberID: String
        let location: String
        let meetingURL: String
        let reminderOffsetsRaw: String
        let agenda: String
        let createdAt: Date
        let completedAt: Date?
        let submissionSelectionID: String?
        let rsvps: [RSVPPayload]
    }

    struct RSVPPayload: Codable, Equatable, Sendable {
        let memberID: String
        let memberName: String
        let statusRaw: String
        let bringingNote: String
        let updatedAt: Date
    }

    struct PollPayload: Codable, Equatable, Sendable {
        let title: String
        let createdAt: Date
        let closesAt: Date?
        let statusRaw: String
        let isAnonymousResults: Bool
        let candidateIDsRaw: String
        let winnerSubmissionID: String
        let votes: [VotePayload]
    }

    struct VotePayload: Codable, Equatable, Sendable {
        let memberID: String
        let memberName: String
        let rankedSubmissionIDsRaw: String
        let updatedAt: Date
    }
}

@MainActor
enum SharedClubSnapshotStore {
    static func snapshot(from club: BookClub, capturedAt: Date = .now) -> SharedClubSnapshot {
        snapshot(
            from: club,
            submissions: club.submissions ?? [],
            meetings: club.meetings ?? [],
            polls: club.selectionPolls ?? [],
            capturedAt: capturedAt
        )
    }

    static func snapshot(from club: BookClub, context: ModelContext, capturedAt: Date = .now) -> SharedClubSnapshot {
        snapshot(
            from: club,
            submissions: fetchedChildren(of: club, parentKeyPath: \BookSubmission.bookClub, fallback: club.submissions ?? [], context: context),
            meetings: fetchedChildren(of: club, parentKeyPath: \ClubMeeting.bookClub, fallback: club.meetings ?? [], context: context),
            polls: fetchedChildren(of: club, parentKeyPath: \SelectionPoll.bookClub, fallback: club.selectionPolls ?? [], context: context),
            capturedAt: capturedAt
        )
    }

    private static func snapshot(
        from club: BookClub,
        submissions: [BookSubmission],
        meetings: [ClubMeeting],
        polls: [SelectionPoll],
        capturedAt: Date
    ) -> SharedClubSnapshot {
        let submissionPayloads = submissions
            .sorted { $0.submittedAt < $1.submittedAt }
            .map(submissionPayload)
        let meetingPayloads = meetings
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .map(meetingPayload)
        let pollPayloads = polls
            .sorted { $0.createdAt < $1.createdAt }
            .map(pollPayload)

        return SharedClubSnapshot(
            capturedAt: capturedAt,
            club: SharedClubSnapshot.ClubPayload(
                name: club.name,
                createdAt: club.createdAt,
                cloudZoneName: club.cloudZoneName,
                shareParticipantCount: club.shareParticipantCount
            ),
            submissions: submissionPayloads,
            meetings: meetingPayloads,
            polls: pollPayloads
        )
    }

    /// Works around a SwiftData faulting case where `club.submissions` (and
    /// equivalent to-many relationships) returns an empty array immediately
    /// after a CloudKit-driven merge, even though the rows are present in the
    /// store. We fetch all rows of the child type and filter to the ones whose
    /// parent matches `club`. The relationship array is used as a fallback if
    /// the fetch fails or returns no matches (e.g. fresh in-memory contexts).
    private static func fetchedChildren<T: PersistentModel>(
        of club: BookClub,
        parentKeyPath: KeyPath<T, BookClub?>,
        fallback: [T],
        context: ModelContext
    ) -> [T] {
        let clubID = club.persistentModelID
        guard let fetched = try? context.fetch(FetchDescriptor<T>()) else {
            return fallback
        }
        let matches = fetched.filter { $0[keyPath: parentKeyPath]?.persistentModelID == clubID }
        return matches.isEmpty ? fallback : matches
    }

    static func apply(_ snapshot: SharedClubSnapshot, to club: BookClub, context: ModelContext) throws {
        if let lastSharedSnapshotAt = club.lastSharedSnapshotAt,
           snapshot.capturedAt <= lastSharedSnapshotAt {
            return
        }

        let notificationEvents = club.lastSharedSnapshotAt == nil
            ? []
            : BookLoomNotificationEvent.events(before: club, applying: snapshot)

        club.name = snapshot.club.name
        club.createdAt = snapshot.club.createdAt
        if club.cloudZoneName.isEmpty {
            club.cloudZoneName = snapshot.club.cloudZoneName
        }
        club.shareIsActive = true
        club.shareParticipantCount = max(club.shareParticipantCount, snapshot.club.shareParticipantCount)

        replaceChildren(of: club, context: context)

        var submissionsByID: [String: BookSubmission] = [:]
        for item in snapshot.submissions {
            let submission = BookSubmission(
                title: item.title,
                author: item.author,
                isbn: item.isbn,
                bookDescription: item.bookDescription,
                publishedYear: item.publishedYear,
                coverURL: item.coverURL,
                externalProvider: item.externalProvider,
                externalID: item.externalID,
                submittedBy: item.submittedBy,
                submittedByMemberID: item.submittedByMemberID,
                submittedAt: item.submittedAt,
                status: BookSubmissionStatus(rawValue: item.statusRaw) ?? .proposed
            )
            submission.selectionID = item.selectionID
            submission.pickedAt = item.pickedAt
            submission.completedAt = item.completedAt
            submission.coverData = nil
            context.insert(submission)
            club.addSubmission(submission)
            submissionsByID[submission.selectionID] = submission

            submission.ratings = item.ratings.map { ratingItem in
                let rating = Rating(
                    memberID: ratingItem.memberID,
                    memberName: ratingItem.memberName,
                    stars: ratingItem.stars,
                    createdAt: ratingItem.createdAt
                )
                rating.submission = submission
                context.insert(rating)
                return rating
            }

            submission.notes = item.notes.map { noteItem in
                let note = BookNote(
                    memberID: noteItem.memberID,
                    memberName: noteItem.memberName,
                    text: noteItem.text,
                    createdAt: noteItem.createdAt
                )
                note.submission = submission
                context.insert(note)
                return note
            }

            submission.discussionPrompts = item.discussionPrompts.map { promptItem in
                let prompt = DiscussionPrompt(
                    question: promptItem.question,
                    orderIndex: promptItem.orderIndex,
                    source: DiscussionPromptSource(rawValue: promptItem.sourceRaw) ?? .custom,
                    createdAt: promptItem.createdAt
                )
                prompt.isArchived = promptItem.isArchived
                prompt.submission = submission
                context.insert(prompt)
                return prompt
            }
        }

        for item in snapshot.meetings {
            let meeting = ClubMeeting(
                title: item.title,
                scheduledAt: item.scheduledAt,
                hostName: item.hostName,
                hostMemberID: item.hostMemberID,
                location: item.location,
                meetingURL: item.meetingURL,
                reminderOffsets: SelectionPoll.decodeIDs(item.reminderOffsetsRaw).compactMap(Int.init),
                agenda: item.agenda,
                createdAt: item.createdAt
            )
            meeting.reminderOffsetsRaw = item.reminderOffsetsRaw
            meeting.completedAt = item.completedAt
            meeting.bookSubmission = item.submissionSelectionID.flatMap { submissionsByID[$0] }
            context.insert(meeting)
            club.addMeeting(meeting)
            meeting.rsvps = item.rsvps.map { rsvpItem in
                let rsvp = MeetingRSVP(
                    memberID: rsvpItem.memberID,
                    memberName: rsvpItem.memberName,
                    status: MeetingRSVPStatus(rawValue: rsvpItem.statusRaw) ?? .attending,
                    bringingNote: rsvpItem.bringingNote,
                    updatedAt: rsvpItem.updatedAt
                )
                rsvp.meeting = meeting
                context.insert(rsvp)
                return rsvp
            }
        }

        for item in snapshot.polls {
            let poll = SelectionPoll(
                title: item.title,
                createdAt: item.createdAt,
                closesAt: item.closesAt,
                isAnonymousResults: item.isAnonymousResults
            )
            poll.statusRaw = item.statusRaw
            poll.candidateIDsRaw = item.candidateIDsRaw
            poll.winnerSubmissionID = item.winnerSubmissionID
            context.insert(poll)
            club.addSelectionPoll(poll)
            poll.votes = item.votes.map { voteItem in
                let vote = BookVote(
                    memberID: voteItem.memberID,
                    memberName: voteItem.memberName,
                    rankedSubmissionIDs: SelectionPoll.decodeIDs(voteItem.rankedSubmissionIDsRaw),
                    updatedAt: voteItem.updatedAt
                )
                vote.poll = poll
                context.insert(vote)
                return vote
            }
        }

        club.lastSharedSnapshotAt = snapshot.capturedAt
        try context.save()

        if !notificationEvents.isEmpty {
            Task {
                await BookLoomUserNotifications.schedule(notificationEvents)
            }
        }
    }

    private static func replaceChildren(of club: BookClub, context: ModelContext) {
        for poll in club.selectionPolls ?? [] {
            context.delete(poll)
        }
        club.selectionPolls = []

        for meeting in club.meetings ?? [] {
            context.delete(meeting)
        }
        club.meetings = []

        for submission in club.submissions ?? [] {
            context.delete(submission)
        }
        club.submissions = []
    }

    private static func submissionPayload(_ submission: BookSubmission) -> SharedClubSnapshot.SubmissionPayload {
        SharedClubSnapshot.SubmissionPayload(
            selectionID: submission.selectionID,
            title: submission.title,
            author: submission.author,
            isbn: submission.isbn,
            submittedBy: submission.submittedBy,
            submittedByMemberID: submission.submittedByMemberID,
            submittedAt: submission.submittedAt,
            statusRaw: submission.statusRaw,
            pickedAt: submission.pickedAt,
            completedAt: submission.completedAt,
            bookDescription: submission.bookDescription,
            publishedYear: submission.publishedYear,
            coverURL: submission.coverURL,
            externalProvider: submission.externalProvider,
            externalID: submission.externalID,
            ratings: (submission.ratings ?? [])
                .sorted { $0.createdAt < $1.createdAt }
                .map(ratingPayload),
            notes: (submission.notes ?? [])
                .sorted { $0.createdAt < $1.createdAt }
                .map(notePayload),
            discussionPrompts: (submission.discussionPrompts ?? [])
                .sorted {
                    if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
                    return $0.createdAt < $1.createdAt
                }
                .map(promptPayload)
        )
    }

    private static func ratingPayload(_ rating: Rating) -> SharedClubSnapshot.RatingPayload {
        SharedClubSnapshot.RatingPayload(
            memberID: rating.memberID,
            memberName: rating.memberName,
            stars: rating.stars,
            createdAt: rating.createdAt
        )
    }

    private static func notePayload(_ note: BookNote) -> SharedClubSnapshot.NotePayload {
        SharedClubSnapshot.NotePayload(
            memberID: note.memberID,
            memberName: note.memberName,
            text: note.text,
            createdAt: note.createdAt
        )
    }

    private static func promptPayload(_ prompt: DiscussionPrompt) -> SharedClubSnapshot.PromptPayload {
        SharedClubSnapshot.PromptPayload(
            question: prompt.question,
            orderIndex: prompt.orderIndex,
            sourceRaw: prompt.sourceRaw,
            createdAt: prompt.createdAt,
            isArchived: prompt.isArchived
        )
    }

    private static func meetingPayload(_ meeting: ClubMeeting) -> SharedClubSnapshot.MeetingPayload {
        SharedClubSnapshot.MeetingPayload(
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
            submissionSelectionID: meeting.bookSubmission?.selectionID,
            rsvps: (meeting.rsvps ?? [])
                .sorted { $0.updatedAt < $1.updatedAt }
                .map(rsvpPayload)
        )
    }

    private static func rsvpPayload(_ rsvp: MeetingRSVP) -> SharedClubSnapshot.RSVPPayload {
        SharedClubSnapshot.RSVPPayload(
            memberID: rsvp.memberID,
            memberName: rsvp.memberName,
            statusRaw: rsvp.statusRaw,
            bringingNote: rsvp.bringingNote,
            updatedAt: rsvp.updatedAt
        )
    }

    private static func pollPayload(_ poll: SelectionPoll) -> SharedClubSnapshot.PollPayload {
        SharedClubSnapshot.PollPayload(
            title: poll.title,
            createdAt: poll.createdAt,
            closesAt: poll.closesAt,
            statusRaw: poll.statusRaw,
            isAnonymousResults: poll.isAnonymousResults,
            candidateIDsRaw: poll.candidateIDsRaw,
            winnerSubmissionID: poll.winnerSubmissionID,
            votes: (poll.votes ?? [])
                .sorted { $0.updatedAt < $1.updatedAt }
                .map(votePayload)
        )
    }

    private static func votePayload(_ vote: BookVote) -> SharedClubSnapshot.VotePayload {
        SharedClubSnapshot.VotePayload(
            memberID: vote.memberID,
            memberName: vote.memberName,
            rankedSubmissionIDsRaw: vote.rankedSubmissionIDsRaw,
            updatedAt: vote.updatedAt
        )
    }
}

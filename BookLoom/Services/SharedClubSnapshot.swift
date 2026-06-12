import Foundation
import SwiftData

/// Per-author CKShare payload. Each participant publishes one of these into
/// the shared zone (a separate CKRecord named `MemberSnapshot-<memberID>`),
/// containing only their own contributions. All clients fetch every member's
/// snapshot and merge them into the local SwiftData store.
///
/// This replaces the earlier single-document `SharedClubSnapshot`, which only
/// supported owner-broadcast and silently dropped any contributions from
/// non-owner participants.
struct MemberShareSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 3

    let schemaVersion: Int
    let capturedAt: Date
    let authorMemberID: String
    let authorName: String
    /// Owner-only: canonical club metadata (name, createdAt). Members publish
    /// nil and rely on the owner's snapshot for these fields.
    let clubMeta: ClubMeta?
    /// Rename pushed by an admin who isn't the CKShare owner. Owners adopt
    /// it through `clubMeta` on next publish.
    let nameProposal: NameProposal?
    let submissions: [SubmissionPayload]
    let statusOverrides: [StatusOverride]
    let detailsOverrides: [SubmissionDetailsOverride]?
    let deletedSubmissions: [SubmissionDeletion]?
    let ratings: [RatingPayload]
    let notes: [NotePayload]
    let prompts: [PromptPayload]
    let polls: [PollPayload]
    let votes: [VotePayload]
    let meetings: [MeetingPayload]
    let rsvps: [RSVPPayload]

    init(
        schemaVersion: Int = Self.schemaVersion,
        capturedAt: Date = .now,
        authorMemberID: String,
        authorName: String,
        clubMeta: ClubMeta? = nil,
        nameProposal: NameProposal? = nil,
        submissions: [SubmissionPayload] = [],
        statusOverrides: [StatusOverride] = [],
        detailsOverrides: [SubmissionDetailsOverride] = [],
        deletedSubmissions: [SubmissionDeletion] = [],
        ratings: [RatingPayload] = [],
        notes: [NotePayload] = [],
        prompts: [PromptPayload] = [],
        polls: [PollPayload] = [],
        votes: [VotePayload] = [],
        meetings: [MeetingPayload] = [],
        rsvps: [RSVPPayload] = []
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.authorMemberID = authorMemberID
        self.authorName = authorName
        self.clubMeta = clubMeta
        self.nameProposal = nameProposal
        self.submissions = submissions
        self.statusOverrides = statusOverrides
        self.detailsOverrides = detailsOverrides
        self.deletedSubmissions = deletedSubmissions
        self.ratings = ratings
        self.notes = notes
        self.prompts = prompts
        self.polls = polls
        self.votes = votes
        self.meetings = meetings
        self.rsvps = rsvps
    }

    struct ClubMeta: Codable, Equatable, Sendable {
        let name: String
        let createdAt: Date
        let cloudZoneName: String
        let shareParticipantCount: Int
        /// Creator's `MemberIdentity.memberID`. Optional for backward
        /// compatibility with snapshots written before this field existed.
        let creatorMemberID: String?
        /// Sorted list of memberIDs granted admin status by the creator.
        /// Optional for backward compatibility.
        let adminMemberIDs: [String]?
        /// Sorted list of memberIDs the owner has removed from the club.
        /// Other devices use this to ignore re-published snapshots from a
        /// removed member. Optional for backward compatibility.
        let removedMemberIDs: [String]?
        let inviteURLString: String?
        let nameUpdatedAt: Date?
    }

    struct NameProposal: Codable, Equatable, Sendable {
        let name: String
        let updatedAt: Date
        let proposerMemberID: String
    }

    struct SubmissionPayload: Codable, Equatable, Sendable {
        let selectionID: String
        let title: String
        let author: String
        let isbn: String
        let submittedBy: String
        let submittedByMemberID: String
        let submittedAt: Date
        let initialStatusRaw: String
        let initialPickedAt: Date?
        let initialCompletedAt: Date?
        let bookDescription: String
        let publishedYear: Int?
        let coverURL: String
        let externalProvider: String
        let externalID: String
    }

    /// Status changes (pick-current, mark-complete, move-to-proposals) recorded
    /// by *any* participant. On merge, the latest override per submission wins.
    struct StatusOverride: Codable, Equatable, Sendable {
        let submissionSelectionID: String
        let statusRaw: String
        let pickedAt: Date?
        let completedAt: Date?
        let occurredAt: Date
    }

    struct SubmissionDetailsOverride: Codable, Equatable, Sendable {
        let submissionSelectionID: String
        let title: String
        let author: String
        let isbn: String
        let bookDescription: String
        let publishedYear: Int?
        let coverURL: String
        let externalProvider: String
        let externalID: String
        let updatedAt: Date
        let actorMemberID: String
    }

    struct SubmissionDeletion: Codable, Equatable, Sendable {
        let submissionSelectionID: String
        let deletedAt: Date
        let actorMemberID: String
    }

    struct RatingPayload: Codable, Equatable, Sendable {
        let submissionSelectionID: String
        let memberID: String
        let memberName: String
        let stars: Int
        let createdAt: Date
    }

    struct NotePayload: Codable, Equatable, Sendable {
        let submissionSelectionID: String
        let memberID: String
        let memberName: String
        let text: String
        let createdAt: Date
    }

    struct PromptPayload: Codable, Equatable, Sendable {
        let promptID: String
        let submissionSelectionID: String
        let createdByMemberID: String
        let question: String
        let orderIndex: Int
        let sourceRaw: String
        let createdAt: Date
        let isArchived: Bool
    }

    struct PollPayload: Codable, Equatable, Sendable {
        let pollID: String
        let createdByMemberID: String
        let title: String
        let createdAt: Date
        let closesAt: Date?
        let statusRaw: String
        let isAnonymousResults: Bool
        let candidateIDsRaw: String
        let winnerSubmissionID: String
    }

    struct VotePayload: Codable, Equatable, Sendable {
        let pollID: String
        let memberID: String
        let memberName: String
        let rankedSubmissionIDsRaw: String
        let updatedAt: Date
    }

    struct MeetingPayload: Codable, Equatable, Sendable {
        let meetingID: String
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
    }

    struct RSVPPayload: Codable, Equatable, Sendable {
        let meetingID: String
        let memberID: String
        let memberName: String
        let statusRaw: String
        let bringingNote: String
        let updatedAt: Date
    }
}

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
                inviteURLString: club.inviteURLString.trimmedOrNil,
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

    /// Additive merge. Reconciles SwiftData rows with the union of all member
    /// snapshots. Local items authored by `localMemberID` are preserved as-is
    /// — they may carry unpublished updates that haven't reached CloudKit yet.
    static func merge(
        snapshots: [MemberShareSnapshot],
        into club: BookClub,
        context: ModelContext,
        localMemberID: String
    ) throws {
        // 1. Apply club meta from the snapshot that carries it (the owner's).
        if let meta = snapshots.compactMap(\.clubMeta).max(by: { $0.shareParticipantCount < $1.shareParticipantCount }) {
            if club.name != meta.name { club.name = meta.name }
            let nextNameUpdatedAt = meta.nameUpdatedAt ?? club.nameUpdatedAt
            if club.nameUpdatedAt != nextNameUpdatedAt { club.nameUpdatedAt = nextNameUpdatedAt }
            if club.createdAt != meta.createdAt { club.createdAt = meta.createdAt }
            if club.cloudZoneName.isEmpty {
                club.cloudZoneName = meta.cloudZoneName
            }
            let participants = max(1, meta.shareParticipantCount)
            if club.shareParticipantCount != participants { club.shareParticipantCount = participants }
            if let creator = meta.creatorMemberID?.trimmedOrNil, club.creatorMemberID != creator {
                club.creatorMemberID = creator
            }
            if let admins = meta.adminMemberIDs {
                let nextAdmins = Set(admins.filter { !$0.isEmpty })
                if club.adminMemberIDs != nextAdmins { club.adminMemberIDs = nextAdmins }
            }
            if let removed = meta.removedMemberIDs {
                let nextRemoved = Set(removed.filter { !$0.isEmpty })
                if club.removedMemberIDs != nextRemoved { club.removedMemberIDs = nextRemoved }
            }
            if let url = meta.inviteURLString?.trimmedOrNil, club.inviteURLString != url {
                club.inviteURLString = url
            }
        }

        let validProposers = club.adminMemberIDs.union(
            club.creatorMemberID.isEmpty ? [] : [club.creatorMemberID]
        )
        let latestProposal = snapshots.lazy
            .compactMap(\.nameProposal)
            .filter { validProposers.contains($0.proposerMemberID) && !$0.name.isEmpty }
            .max(by: { $0.updatedAt < $1.updatedAt })
        if let latestProposal, latestProposal.updatedAt > club.nameUpdatedAt {
            club.name = latestProposal.name
            club.nameUpdatedAt = latestProposal.updatedAt
        }
        club.shareIsActive = true

        // Removed members' snapshots must be filtered before building canonical
        // sets — otherwise step 5's "delete non-canonical, non-local" pass
        // would re-import their rows on every merge.
        let removedAuthors = club.removedMemberIDs
        let activeSnapshots = removedAuthors.isEmpty
            ? snapshots
            : snapshots.filter { !removedAuthors.contains($0.authorMemberID) }

        // 2. Index existing local rows by stable ID for upsert.
        //
        // Predicate-scope each fetch to this club so SQLite filters server-side
        // instead of loading every row and filtering in memory (these run on
        // every CloudKit sync tick). The fetches use `try` rather than `try?`:
        // a failing/migrating store must propagate out of the throwing `merge()`
        // — swallowing it would hand the delete passes below (steps 5/6/7/8) an
        // empty "existing" index against a full canonical set, mass-deleting
        // remote-authored rows on a transient read failure.
        let clubID = club.persistentModelID
        let submissionPredicate = #Predicate<BookSubmission> { $0.bookClub?.persistentModelID == clubID }
        let localSubmissions = try context.fetch(FetchDescriptor<BookSubmission>(predicate: submissionPredicate))
        var submissionsByID: [String: BookSubmission] = [:]
        for sub in localSubmissions where !sub.selectionID.isEmpty {
            submissionsByID[sub.selectionID] = sub
        }
        let preMergeSubmissions = Array(submissionsByID.values)
        let promptPredicate = #Predicate<DiscussionPrompt> { $0.submission?.bookClub?.persistentModelID == clubID }
        let localPrompts = try context.fetch(FetchDescriptor<DiscussionPrompt>(predicate: promptPredicate))
        var promptsByID: [String: DiscussionPrompt] = [:]
        for prompt in localPrompts where !prompt.promptID.isEmpty {
            promptsByID[prompt.promptID] = prompt
        }
        let preMergePromptIDs = Set(promptsByID.keys)
        let pollPredicate = #Predicate<SelectionPoll> { $0.bookClub?.persistentModelID == clubID }
        let localPolls = try context.fetch(FetchDescriptor<SelectionPoll>(predicate: pollPredicate))
        var pollsByID: [String: SelectionPoll] = [:]
        for poll in localPolls where !poll.pollID.isEmpty {
            pollsByID[poll.pollID] = poll
        }
        let preMergePollIDs = Set(pollsByID.keys)
        let meetingPredicate = #Predicate<ClubMeeting> { $0.bookClub?.persistentModelID == clubID }
        let localMeetings = try context.fetch(FetchDescriptor<ClubMeeting>(predicate: meetingPredicate))
        var meetingsByID: [String: ClubMeeting] = [:]
        for meeting in localMeetings where !meeting.meetingID.isEmpty {
            meetingsByID[meeting.meetingID] = meeting
        }
        let preMergeMeetingIDs = Set(meetingsByID.keys)

        // 3. Compute canonical sets from snapshots.
        var canonicalSubmissions: [String: MemberShareSnapshot.SubmissionPayload] = [:]
        var statusOverridesByID: [String: [MemberShareSnapshot.StatusOverride]] = [:]
        var detailsOverridesByID: [String: [MemberShareSnapshot.SubmissionDetailsOverride]] = [:]
        var deletionsByID: [String: [MemberShareSnapshot.SubmissionDeletion]] = [:]
        var canonicalPrompts: [String: MemberShareSnapshot.PromptPayload] = [:]
        var canonicalPolls: [String: MemberShareSnapshot.PollPayload] = [:]
        var canonicalMeetings: [String: MemberShareSnapshot.MeetingPayload] = [:]
        var meetingsBySubmissionID: [String: String] = [:]
        var ratingsByKey: [String: MemberShareSnapshot.RatingPayload] = [:] // "<submissionID>|<memberID>"
        var notesByKey: [String: MemberShareSnapshot.NotePayload] = [:] // "<submissionID>|<memberID>|<createdAt>"
        var votesByKey: [String: MemberShareSnapshot.VotePayload] = [:] // "<pollID>|<memberID>"
        var rsvpsByKey: [String: MemberShareSnapshot.RSVPPayload] = [:] // "<meetingID>|<memberID>"

        for snap in activeSnapshots {
            for sub in snap.submissions {
                canonicalSubmissions[sub.selectionID] = sub
            }
            for ov in snap.statusOverrides {
                statusOverridesByID[ov.submissionSelectionID, default: []].append(ov)
            }
            for override in snap.detailsOverrides ?? [] {
                detailsOverridesByID[override.submissionSelectionID, default: []].append(override)
            }
            for deletion in snap.deletedSubmissions ?? [] {
                deletionsByID[deletion.submissionSelectionID, default: []].append(deletion)
            }
            for prompt in snap.prompts {
                canonicalPrompts[prompt.promptID] = prompt
            }
            for poll in snap.polls {
                canonicalPolls[poll.pollID] = poll
            }
            for meeting in snap.meetings {
                canonicalMeetings[meeting.meetingID] = meeting
                if let submissionID = meeting.submissionSelectionID {
                    meetingsBySubmissionID[meeting.meetingID] = submissionID
                }
            }
            for rating in snap.ratings {
                let key = "\(rating.submissionSelectionID)|\(rating.memberID)"
                if let existing = ratingsByKey[key], existing.createdAt >= rating.createdAt { continue }
                ratingsByKey[key] = rating
            }
            for note in snap.notes {
                let key = "\(note.submissionSelectionID)|\(note.memberID)|\(note.createdAt.timeIntervalSince1970)"
                notesByKey[key] = note
            }
            for vote in snap.votes {
                let key = "\(vote.pollID)|\(vote.memberID)"
                if let existing = votesByKey[key], existing.updatedAt >= vote.updatedAt { continue }
                votesByKey[key] = vote
            }
            for rsvp in snap.rsvps {
                let key = "\(rsvp.meetingID)|\(rsvp.memberID)"
                if let existing = rsvpsByKey[key], existing.updatedAt >= rsvp.updatedAt { continue }
                rsvpsByKey[key] = rsvp
            }
        }

        let deletedSubmissionIDs = Set(deletionsByID.keys)
        for selectionID in deletedSubmissionIDs {
            if let sub = submissionsByID.removeValue(forKey: selectionID) {
                context.delete(sub)
            }
        }

        // 4. Upsert submissions.
        for (selectionID, payload) in canonicalSubmissions {
            if deletedSubmissionIDs.contains(selectionID) { continue }
            let submission: BookSubmission
            if let existing = submissionsByID[selectionID] {
                submission = existing
            } else {
                submission = BookSubmission()
                context.insert(submission)
                club.addSubmission(submission)
                submissionsByID[selectionID] = submission
            }
            submission.selectionID = payload.selectionID
            submission.title = payload.title
            submission.author = payload.author
            submission.isbn = payload.isbn
            submission.submittedBy = payload.submittedBy
            submission.submittedByMemberID = payload.submittedByMemberID
            submission.submittedAt = payload.submittedAt
            submission.bookDescription = payload.bookDescription
            submission.publishedYear = payload.publishedYear
            submission.coverURL = payload.coverURL
            submission.externalProvider = payload.externalProvider
            submission.externalID = payload.externalID
            submission.coverData = nil

            if let latestDetails = detailsOverridesByID[selectionID]?.max(by: { $0.updatedAt < $1.updatedAt }) {
                submission.title = latestDetails.title
                submission.author = latestDetails.author
                submission.isbn = latestDetails.isbn
                submission.bookDescription = latestDetails.bookDescription
                submission.publishedYear = latestDetails.publishedYear
                submission.coverURL = latestDetails.coverURL
                submission.externalProvider = latestDetails.externalProvider
                submission.externalID = latestDetails.externalID
                submission.coverData = nil
            }

            let overrides = statusOverridesByID[selectionID] ?? []
            if let latest = overrides.max(by: { $0.occurredAt < $1.occurredAt }) {
                submission.statusRaw = latest.statusRaw
                submission.pickedAt = latest.pickedAt
                submission.completedAt = latest.completedAt
            } else {
                submission.statusRaw = payload.initialStatusRaw
                submission.pickedAt = payload.initialPickedAt
                submission.completedAt = payload.initialCompletedAt
            }
            if submission.bookClub?.persistentModelID != clubID {
                club.addSubmission(submission)
            }
        }

        // 5. Delete local submissions not in canonical, except those authored
        //    locally (might be unpublished new additions).
        for (selectionID, sub) in submissionsByID where canonicalSubmissions[selectionID] == nil {
            if isAuthor(localMemberID, of: sub.submittedByMemberID) { continue }
            context.delete(sub)
        }

        // 6. Upsert prompts.
        for (promptID, payload) in canonicalPrompts {
            guard let parent = submissionsByID[payload.submissionSelectionID] else { continue }
            let prompt: DiscussionPrompt
            if let existing = promptsByID[promptID] {
                prompt = existing
            } else {
                prompt = DiscussionPrompt()
                context.insert(prompt)
                promptsByID[promptID] = prompt
            }
            prompt.promptID = payload.promptID
            prompt.question = payload.question
            prompt.orderIndex = payload.orderIndex
            prompt.sourceRaw = payload.sourceRaw
            prompt.createdAt = payload.createdAt
            prompt.isArchived = payload.isArchived
            prompt.createdByMemberID = payload.createdByMemberID
            prompt.submission = parent
        }
        for (promptID, prompt) in promptsByID where canonicalPrompts[promptID] == nil {
            if isAuthor(localMemberID, of: prompt.createdByMemberID) { continue }
            // Starter prompts (empty createdByMemberID) are auto-generated locally
            // and not synced — leave them in place.
            if prompt.createdByMemberID.isEmpty { continue }
            context.delete(prompt)
        }

        // 7. Upsert polls.
        for (pollID, payload) in canonicalPolls {
            let poll: SelectionPoll
            if let existing = pollsByID[pollID] {
                poll = existing
            } else {
                poll = SelectionPoll()
                context.insert(poll)
                club.addSelectionPoll(poll)
                pollsByID[pollID] = poll
            }
            poll.pollID = payload.pollID
            poll.createdByMemberID = payload.createdByMemberID
            poll.title = payload.title
            poll.createdAt = payload.createdAt
            poll.closesAt = payload.closesAt
            poll.statusRaw = payload.statusRaw
            poll.isAnonymousResults = payload.isAnonymousResults
            poll.candidateIDsRaw = payload.candidateIDsRaw
            poll.winnerSubmissionID = payload.winnerSubmissionID
            if poll.bookClub?.persistentModelID != clubID {
                club.addSelectionPoll(poll)
            }
        }
        for (pollID, poll) in pollsByID where canonicalPolls[pollID] == nil {
            if isAuthor(localMemberID, of: poll.createdByMemberID) { continue }
            context.delete(poll)
        }

        // 8. Upsert meetings.
        for (meetingID, payload) in canonicalMeetings {
            let meeting: ClubMeeting
            if let existing = meetingsByID[meetingID] {
                meeting = existing
            } else {
                meeting = ClubMeeting()
                context.insert(meeting)
                club.addMeeting(meeting)
                meetingsByID[meetingID] = meeting
            }
            meeting.meetingID = payload.meetingID
            meeting.title = payload.title
            meeting.scheduledAt = payload.scheduledAt
            meeting.hostName = payload.hostName
            meeting.hostMemberID = payload.hostMemberID
            meeting.location = payload.location
            meeting.meetingURL = payload.meetingURL
            meeting.reminderOffsetsRaw = payload.reminderOffsetsRaw
            meeting.agenda = payload.agenda
            meeting.createdAt = payload.createdAt
            meeting.completedAt = payload.completedAt
            meeting.bookSubmission = payload.submissionSelectionID.flatMap { submissionsByID[$0] }
            if meeting.bookClub?.persistentModelID != clubID {
                club.addMeeting(meeting)
            }
        }
        for (meetingID, meeting) in meetingsByID where canonicalMeetings[meetingID] == nil {
            if isAuthor(localMemberID, of: meeting.hostMemberID) { continue }
            context.delete(meeting)
        }

        // 9. Reconcile per-submission ratings/notes (own ratings/notes are
        //    preserved verbatim; remote authors' are upserted/pruned to match
        //    canonical).
        applyRatings(canonical: ratingsByKey, submissionsByID: submissionsByID, localMemberID: localMemberID, context: context)
        applyNotes(canonical: notesByKey, submissionsByID: submissionsByID, localMemberID: localMemberID, context: context)

        // 10. Reconcile votes per poll (one canonical vote per (poll, member)).
        applyVotes(canonical: votesByKey, pollsByID: pollsByID, localMemberID: localMemberID, context: context)

        // 11. Reconcile RSVPs per meeting (one canonical RSVP per (meeting, member)).
        applyRSVPs(canonical: rsvpsByKey, meetingsByID: meetingsByID, localMemberID: localMemberID, context: context)

        // 12. Notification events (only after we have a baseline snapshot —
        //     never on first import or we'd flood the user).
        let notificationEvents: [BookLoomNotificationEvent]
        if let baseline = club.lastSharedSnapshotAt {
            notificationEvents = BookLoomNotificationEvent.events(
                clubName: club.name,
                previousSubmissions: preMergeSubmissions,
                previousPromptIDs: preMergePromptIDs,
                previousPollIDs: preMergePollIDs,
                previousMeetingIDs: preMergeMeetingIDs,
                canonicalSubmissions: Array(canonicalSubmissions.values),
                canonicalStatusOverrides: statusOverridesByID.values.flatMap { $0 },
                canonicalRatings: Array(ratingsByKey.values),
                canonicalNotes: Array(notesByKey.values),
                canonicalPrompts: Array(canonicalPrompts.values),
                canonicalPolls: Array(canonicalPolls.values),
                canonicalMeetings: Array(canonicalMeetings.values),
                localMemberID: localMemberID,
                sinceCapturedAt: baseline
            )
        } else {
            notificationEvents = []
        }

        let latestCaptureAt = activeSnapshots.map(\.capturedAt).max() ?? .now
        club.lastSharedSnapshotAt = latestCaptureAt

        var roster = club.knownMemberRoster
        for snap in activeSnapshots {
            let trimmedID = snap.authorMemberID.trimmedOrNil
            let trimmedName = snap.authorName.trimmedOrNil
            guard let id = trimmedID, let name = trimmedName else { continue }
            roster[id] = name
        }
        club.knownMemberRoster = roster

        // Once a status override has appeared in a remote snapshot, we no
        // longer need to keep echoing it from local cache.
        let allOverrides = statusOverridesByID.values.flatMap { $0 }
        club.pruneAcknowledgedStatusOverrides(merged: allOverrides)
        let allDetailsOverrides = detailsOverridesByID.values.flatMap { $0 }
        club.pruneAcknowledgedSubmissionDetailsOverrides(merged: allDetailsOverrides)
        let allDeletions = deletionsByID.values.flatMap { $0 }
        club.pruneAcknowledgedSubmissionDeletions(merged: allDeletions)

        try context.save()

        if !notificationEvents.isEmpty {
            Task {
                await BookLoomUserNotifications.schedule(notificationEvents)
            }
        }
    }

    // MARK: - Helpers

    private static func isAuthor(_ localMemberID: String, of recordedMemberID: String) -> Bool {
        guard !localMemberID.isEmpty else { return false }
        return recordedMemberID == localMemberID
    }

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

    /// Reconcile a per-parent collection (ratings on submissions, votes on
    /// polls, RSVPs on meetings, etc.) against the canonical payloads. The
    /// generic version pre-builds an index of existing rows keyed by
    /// `existingKey` so the upsert is O(canonical + existing) rather than
    /// quadratic.
    private static func reconcileCollection<Parent, Existing: PersistentModel, Payload>(
        parents: some Collection<Parent>,
        canonical: [String: Payload],
        parentKey: (Parent) -> String,
        canonicalParentKey: (Payload) -> String,
        existingChildren: (Parent) -> [Existing],
        existingKey: (Existing) -> String,
        existingMemberID: (Existing) -> String,
        canonicalKey: (Payload) -> String,
        canonicalMemberID: (Payload) -> String,
        localMemberID: String,
        context: ModelContext,
        update: (Existing, Payload) -> Void,
        insert: (Parent, Payload) -> Void
    ) {
        var canonicalByParent: [String: [Payload]] = [:]
        for payload in canonical.values {
            canonicalByParent[canonicalParentKey(payload), default: []].append(payload)
        }
        for parent in parents {
            let canonicalForParent = canonicalByParent[parentKey(parent)] ?? []
            let canonicalKeys = Set(canonicalForParent.map(canonicalKey))
            let existing = existingChildren(parent)
            // Tolerate stray duplicates (e.g. legacy rows): last-write wins.
            let existingByKey = Dictionary(existing.map { (existingKey($0), $0) }, uniquingKeysWith: { _, latest in latest })

            for child in existing where !isAuthor(localMemberID, of: existingMemberID(child)) {
                if !canonicalKeys.contains(existingKey(child)) {
                    context.delete(child)
                }
            }
            for payload in canonicalForParent where !isAuthor(localMemberID, of: canonicalMemberID(payload)) {
                if let existing = existingByKey[canonicalKey(payload)] {
                    update(existing, payload)
                } else {
                    insert(parent, payload)
                }
            }
        }
    }

    private static func applyRatings(
        canonical: [String: MemberShareSnapshot.RatingPayload],
        submissionsByID: [String: BookSubmission],
        localMemberID: String,
        context: ModelContext
    ) {
        reconcileCollection(
            parents: submissionsByID.values,
            canonical: canonical,
            parentKey: \.selectionID,
            canonicalParentKey: \.submissionSelectionID,
            existingChildren: { $0.ratings ?? [] },
            existingKey: \.memberID,
            existingMemberID: \.memberID,
            canonicalKey: \.memberID,
            canonicalMemberID: \.memberID,
            localMemberID: localMemberID,
            context: context,
            update: { rating, payload in
                rating.memberName = payload.memberName
                rating.stars = payload.stars
                rating.createdAt = payload.createdAt
            },
            insert: { submission, payload in
                let rating = Rating(
                    memberID: payload.memberID,
                    memberName: payload.memberName,
                    stars: payload.stars,
                    createdAt: payload.createdAt
                )
                rating.submission = submission
                context.insert(rating)
                var ratings = submission.ratings ?? []
                ratings.append(rating)
                submission.ratings = ratings
            }
        )
    }

    private static func applyNotes(
        canonical: [String: MemberShareSnapshot.NotePayload],
        submissionsByID: [String: BookSubmission],
        localMemberID: String,
        context: ModelContext
    ) {
        // Notes are keyed by (memberID, createdAt) so multiple notes per
        // member per submission are preserved.
        let noteKey: (String, Date) -> String = { "\($0)|\($1.timeIntervalSince1970)" }
        reconcileCollection(
            parents: submissionsByID.values,
            canonical: canonical,
            parentKey: \.selectionID,
            canonicalParentKey: \.submissionSelectionID,
            existingChildren: { $0.notes ?? [] },
            existingKey: { noteKey($0.memberID, $0.createdAt) },
            existingMemberID: \.memberID,
            canonicalKey: { noteKey($0.memberID, $0.createdAt) },
            canonicalMemberID: \.memberID,
            localMemberID: localMemberID,
            context: context,
            update: { note, payload in
                note.memberName = payload.memberName
                note.text = payload.text
            },
            insert: { submission, payload in
                let note = BookNote(
                    memberID: payload.memberID,
                    memberName: payload.memberName,
                    text: payload.text,
                    createdAt: payload.createdAt
                )
                note.submission = submission
                context.insert(note)
                var notes = submission.notes ?? []
                notes.append(note)
                submission.notes = notes
            }
        )
    }

    private static func applyVotes(
        canonical: [String: MemberShareSnapshot.VotePayload],
        pollsByID: [String: SelectionPoll],
        localMemberID: String,
        context: ModelContext
    ) {
        reconcileCollection(
            parents: pollsByID.values,
            canonical: canonical,
            parentKey: \.pollID,
            canonicalParentKey: \.pollID,
            existingChildren: { $0.votes ?? [] },
            existingKey: \.memberID,
            existingMemberID: \.memberID,
            canonicalKey: \.memberID,
            canonicalMemberID: \.memberID,
            localMemberID: localMemberID,
            context: context,
            update: { vote, payload in
                vote.memberName = payload.memberName
                vote.rankedSubmissionIDsRaw = payload.rankedSubmissionIDsRaw
                vote.updatedAt = payload.updatedAt
            },
            insert: { poll, payload in
                let vote = BookVote(
                    memberID: payload.memberID,
                    memberName: payload.memberName,
                    rankedSubmissionIDs: SelectionPoll.decodeIDs(payload.rankedSubmissionIDsRaw),
                    updatedAt: payload.updatedAt
                )
                vote.poll = poll
                context.insert(vote)
                var votes = poll.votes ?? []
                votes.append(vote)
                poll.votes = votes
            }
        )
    }

    private static func applyRSVPs(
        canonical: [String: MemberShareSnapshot.RSVPPayload],
        meetingsByID: [String: ClubMeeting],
        localMemberID: String,
        context: ModelContext
    ) {
        reconcileCollection(
            parents: meetingsByID.values,
            canonical: canonical,
            parentKey: \.meetingID,
            canonicalParentKey: \.meetingID,
            existingChildren: { $0.rsvps ?? [] },
            existingKey: \.memberID,
            existingMemberID: \.memberID,
            canonicalKey: \.memberID,
            canonicalMemberID: \.memberID,
            localMemberID: localMemberID,
            context: context,
            update: { rsvp, payload in
                rsvp.memberName = payload.memberName
                rsvp.statusRaw = payload.statusRaw
                rsvp.bringingNote = payload.bringingNote
                rsvp.updatedAt = payload.updatedAt
            },
            insert: { meeting, payload in
                let rsvp = MeetingRSVP(
                    memberID: payload.memberID,
                    memberName: payload.memberName,
                    status: MeetingRSVPStatus(rawValue: payload.statusRaw) ?? .attending,
                    bringingNote: payload.bringingNote,
                    updatedAt: payload.updatedAt
                )
                rsvp.meeting = meeting
                context.insert(rsvp)
                var rsvps = meeting.rsvps ?? []
                rsvps.append(rsvp)
                meeting.rsvps = rsvps
            }
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
}

/// Status overrides are recorded out-of-band (a small in-memory log on the
/// club) when a user picks/completes/moves-back a book. They are flushed into
/// the local member's published snapshot on each save and persisted across
/// app launches via UserDefaults so unsynced overrides survive a restart.
struct StatusOverrideEntry: Codable, Equatable {
    let submissionSelectionID: String
    let statusRaw: String
    let pickedAt: Date?
    let completedAt: Date?
    let occurredAt: Date
    let actorMemberID: String
}

struct SubmissionDetailsOverrideEntry: Codable, Equatable {
    let submissionSelectionID: String
    let title: String
    let author: String
    let isbn: String
    let bookDescription: String
    let publishedYear: Int?
    let coverURL: String
    let externalProvider: String
    let externalID: String
    let updatedAt: Date
    let actorMemberID: String
}

struct SubmissionDeletionEntry: Codable, Equatable {
    let submissionSelectionID: String
    let deletedAt: Date
    let actorMemberID: String
}

extension BookClub {
    /// In-memory cache of recent status overrides that haven't yet been
    /// observed in a remote snapshot for confirmation. Backed by UserDefaults
    /// keyed on the cloud zone so the log survives app restarts.
    var statusOverrideLog: [StatusOverrideEntry] {
        StatusOverrideStore.entries(forZone: cloudZoneName)
    }

    var submissionDetailsOverrideLog: [SubmissionDetailsOverrideEntry] {
        SubmissionDetailsOverrideStore.entries(forZone: cloudZoneName)
    }

    var submissionDeletionLog: [SubmissionDeletionEntry] {
        SubmissionDeletionStore.entries(forZone: cloudZoneName)
    }

    func recordStatusOverride(_ entry: StatusOverrideEntry) {
        StatusOverrideStore.append(entry, forZone: cloudZoneName)
    }

    func recordSubmissionDetailsOverride(_ entry: SubmissionDetailsOverrideEntry) {
        SubmissionDetailsOverrideStore.append(entry, forZone: cloudZoneName)
    }

    func recordSubmissionDeletion(_ entry: SubmissionDeletionEntry) {
        SubmissionDeletionStore.append(entry, forZone: cloudZoneName)
    }

    func pruneAcknowledgedStatusOverrides(merged: [MemberShareSnapshot.StatusOverride]) {
        let keys: Set<String> = Set(merged.map { "\($0.submissionSelectionID)|\($0.occurredAt.timeIntervalSince1970)" })
        StatusOverrideStore.pruneEntries(forZone: cloudZoneName, where: { entry in
            keys.contains("\(entry.submissionSelectionID)|\(entry.occurredAt.timeIntervalSince1970)")
        })
    }

    func pruneAcknowledgedSubmissionDetailsOverrides(merged: [MemberShareSnapshot.SubmissionDetailsOverride]) {
        let keys: Set<String> = Set(merged.map { "\($0.submissionSelectionID)|\($0.updatedAt.timeIntervalSince1970)" })
        SubmissionDetailsOverrideStore.pruneEntries(forZone: cloudZoneName, where: { entry in
            keys.contains("\(entry.submissionSelectionID)|\(entry.updatedAt.timeIntervalSince1970)")
        })
    }

    func pruneAcknowledgedSubmissionDeletions(merged: [MemberShareSnapshot.SubmissionDeletion]) {
        let keys: Set<String> = Set(merged.map { "\($0.submissionSelectionID)|\($0.deletedAt.timeIntervalSince1970)" })
        SubmissionDeletionStore.pruneEntries(forZone: cloudZoneName, where: { entry in
            keys.contains("\(entry.submissionSelectionID)|\(entry.deletedAt.timeIntervalSince1970)")
        })
    }
}

enum StatusOverrideStore {
    static let prefix = "net.shadowpuppet.BookLoom.statusOverrides."

    static func entries(forZone zone: String) -> [StatusOverrideEntry] {
        guard !zone.isEmpty,
              let data = UserDefaults.standard.data(forKey: prefix + zone),
              let entries = try? JSONDecoder().decode([StatusOverrideEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func append(_ entry: StatusOverrideEntry, forZone zone: String) {
        guard !zone.isEmpty else { return }
        var current = entries(forZone: zone)
        current.removeAll { $0.submissionSelectionID == entry.submissionSelectionID && $0.actorMemberID == entry.actorMemberID }
        current.append(entry)
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: prefix + zone)
        }
    }

    static func pruneEntries(forZone zone: String, where shouldRemove: (StatusOverrideEntry) -> Bool) {
        guard !zone.isEmpty else { return }
        let kept = entries(forZone: zone).filter { !shouldRemove($0) }
        if let data = try? JSONEncoder().encode(kept) {
            UserDefaults.standard.set(data, forKey: prefix + zone)
        }
    }

    static func clear(forZone zone: String) {
        guard !zone.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: prefix + zone)
    }
}

enum SubmissionDetailsOverrideStore {
    static let prefix = "net.shadowpuppet.BookLoom.submissionDetailsOverrides."

    static func entries(forZone zone: String) -> [SubmissionDetailsOverrideEntry] {
        guard !zone.isEmpty,
              let data = UserDefaults.standard.data(forKey: prefix + zone),
              let entries = try? JSONDecoder().decode([SubmissionDetailsOverrideEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func append(_ entry: SubmissionDetailsOverrideEntry, forZone zone: String) {
        guard !zone.isEmpty else { return }
        var current = entries(forZone: zone)
        current.removeAll { $0.submissionSelectionID == entry.submissionSelectionID && $0.actorMemberID == entry.actorMemberID }
        current.append(entry)
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: prefix + zone)
        }
    }

    static func pruneEntries(forZone zone: String, where shouldRemove: (SubmissionDetailsOverrideEntry) -> Bool) {
        guard !zone.isEmpty else { return }
        let kept = entries(forZone: zone).filter { !shouldRemove($0) }
        if let data = try? JSONEncoder().encode(kept) {
            UserDefaults.standard.set(data, forKey: prefix + zone)
        }
    }

    static func clear(forZone zone: String) {
        guard !zone.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: prefix + zone)
    }
}

enum SubmissionDeletionStore {
    static let prefix = "net.shadowpuppet.BookLoom.submissionDeletions."

    static func entries(forZone zone: String) -> [SubmissionDeletionEntry] {
        guard !zone.isEmpty,
              let data = UserDefaults.standard.data(forKey: prefix + zone),
              let entries = try? JSONDecoder().decode([SubmissionDeletionEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func append(_ entry: SubmissionDeletionEntry, forZone zone: String) {
        guard !zone.isEmpty else { return }
        var current = entries(forZone: zone)
        current.removeAll { $0.submissionSelectionID == entry.submissionSelectionID && $0.actorMemberID == entry.actorMemberID }
        current.append(entry)
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: prefix + zone)
        }
    }

    static func pruneEntries(forZone zone: String, where shouldRemove: (SubmissionDeletionEntry) -> Bool) {
        guard !zone.isEmpty else { return }
        let kept = entries(forZone: zone).filter { !shouldRemove($0) }
        if let data = try? JSONEncoder().encode(kept) {
            UserDefaults.standard.set(data, forKey: prefix + zone)
        }
    }

    static func clear(forZone zone: String) {
        guard !zone.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: prefix + zone)
    }
}

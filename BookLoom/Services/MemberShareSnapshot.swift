import Foundation

/// Per-author CKShare payload. Each participant publishes one of these into
/// the shared zone (a separate CKRecord named `MemberSnapshot-<memberID>`),
/// containing only their own contributions. All clients fetch every member's
/// snapshot and merge them into the local SwiftData store.
///
/// This replaces the earlier single-document `SharedClubSnapshot`, which only
/// supported owner-broadcast and silently dropped any contributions from
/// non-owner participants.
struct MemberShareSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 5

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
        /// Owner-signed identity bindings. A member ID is accepted only when
        /// the enclosing record's CloudKit creator matches this mapping.
        let memberIdentityBindings: [MemberIdentityBinding]?
        let metadataUpdatedAt: Date?
        let inviteURLString: String?
        let nameUpdatedAt: Date?

        init(
            name: String,
            createdAt: Date,
            cloudZoneName: String,
            shareParticipantCount: Int,
            creatorMemberID: String?,
            adminMemberIDs: [String]?,
            removedMemberIDs: [String]?,
            memberIdentityBindings: [MemberIdentityBinding]? = nil,
            metadataUpdatedAt: Date? = nil,
            inviteURLString: String?,
            nameUpdatedAt: Date?
        ) {
            self.name = name
            self.createdAt = createdAt
            self.cloudZoneName = cloudZoneName
            self.shareParticipantCount = shareParticipantCount
            self.creatorMemberID = creatorMemberID
            self.adminMemberIDs = adminMemberIDs
            self.removedMemberIDs = removedMemberIDs
            self.memberIdentityBindings = memberIdentityBindings
            self.metadataUpdatedAt = metadataUpdatedAt
            self.inviteURLString = inviteURLString
            self.nameUpdatedAt = nameUpdatedAt
        }
    }

    struct MemberIdentityBinding: Codable, Equatable, Sendable {
        let memberID: String
        let cloudKitUserRecordName: String
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

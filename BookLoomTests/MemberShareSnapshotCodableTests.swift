import Foundation
import XCTest
@testable import BookLoom

/// `MemberShareSnapshot` is the wire format published per-author into the
/// shared CloudKit zone. A decode failure on a record written by an older or
/// newer client silently drops that member's contributions, so these tests
/// pin both encode→decode losslessness and tolerant decoding of legacy
/// payloads that predate the optional fields added in schemaVersion 3.
final class MemberShareSnapshotCodableTests: XCTestCase {
    private func makeFullyPopulatedSnapshot() -> MemberShareSnapshot {
        MemberShareSnapshot(
            schemaVersion: MemberShareSnapshot.schemaVersion,
            capturedAt: Date(timeIntervalSince1970: 9_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: "Sunday Pages",
                createdAt: Date(timeIntervalSince1970: 1_000),
                cloudZoneName: "BookClub-Test",
                shareParticipantCount: 3,
                creatorMemberID: "member-alex",
                adminMemberIDs: ["member-alex", "member-lena"],
                removedMemberIDs: ["member-kim"],
                inviteURLString: "https://www.icloud.com/share/0Aabcdef",
                nameUpdatedAt: Date(timeIntervalSince1970: 2_000)
            ),
            nameProposal: MemberShareSnapshot.NameProposal(
                name: "Sunday Mornings",
                updatedAt: Date(timeIntervalSince1970: 2_500),
                proposerMemberID: "member-lena"
            ),
            submissions: [
                MemberShareSnapshot.SubmissionPayload(
                    selectionID: "sel-piranesi",
                    title: "Piranesi",
                    author: "Susanna Clarke",
                    isbn: "9781635575637",
                    submittedBy: "Alex",
                    submittedByMemberID: "member-alex",
                    submittedAt: Date(timeIntervalSince1970: 1_100),
                    initialStatusRaw: BookSubmissionStatus.current.rawValue,
                    initialPickedAt: Date(timeIntervalSince1970: 1_200),
                    initialCompletedAt: nil,
                    bookDescription: "A labyrinthine novel.",
                    publishedYear: 2020,
                    coverURL: "https://example.com/piranesi.jpg",
                    externalProvider: "Open Library",
                    externalID: "OL1"
                )
            ],
            statusOverrides: [
                MemberShareSnapshot.StatusOverride(
                    submissionSelectionID: "sel-piranesi",
                    statusRaw: BookSubmissionStatus.completed.rawValue,
                    pickedAt: Date(timeIntervalSince1970: 1_200),
                    completedAt: Date(timeIntervalSince1970: 3_000),
                    occurredAt: Date(timeIntervalSince1970: 3_000)
                )
            ],
            detailsOverrides: [
                MemberShareSnapshot.SubmissionDetailsOverride(
                    submissionSelectionID: "sel-piranesi",
                    title: "Piranesi: Deluxe",
                    author: "Susanna Clarke",
                    isbn: "9781635575637",
                    bookDescription: "Updated.",
                    publishedYear: 2021,
                    coverURL: "https://example.com/new.jpg",
                    externalProvider: "Google Books",
                    externalID: "gb-1",
                    updatedAt: Date(timeIntervalSince1970: 3_100),
                    actorMemberID: "member-lena"
                )
            ],
            deletedSubmissions: [
                MemberShareSnapshot.SubmissionDeletion(
                    submissionSelectionID: "sel-old",
                    deletedAt: Date(timeIntervalSince1970: 3_200),
                    actorMemberID: "member-alex"
                )
            ],
            ratings: [
                MemberShareSnapshot.RatingPayload(
                    submissionSelectionID: "sel-piranesi",
                    memberID: "member-alex",
                    memberName: "Alex",
                    stars: 5,
                    createdAt: Date(timeIntervalSince1970: 1_800)
                )
            ],
            notes: [
                MemberShareSnapshot.NotePayload(
                    submissionSelectionID: "sel-piranesi",
                    memberID: "member-alex",
                    memberName: "Alex",
                    text: "Great pick.",
                    createdAt: Date(timeIntervalSince1970: 1_900)
                )
            ],
            prompts: [
                MemberShareSnapshot.PromptPayload(
                    promptID: "prompt-1",
                    submissionSelectionID: "sel-piranesi",
                    createdByMemberID: "member-alex",
                    question: "What did the statues mean?",
                    orderIndex: 0,
                    sourceRaw: DiscussionPromptSource.custom.rawValue,
                    createdAt: Date(timeIntervalSince1970: 2_100),
                    isArchived: false
                )
            ],
            polls: [
                MemberShareSnapshot.PollPayload(
                    pollID: "poll-1",
                    createdByMemberID: "member-alex",
                    title: "Next Pick",
                    createdAt: Date(timeIntervalSince1970: 2_200),
                    closesAt: Date(timeIntervalSince1970: 9_999),
                    statusRaw: SelectionPollStatus.open.rawValue,
                    isAnonymousResults: true,
                    candidateIDsRaw: "sel-piranesi,sel-other",
                    winnerSubmissionID: ""
                )
            ],
            votes: [
                MemberShareSnapshot.VotePayload(
                    pollID: "poll-1",
                    memberID: "member-alex",
                    memberName: "Alex",
                    rankedSubmissionIDsRaw: "sel-piranesi,sel-other",
                    updatedAt: Date(timeIntervalSince1970: 2_300)
                )
            ],
            meetings: [
                MemberShareSnapshot.MeetingPayload(
                    meetingID: "meeting-1",
                    title: "Piranesi Discussion",
                    scheduledAt: Date(timeIntervalSince1970: 5_000),
                    hostName: "Alex",
                    hostMemberID: "member-alex",
                    location: "Library",
                    meetingURL: "https://example.com/call",
                    reminderOffsetsRaw: "1440,60",
                    agenda: "Discuss chapters 1-5.",
                    createdAt: Date(timeIntervalSince1970: 2_400),
                    completedAt: nil,
                    submissionSelectionID: "sel-piranesi"
                )
            ],
            rsvps: [
                MemberShareSnapshot.RSVPPayload(
                    meetingID: "meeting-1",
                    memberID: "member-alex",
                    memberName: "Alex",
                    statusRaw: MeetingRSVPStatus.attending.rawValue,
                    bringingNote: "Snacks",
                    updatedAt: Date(timeIntervalSince1970: 2_450)
                )
            ]
        )
    }

    func test_memberShareSnapshotRoundTripsFullyPopulated() throws {
        let original = makeFullyPopulatedSnapshot()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MemberShareSnapshot.self, from: data)

        XCTAssertEqual(decoded, original)
        // Spot-check the nested optionals survived rather than relying solely on
        // the synthesized Equatable conformance.
        XCTAssertEqual(decoded.clubMeta?.adminMemberIDs, ["member-alex", "member-lena"])
        XCTAssertEqual(decoded.detailsOverrides?.count, 1)
        XCTAssertEqual(decoded.deletedSubmissions?.first?.submissionSelectionID, "sel-old")
        XCTAssertEqual(decoded.nameProposal?.name, "Sunday Mornings")
        XCTAssertEqual(decoded.votes.first?.rankedSubmissionIDsRaw, "sel-piranesi,sel-other")
        XCTAssertEqual(decoded.rsvps.first?.bringingNote, "Snacks")
    }

    func test_memberShareSnapshotDecodesLegacyPayloadWithoutOptionalFields() throws {
        // A legacy record that omits the optional fields added for backward
        // compatibility: clubMeta, nameProposal, detailsOverrides, and
        // deletedSubmissions. These are the only members declared optional on
        // `MemberShareSnapshot`, so they are the fields an older client could
        // legitimately leave out. They must decode as nil — not throw and drop
        // the member's submissions/ratings/prompts/polls/votes/meetings/rsvps.
        //
        // Note: the array members (submissions, statusOverrides, ratings, notes,
        // prompts, polls, votes, meetings, rsvps) are NOT optional in the
        // current schema, so a conforming payload still carries them (empty is
        // fine). This test pins exactly which fields the decoder tolerates as
        // absent — a regression that made one of these optional arrays required,
        // or one of the currently-optional fields required, would change that.
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "capturedAt": 1000,
          "authorMemberID": "member-legacy",
          "authorName": "Legacy",
          "submissions": [
            {
              "selectionID": "sel-legacy",
              "title": "Old Book",
              "author": "Old Author",
              "isbn": "",
              "submittedBy": "Legacy",
              "submittedByMemberID": "member-legacy",
              "submittedAt": 1100,
              "initialStatusRaw": "proposed",
              "bookDescription": "",
              "coverURL": "",
              "externalProvider": "",
              "externalID": ""
            }
          ],
          "statusOverrides": [],
          "ratings": [
            {
              "submissionSelectionID": "sel-legacy",
              "memberID": "member-legacy",
              "memberName": "Legacy",
              "stars": 4,
              "createdAt": 1200
            }
          ],
          "notes": [],
          "prompts": [],
          "polls": [],
          "votes": [],
          "meetings": [],
          "rsvps": []
        }
        """

        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(MemberShareSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.authorMemberID, "member-legacy")
        XCTAssertEqual(decoded.submissions.map(\.selectionID), ["sel-legacy"])
        XCTAssertNil(decoded.submissions.first?.initialPickedAt, "Optional submission dates decode as nil when absent")
        XCTAssertNil(decoded.submissions.first?.publishedYear)
        XCTAssertEqual(decoded.ratings.first?.stars, 4)
        XCTAssertNil(decoded.clubMeta, "Missing clubMeta must decode as nil, not throw")
        XCTAssertNil(decoded.nameProposal, "Missing nameProposal must decode as nil")
        XCTAssertNil(decoded.detailsOverrides, "Missing detailsOverrides must decode as nil")
        XCTAssertNil(decoded.deletedSubmissions, "Missing deletedSubmissions must decode as nil")
    }

    func test_clubMetaDecodesLegacyPayloadWithoutNewerOptionalFields() throws {
        // A ClubMeta written before creatorMemberID/adminMemberIDs/
        // removedMemberIDs/inviteURLString/nameUpdatedAt existed. The merge
        // engine reads these optionals defensively; decoding must not throw.
        let legacyJSON = """
        {
          "schemaVersion": 2,
          "capturedAt": 5000,
          "authorMemberID": "member-owner",
          "authorName": "Owner",
          "clubMeta": {
            "name": "Sunday Pages",
            "createdAt": 1000,
            "cloudZoneName": "BookClub-Test",
            "shareParticipantCount": 2
          },
          "submissions": [],
          "statusOverrides": [],
          "ratings": [],
          "notes": [],
          "prompts": [],
          "polls": [],
          "votes": [],
          "meetings": [],
          "rsvps": []
        }
        """

        let decoded = try JSONDecoder().decode(MemberShareSnapshot.self, from: Data(legacyJSON.utf8))

        let meta = try XCTUnwrap(decoded.clubMeta)
        XCTAssertEqual(meta.name, "Sunday Pages")
        XCTAssertEqual(meta.shareParticipantCount, 2)
        XCTAssertNil(meta.creatorMemberID)
        XCTAssertNil(meta.adminMemberIDs)
        XCTAssertNil(meta.removedMemberIDs)
        XCTAssertNil(meta.inviteURLString)
        XCTAssertNil(meta.nameUpdatedAt)
    }
}

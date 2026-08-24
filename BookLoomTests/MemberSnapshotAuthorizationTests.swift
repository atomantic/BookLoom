import Foundation
import XCTest
@testable import BookLoom

final class MemberSnapshotAuthorizationTests: XCTestCase {
    func test_acceptsOwnerBoundSelfAttributedMemberSnapshot() {
        let batch = batch(
            ownerBindings: [binding("member-owner", "cloud-owner"), binding("member-sam", "cloud-sam")],
            additional: [envelope(memberSnapshot("member-sam"), creator: "cloud-sam")]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertEqual(result.snapshots.map(\.authorMemberID).sorted(), ["member-owner", "member-sam"])
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
        XCTAssertTrue(result.isTrustEstablished)
    }

    func test_rejectsForgedMemberAuthorshipEvenWhenAttackerIsBound() {
        let forged = MemberShareSnapshot(
            authorMemberID: "member-attacker",
            authorName: "Attacker",
            ratings: [
                .init(
                    submissionSelectionID: "selection-1",
                    memberID: "member-victim",
                    memberName: "Victim",
                    stars: 1,
                    createdAt: .now
                )
            ]
        )
        let batch = batch(
            ownerBindings: [binding("member-owner", "cloud-owner"), binding("member-attacker", "cloud-attacker")],
            additional: [envelope(forged, creator: "cloud-attacker")]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
        XCTAssertEqual(result.rejectedRecordNames, ["MemberSnapshot-member-attacker"])
    }

    func test_rejectsRecordOverwrittenByDifferentCloudKitUser() {
        let overwritten = envelope(
            memberSnapshot("member-sam"),
            creator: "cloud-sam",
            modifier: "cloud-attacker"
        )
        let batch = batch(
            ownerBindings: [binding("member-owner", "cloud-owner"), binding("member-sam", "cloud-sam")],
            additional: [overwritten]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
        XCTAssertEqual(result.rejectedRecordNames, ["MemberSnapshot-member-sam"])
    }

    func test_rejectsForgedOwnerMetadataAndUnauthorizedRemoval() {
        let forgedMeta = ownerMeta(
            creatorMemberID: "member-attacker",
            removedMemberIDs: ["member-owner"],
            bindings: [binding("member-attacker", "cloud-attacker")]
        )
        let attacker = MemberShareSnapshot(
            authorMemberID: "member-attacker",
            authorName: "Attacker",
            clubMeta: forgedMeta
        )
        let batch = batch(
            ownerBindings: [binding("member-owner", "cloud-owner"), binding("member-attacker", "cloud-attacker")],
            additional: [envelope(attacker, creator: "cloud-attacker")]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
        XCTAssertEqual(result.rejectedRecordNames, ["MemberSnapshot-member-attacker"])
    }

    func test_rejectsOverrideWhoseActorImpersonatesAdmin() {
        let forged = MemberShareSnapshot(
            authorMemberID: "member-sam",
            authorName: "Sam",
            detailsOverrides: [
                .init(
                    submissionSelectionID: "selection-1",
                    title: "Forged",
                    author: "",
                    isbn: "",
                    bookDescription: "",
                    publishedYear: nil,
                    coverURL: "",
                    externalProvider: "",
                    externalID: "",
                    updatedAt: .now,
                    actorMemberID: "member-admin"
                )
            ],
            deletedSubmissions: [
                .init(
                    submissionSelectionID: "selection-2",
                    deletedAt: .now,
                    actorMemberID: "member-admin"
                )
            ]
        )
        let batch = batch(
            ownerBindings: [
                binding("member-owner", "cloud-owner"),
                binding("member-admin", "cloud-admin"),
                binding("member-sam", "cloud-sam")
            ],
            admins: ["member-admin"],
            additional: [envelope(forged, creator: "cloud-sam")]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
        XCTAssertEqual(result.rejectedRecordNames, ["MemberSnapshot-member-sam"])
    }

    func test_ownerMigratesPristineLegacyMemberBinding() {
        let batch = batch(
            ownerBindings: nil,
            additional: [envelope(memberSnapshot("member-sam"), creator: "cloud-sam")]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: true)

        XCTAssertEqual(result.bindings, ["member-owner": "cloud-owner", "member-sam": "cloud-sam"])
        XCTAssertTrue(result.bindingsChanged)
        XCTAssertEqual(result.snapshots.map(\.authorMemberID).sorted(), ["member-owner", "member-sam"])
    }

    func test_nonAdminRenameProposalIsRejected() {
        let snapshot = MemberShareSnapshot(
            authorMemberID: "member-sam",
            authorName: "Sam",
            nameProposal: .init(name: "Takeover", updatedAt: .now, proposerMemberID: "member-sam")
        )
        let batch = batch(
            ownerBindings: [binding("member-owner", "cloud-owner"), binding("member-sam", "cloud-sam")],
            additional: [envelope(snapshot, creator: "cloud-sam")]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
    }

    func test_missingOwnerTrustRootFailsClosed() {
        let member = envelope(memberSnapshot("member-sam"), creator: "cloud-sam")
        let batch = MemberSnapshotBatch(ownerUserRecordName: "cloud-owner", snapshots: [member])

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertFalse(result.isTrustEstablished)
        XCTAssertTrue(result.snapshots.isEmpty)
        XCTAssertEqual(result.rejectedRecordNames, ["MemberSnapshot-member-sam"])
    }

    private func batch(
        ownerBindings: [MemberShareSnapshot.MemberIdentityBinding]?,
        admins: [String] = [],
        additional: [ProvenancedMemberSnapshot]
    ) -> MemberSnapshotBatch {
        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_000),
            authorMemberID: "member-owner",
            authorName: "Owner",
            clubMeta: ownerMeta(
                creatorMemberID: "member-owner",
                removedMemberIDs: [],
                admins: admins,
                bindings: ownerBindings
            )
        )
        return MemberSnapshotBatch(
            ownerUserRecordName: "cloud-owner",
            snapshots: [envelope(owner, creator: "cloud-owner")] + additional
        )
    }

    private func memberSnapshot(_ memberID: String) -> MemberShareSnapshot {
        MemberShareSnapshot(authorMemberID: memberID, authorName: memberID)
    }

    private func ownerMeta(
        creatorMemberID: String,
        removedMemberIDs: [String],
        admins: [String] = [],
        bindings: [MemberShareSnapshot.MemberIdentityBinding]?
    ) -> MemberShareSnapshot.ClubMeta {
        .init(
            name: "Sunday Pages",
            createdAt: Date(timeIntervalSince1970: 500),
            cloudZoneName: "BookClub-Test",
            shareParticipantCount: 2,
            creatorMemberID: creatorMemberID,
            adminMemberIDs: admins,
            removedMemberIDs: removedMemberIDs,
            memberIdentityBindings: bindings,
            inviteURLString: nil,
            nameUpdatedAt: nil
        )
    }

    private func binding(_ memberID: String, _ user: String) -> MemberShareSnapshot.MemberIdentityBinding {
        .init(memberID: memberID, cloudKitUserRecordName: user)
    }

    private func envelope(
        _ snapshot: MemberShareSnapshot,
        creator: String,
        modifier: String? = nil
    ) -> ProvenancedMemberSnapshot {
        ProvenancedMemberSnapshot(
            snapshot: snapshot,
            provenance: MemberSnapshotProvenance(
                recordName: "MemberSnapshot-\(snapshot.authorMemberID)",
                creatorUserRecordName: creator,
                lastModifiedUserRecordName: modifier ?? creator
            )
        )
    }
}

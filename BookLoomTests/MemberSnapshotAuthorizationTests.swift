import CloudKit
import Foundation
import XCTest
@testable import BookLoom

final class MemberSnapshotAuthorizationTests: XCTestCase {
    func test_normalizesCurrentUserAliasBeforeEstablishingOwnerTrust() {
        let owner = MemberShareSnapshot(
            authorMemberID: "member-owner",
            authorName: "Owner",
            clubMeta: ownerMeta(
                creatorMemberID: "member-owner",
                removedMemberIDs: [],
                bindings: [binding("member-owner", "cloud-owner")]
            )
        )
        let batch = MemberSnapshotBatch(
            ownerUserRecordName: CKCurrentUserDefaultName,
            currentUserRecordName: "cloud-owner",
            approvedParticipantUserRecordNames: [CKCurrentUserDefaultName],
            snapshots: [envelope(owner, creator: CKCurrentUserDefaultName)]
        )

        let result = MemberSnapshotAuthorization.authorize(
            batch,
            existingBindings: [:],
            isShareOwner: true
        )

        XCTAssertTrue(result.isTrustEstablished)
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
        XCTAssertEqual(result.bindings, ["member-owner": "cloud-owner"])
    }

    func test_normalizesCurrentParticipantAliasAgainstOwnerPublishedBinding() {
        let original = batch(
            ownerBindings: [
                binding("member-owner", "cloud-owner"),
                binding("member-sam", "cloud-sam")
            ],
            additional: [envelope(memberSnapshot("member-sam"), creator: CKCurrentUserDefaultName)]
        )
        let batch = MemberSnapshotBatch(
            ownerUserRecordName: original.ownerUserRecordName,
            currentUserRecordName: "cloud-sam",
            approvedParticipantUserRecordNames: ["cloud-owner", "cloud-sam"],
            snapshots: original.snapshots
        )

        let result = MemberSnapshotAuthorization.authorize(
            batch,
            existingBindings: [:],
            isShareOwner: false
        )

        XCTAssertTrue(result.isTrustEstablished)
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
        XCTAssertEqual(result.snapshots.map(\.authorMemberID).sorted(), ["member-owner", "member-sam"])
    }

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

    func test_rejectsSnapshotClaimingMemberIDBoundToDifferentCloudKitUser() {
        let forged = memberSnapshot("member-victim")
        let batch = batch(
            ownerBindings: [
                binding("member-owner", "cloud-owner"),
                binding("member-victim", "cloud-victim")
            ],
            additional: [envelope(forged, creator: "cloud-attacker")]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
        XCTAssertEqual(result.rejectedRecordNames, ["MemberSnapshot-member-victim"])
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

    func test_ownerMigratesApprovedLegacyAdminBinding() {
        let admin = MemberShareSnapshot(
            authorMemberID: "member-admin",
            authorName: "Admin",
            nameProposal: .init(
                name: "Admin Rename",
                updatedAt: .now,
                proposerMemberID: "member-admin"
            )
        )
        let batch = batch(
            ownerBindings: nil,
            admins: ["member-admin"],
            additional: [envelope(admin, creator: "cloud-admin")]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: true)

        XCTAssertEqual(result.bindings["member-admin"], "cloud-admin")
        XCTAssertEqual(result.snapshots.map(\.authorMemberID).sorted(), ["member-admin", "member-owner"])
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
    }

    func test_bindsEveryStructurallyValidOwnerDeviceSnapshot() {
        let secondOwnerDevice = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            authorMemberID: "member-owner-device-2",
            authorName: "Owner",
            clubMeta: ownerMeta(
                creatorMemberID: "member-owner",
                removedMemberIDs: [],
                bindings: nil
            )
        )
        let batch = batch(
            ownerBindings: nil,
            additional: [envelope(secondOwnerDevice, creator: "cloud-owner")]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertEqual(result.bindings["member-owner"], "cloud-owner")
        XCTAssertEqual(result.bindings["member-owner-device-2"], "cloud-owner")
        XCTAssertEqual(result.snapshots.map(\.authorMemberID).sorted(), ["member-owner", "member-owner-device-2"])
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
    }

    func test_ownerIgnoresLegacySnapshotFromUnapprovedCloudKitParticipant() {
        let candidate = envelope(memberSnapshot("member-sam"), creator: "cloud-sam")
        let original = batch(ownerBindings: nil, additional: [candidate])
        let unapproved = MemberSnapshotBatch(
            ownerUserRecordName: original.ownerUserRecordName,
            approvedParticipantUserRecordNames: ["cloud-owner"],
            snapshots: original.snapshots
        )

        let result = MemberSnapshotAuthorization.authorize(unapproved, existingBindings: [:], isShareOwner: true)

        XCTAssertNil(result.bindings["member-sam"])
        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
    }

    func test_participantRejectsUnboundSnapshotFromApprovedCloudKitParticipant() {
        let original = batch(
            ownerBindings: [binding("member-owner", "cloud-owner")],
            additional: [envelope(memberSnapshot("member-sam"), creator: "cloud-sam")]
        )

        let result = MemberSnapshotAuthorization.authorize(
            original,
            existingBindings: [:],
            isShareOwner: false
        )

        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
        XCTAssertEqual(result.rejectedRecordNames, ["MemberSnapshot-member-sam"])
    }

    func test_retiresBindingsForParticipantsWhoLeftTheShare() {
        let original = batch(
            ownerBindings: [binding("member-owner", "cloud-owner"), binding("member-sam", "cloud-sam")],
            additional: []
        )
        let afterLeave = MemberSnapshotBatch(
            ownerUserRecordName: original.ownerUserRecordName,
            approvedParticipantUserRecordNames: ["cloud-owner"],
            snapshots: original.snapshots
        )

        let result = MemberSnapshotAuthorization.authorize(
            afterLeave,
            existingBindings: ["member-owner": "cloud-owner", "member-sam": "cloud-sam"],
            isShareOwner: true
        )

        XCTAssertEqual(result.bindings, ["member-owner": "cloud-owner"])
        XCTAssertTrue(result.bindingsChanged)
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
    }

    func test_ownerReactivatesRemovedIdentityAfterAcceptedReinvite() {
        let bindings = [
            binding("member-owner", "cloud-owner"),
            binding("member-sam", "cloud-sam")
        ]
        let batch = batch(
            ownerBindings: bindings,
            removedMemberIDs: ["member-sam"],
            additional: [envelope(memberSnapshot("member-sam"), creator: "cloud-sam")]
        )

        let result = MemberSnapshotAuthorization.authorize(
            batch,
            existingBindings: ["member-owner": "cloud-owner", "member-sam": "cloud-sam"],
            isShareOwner: true
        )

        XCTAssertEqual(result.reactivatedMemberIDs, ["member-sam"])
        XCTAssertEqual(result.bindings["member-sam"], "cloud-sam")
        XCTAssertEqual(result.snapshots.map(\.authorMemberID).sorted(), ["member-owner", "member-sam"])
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
    }

    func test_differentAcceptedIdentityCannotClaimRetainedRemovalTombstone() {
        let batch = batch(
            ownerBindings: [
                binding("member-owner", "cloud-owner"),
                binding("member-sam", "cloud-sam")
            ],
            removedMemberIDs: ["member-sam"],
            additional: [envelope(memberSnapshot("member-sam"), creator: "cloud-other")]
        )

        let result = MemberSnapshotAuthorization.authorize(
            batch,
            existingBindings: ["member-owner": "cloud-owner", "member-sam": "cloud-sam"],
            isShareOwner: true
        )

        XCTAssertTrue(result.reactivatedMemberIDs.isEmpty)
        XCTAssertEqual(result.bindings["member-sam"], "cloud-sam")
        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
        XCTAssertTrue(result.rejectedRecordNames.isEmpty, "A removed identity remains inert")
    }

    func test_ownerRepairsLegacyReinviteOnlyFromSnapshotNewerThanRemoval() {
        let batch = batch(
            ownerBindings: [binding("member-owner", "cloud-owner")],
            removedMemberIDs: ["member-sam"],
            ownerModificationDate: Date(timeIntervalSince1970: 1_000),
            additional: [
                envelope(
                    memberSnapshot("member-sam"),
                    creator: "cloud-sam",
                    modificationDate: Date(timeIntervalSince1970: 2_000)
                )
            ]
        )

        let result = MemberSnapshotAuthorization.authorize(
            batch,
            existingBindings: ["member-owner": "cloud-owner"],
            isShareOwner: true
        )

        XCTAssertEqual(result.reactivatedMemberIDs, ["member-sam"])
        XCTAssertEqual(result.bindings["member-sam"], "cloud-sam")
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
    }

    func test_ownerRejectsStaleLegacyRecordLeftBehindBeforeReinvite() {
        let batch = batch(
            ownerBindings: [binding("member-owner", "cloud-owner")],
            removedMemberIDs: ["member-sam"],
            ownerModificationDate: Date(timeIntervalSince1970: 1_000),
            additional: [
                envelope(
                    memberSnapshot("member-sam"),
                    creator: "cloud-sam",
                    modificationDate: Date(timeIntervalSince1970: 900)
                )
            ]
        )

        let result = MemberSnapshotAuthorization.authorize(
            batch,
            existingBindings: ["member-owner": "cloud-owner"],
            isShareOwner: true
        )

        XCTAssertTrue(result.reactivatedMemberIDs.isEmpty)
        XCTAssertNil(result.bindings["member-sam"])
        XCTAssertTrue(result.rejectedRecordNames.isEmpty, "A stale pre-reinvite record remains inert")
    }

    func test_participantCannotRetireOwnerRemovalTombstone() {
        let batch = batch(
            ownerBindings: [
                binding("member-owner", "cloud-owner"),
                binding("member-sam", "cloud-sam")
            ],
            removedMemberIDs: ["member-sam"],
            additional: [envelope(memberSnapshot("member-sam"), creator: "cloud-sam")]
        )

        let result = MemberSnapshotAuthorization.authorize(
            batch,
            existingBindings: ["member-owner": "cloud-owner", "member-sam": "cloud-sam"],
            isShareOwner: false
        )

        XCTAssertTrue(result.reactivatedMemberIDs.isEmpty)
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
    }

    func test_ownerIgnoresRetainedSnapshotThatPredatesReinvite() {
        let batch = batch(
            ownerBindings: [
                binding("member-owner", "cloud-owner"),
                binding("member-sam", "cloud-sam")
            ],
            removedMemberIDs: ["member-sam"],
            ownerModificationDate: Date(timeIntervalSince1970: 1_000),
            additional: [
                envelope(
                    memberSnapshot("member-sam"),
                    creator: "cloud-sam",
                    modificationDate: Date(timeIntervalSince1970: 900)
                )
            ]
        )

        let result = MemberSnapshotAuthorization.authorize(
            batch,
            existingBindings: ["member-owner": "cloud-owner", "member-sam": "cloud-sam"],
            isShareOwner: true
        )

        XCTAssertTrue(result.reactivatedMemberIDs.isEmpty)
        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
        XCTAssertTrue(result.missingMemberIDs.isEmpty, "A removed generation is inert, not missing")
    }

    func test_ownerStripsFormerAdminRenameProposalDuringFreshReinvite() throws {
        let returning = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            authorMemberID: "member-sam",
            authorName: "Sam",
            nameProposal: .init(
                name: "Stale Admin Rename",
                updatedAt: Date(timeIntervalSince1970: 2_000),
                proposerMemberID: "member-sam"
            )
        )
        let batch = batch(
            ownerBindings: [
                binding("member-owner", "cloud-owner"),
                binding("member-sam", "cloud-sam")
            ],
            removedMemberIDs: ["member-sam"],
            ownerModificationDate: Date(timeIntervalSince1970: 1_000),
            additional: [
                envelope(
                    returning,
                    creator: "cloud-sam",
                    modificationDate: Date(timeIntervalSince1970: 2_000)
                )
            ]
        )

        let result = MemberSnapshotAuthorization.authorize(
            batch,
            existingBindings: ["member-owner": "cloud-owner", "member-sam": "cloud-sam"],
            isShareOwner: true
        )

        XCTAssertEqual(result.reactivatedMemberIDs, ["member-sam"])
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
        let accepted = try XCTUnwrap(result.snapshots.first { $0.authorMemberID == "member-sam" })
        XCTAssertNil(accepted.nameProposal)
    }

    func test_ownerReinviteOnNewDeviceStartsFreshMembershipGeneration() {
        let batch = batch(
            ownerBindings: [
                binding("member-owner", "cloud-owner"),
                binding("member-sam-phone", "cloud-sam"),
                binding("member-sam-mac", "cloud-sam")
            ],
            removedMemberIDs: ["member-sam-phone", "member-sam-mac"],
            additional: [envelope(memberSnapshot("member-sam-ipad"), creator: "cloud-sam")]
        )

        let result = MemberSnapshotAuthorization.authorize(
            batch,
            existingBindings: [
                "member-owner": "cloud-owner",
                "member-sam-phone": "cloud-sam",
                "member-sam-mac": "cloud-sam"
            ],
            isShareOwner: true
        )

        XCTAssertEqual(result.reactivatedMemberIDs, ["member-sam-phone", "member-sam-mac"])
        XCTAssertEqual(
            result.bindings,
            ["member-owner": "cloud-owner", "member-sam-ipad": "cloud-sam"]
        )
        XCTAssertEqual(result.snapshots.map(\.authorMemberID).sorted(), ["member-owner", "member-sam-ipad"])
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
    }

    func test_missingOwnerBoundMemberRecordPreservesAuthorWithoutRejectingBatch() {
        let original = batch(
            ownerBindings: [binding("member-owner", "cloud-owner"), binding("member-sam", "cloud-sam")],
            additional: []
        )
        let batch = MemberSnapshotBatch(
            ownerUserRecordName: original.ownerUserRecordName,
            approvedParticipantUserRecordNames: ["cloud-owner", "cloud-sam"],
            snapshots: original.snapshots
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
        XCTAssertEqual(result.missingMemberIDs, ["member-sam"])
        XCTAssertEqual(result.snapshots.map(\.authorMemberID), ["member-owner"])
    }

    func test_legacyOwnerMetadataUsesCapturedAtAsVersion() {
        let stale = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_000),
            authorMemberID: "member-owner",
            authorName: "Owner",
            clubMeta: ownerMeta(
                creatorMemberID: "member-owner",
                removedMemberIDs: [],
                bindings: [binding("member-owner", "cloud-owner"), binding("member-old", "cloud-old")]
            )
        )
        let fresh = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            authorMemberID: "member-owner",
            authorName: "Owner",
            clubMeta: ownerMeta(
                creatorMemberID: "member-owner",
                removedMemberIDs: [],
                bindings: [binding("member-owner", "cloud-owner"), binding("member-new", "cloud-new")]
            )
        )
        let batch = MemberSnapshotBatch(
            ownerUserRecordName: "cloud-owner",
            approvedParticipantUserRecordNames: ["cloud-owner", "cloud-new"],
            snapshots: [
                envelope(stale, creator: "cloud-owner"),
                envelope(fresh, creator: "cloud-owner"),
                envelope(memberSnapshot("member-new"), creator: "cloud-new")
            ]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertEqual(result.bindings, ["member-owner": "cloud-owner", "member-new": "cloud-new"])
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
    }

    func test_rejectsStableObjectIDClaimedByDifferentAuthors() {
        let ownerPoll = pollSnapshot(memberID: "member-owner", pollID: "poll-shared")
        let memberPoll = pollSnapshot(memberID: "member-sam", pollID: "poll-shared")
        let owner = MemberShareSnapshot(
            authorMemberID: "member-owner",
            authorName: "Owner",
            clubMeta: ownerMeta(
                creatorMemberID: "member-owner",
                removedMemberIDs: [],
                bindings: [binding("member-owner", "cloud-owner"), binding("member-sam", "cloud-sam")]
            ),
            polls: ownerPoll.polls
        )
        let batch = MemberSnapshotBatch(
            ownerUserRecordName: "cloud-owner",
            approvedParticipantUserRecordNames: ["cloud-owner", "cloud-sam"],
            snapshots: [envelope(owner, creator: "cloud-owner"), envelope(memberPoll, creator: "cloud-sam")]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertEqual(Set(result.rejectedRecordNames), ["MemberSnapshot-member-owner", "MemberSnapshot-member-sam"])
    }

    func test_nonAdminRenameProposalIsStrippedWithoutRejectingContributions() throws {
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

        XCTAssertEqual(result.snapshots.map(\.authorMemberID).sorted(), ["member-owner", "member-sam"])
        let accepted = try XCTUnwrap(result.snapshots.first { $0.authorMemberID == "member-sam" })
        XCTAssertNil(accepted.nameProposal)
        XCTAssertTrue(result.rejectedRecordNames.isEmpty)
    }

    func test_missingOwnerTrustRootFailsClosed() {
        let member = envelope(memberSnapshot("member-sam"), creator: "cloud-sam")
        let batch = MemberSnapshotBatch(
            ownerUserRecordName: "cloud-owner",
            approvedParticipantUserRecordNames: ["cloud-owner", "cloud-sam"],
            snapshots: [member]
        )

        let result = MemberSnapshotAuthorization.authorize(batch, existingBindings: [:], isShareOwner: false)

        XCTAssertFalse(result.isTrustEstablished)
        XCTAssertTrue(result.snapshots.isEmpty)
        XCTAssertEqual(result.rejectedRecordNames, ["MemberSnapshot-member-sam"])
    }

    func test_shareReacceptPreservesBindingsWhenOwnerTrustIsNotYetAvailable() {
        let member = envelope(memberSnapshot("member-sam"), creator: "cloud-sam")
        let batch = MemberSnapshotBatch(
            ownerUserRecordName: "cloud-owner",
            approvedParticipantUserRecordNames: ["cloud-owner", "cloud-sam"],
            snapshots: [member]
        )
        let authorization = MemberSnapshotAuthorization.authorize(
            batch,
            existingBindings: [:],
            isShareOwner: false
        )
        let existing = ["member-owner": "cloud-owner", "member-sam": "cloud-sam"]

        let resolved = ShareAcceptance.bindingsAfterAuthorization(
            existing: existing,
            authorization: authorization
        )

        XCTAssertEqual(resolved, existing)
    }

    private func batch(
        ownerBindings: [MemberShareSnapshot.MemberIdentityBinding]?,
        admins: [String] = [],
        removedMemberIDs: [String] = [],
        ownerModificationDate: Date? = nil,
        additional: [ProvenancedMemberSnapshot]
    ) -> MemberSnapshotBatch {
        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_000),
            authorMemberID: "member-owner",
            authorName: "Owner",
            clubMeta: ownerMeta(
                creatorMemberID: "member-owner",
                removedMemberIDs: removedMemberIDs,
                admins: admins,
                bindings: ownerBindings
            )
        )
        let ownerEnvelope = envelope(
            owner,
            creator: "cloud-owner",
            modificationDate: ownerModificationDate
        )
        return MemberSnapshotBatch(
            ownerUserRecordName: "cloud-owner",
            approvedParticipantUserRecordNames: Set(
                ([ownerEnvelope] + additional)
                    .compactMap(\.provenance.creatorUserRecordName)
            ),
            snapshots: [ownerEnvelope] + additional
        )
    }

    private func memberSnapshot(_ memberID: String) -> MemberShareSnapshot {
        MemberShareSnapshot(authorMemberID: memberID, authorName: memberID)
    }

    private func pollSnapshot(memberID: String, pollID: String) -> MemberShareSnapshot {
        MemberShareSnapshot(
            authorMemberID: memberID,
            authorName: memberID,
            polls: [
                .init(
                    pollID: pollID,
                    createdByMemberID: memberID,
                    title: "Next Book",
                    createdAt: .now,
                    closesAt: nil,
                    statusRaw: "open",
                    isAnonymousResults: false,
                    candidateIDsRaw: "",
                    winnerSubmissionID: ""
                )
            ]
        )
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
        modifier: String? = nil,
        modificationDate: Date? = nil
    ) -> ProvenancedMemberSnapshot {
        ProvenancedMemberSnapshot(
            snapshot: snapshot,
            provenance: MemberSnapshotProvenance(
                recordName: "MemberSnapshot-\(snapshot.authorMemberID)",
                creatorUserRecordName: creator,
                lastModifiedUserRecordName: modifier ?? creator,
                modificationDate: modificationDate
            )
        )
    }
}

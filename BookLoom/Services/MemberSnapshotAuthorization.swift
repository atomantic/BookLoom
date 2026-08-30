import CloudKit
import Foundation

struct MemberSnapshotProvenance: Equatable, Sendable {
    let recordName: String
    let creatorUserRecordName: String?
    let lastModifiedUserRecordName: String?
}

struct ProvenancedMemberSnapshot: Equatable, Sendable {
    let snapshot: MemberShareSnapshot
    let provenance: MemberSnapshotProvenance
}

struct MemberSnapshotBatch: Equatable, Sendable {
    let ownerUserRecordName: String
    /// Stable CloudKit identity for the account performing this fetch. System
    /// record metadata may use `CKCurrentUserDefaultName` for this identity,
    /// while CKShare participants and persisted bindings use its stable name.
    let currentUserRecordName: String?
    /// CloudKit identities the owner has explicitly admitted to the private
    /// share. An unbound snapshot can be enrolled only for one of these users.
    let approvedParticipantUserRecordNames: Set<String>
    let snapshots: [ProvenancedMemberSnapshot]

    init(
        ownerUserRecordName: String,
        currentUserRecordName: String? = nil,
        approvedParticipantUserRecordNames: Set<String>,
        snapshots: [ProvenancedMemberSnapshot]
    ) {
        self.ownerUserRecordName = ownerUserRecordName
        self.currentUserRecordName = currentUserRecordName
        self.approvedParticipantUserRecordNames = approvedParticipantUserRecordNames
        self.snapshots = snapshots
    }
}

struct MemberSnapshotAuthorizationResult: Equatable, Sendable {
    let snapshots: [MemberShareSnapshot]
    let bindings: [String: String]
    let rejectedRecordNames: [String]
    let bindingsChanged: Bool
    let isTrustEstablished: Bool
}

struct MemberSnapshotAuthorizationError: LocalizedError, Equatable, Sendable {
    let rejectedRecordNames: [String]

    var errorDescription: String? {
        if rejectedRecordNames.isEmpty {
            return "The shared club has no provenance-verified owner snapshot yet. No local data was changed."
        }
        return "The shared club contains unauthenticated member snapshots (\(rejectedRecordNames.joined(separator: ", "))). No local data was changed."
    }
}

enum MemberSnapshotAuthorization {
    private static let recordPrefix = "MemberSnapshot-"

    /// Authenticate CloudKit records before their decoded payloads reach the
    /// merge engine. The share owner signs the member-to-CloudKit-user mapping
    /// through ClubMeta; only the owner may extend that mapping during sync.
    static func authorize(
        _ batch: MemberSnapshotBatch,
        existingBindings: [String: String],
        isShareOwner: Bool
    ) -> MemberSnapshotAuthorizationResult {
        // CloudKit uses `CKCurrentUserDefaultName` in record system fields when
        // the creator/modifier is the account performing the fetch. CKShare
        // participant identities and our persisted binding map use the stable
        // user record name instead. Normalize that database-relative alias at
        // the trust boundary before making any provenance comparisons.
        let snapshots = normalizeCurrentUserAliases(
            batch.snapshots,
            currentUserRecordName: batch.currentUserRecordName
        )
        let ownerUserRecordName = normalizeCurrentUserAlias(
            batch.ownerUserRecordName,
            currentUserRecordName: batch.currentUserRecordName
        )
        let approvedParticipantUserRecordNames = Set(
            batch.approvedParticipantUserRecordNames.map {
                normalizeCurrentUserAlias(
                    $0,
                    currentUserRecordName: batch.currentUserRecordName
                )
            }
        )
        let structurallyValid = snapshots.filter(isStructurallyValid)
        let ownerEnvelope = structurallyValid
            .filter { envelope in
                envelope.provenance.creatorUserRecordName == ownerUserRecordName
                    && envelope.snapshot.clubMeta != nil
            }
            .max { metadataVersion($0.snapshot) < metadataVersion($1.snapshot) }

        guard let ownerEnvelope, let ownerMeta = ownerEnvelope.snapshot.clubMeta else {
            return MemberSnapshotAuthorizationResult(
                snapshots: [],
                bindings: isShareOwner ? existingBindings : [:],
                rejectedRecordNames: snapshots.map(\.provenance.recordName),
                bindingsChanged: false,
                isTrustEstablished: false
            )
        }

        let publishedBindings = bindingDictionary(ownerMeta.memberIdentityBindings ?? [])
        var bindings = isShareOwner ? existingBindings : publishedBindings
        if isShareOwner {
            for (memberID, userRecordName) in publishedBindings where bindings[memberID] == nil {
                bindings[memberID] = userRecordName
            }
        }

        // The provenance-verified owner snapshot bootstraps legacy shares that
        // predate the binding field. This never trusts a payload-only identity.
        let ownerMemberID = ownerEnvelope.snapshot.authorMemberID
        // CloudKit may represent the current database owner with its default
        // alias on the owner's device and with the stable user record name on
        // participants' devices. Normalize the owner binding to the trusted
        // CKShare owner identity visible to this fetch instead of persisting a
        // cross-database alias comparison.
        // One Apple ID can use BookLoom on multiple devices, each with its own
        // local member ID and owner-authored snapshot. Bind every structurally
        // valid record created by the CKShare owner, not only whichever owner
        // metadata envelope won the version comparison.
        for envelope in structurallyValid
        where envelope.provenance.creatorUserRecordName == ownerUserRecordName {
            bindings[envelope.snapshot.authorMemberID] = ownerUserRecordName
        }

        // A participant who has left (or was removed directly in the system
        // sharing UI) no longer has authority in this share. Retire all of that
        // CloudKit identity's member IDs before checking for missing records.
        // The owner binding remains anchored to the provenance-verified share
        // owner even if CloudKit omits the owner from the participant array.
        bindings = bindings.filter { memberID, userRecordName in
            memberID == ownerMemberID
                || userRecordName == ownerUserRecordName
                || approvedParticipantUserRecordNames.contains(userRecordName)
        }

        let creatorMemberID = ownerMeta.creatorMemberID?.trimmedOrNil ?? ownerMemberID
        let authorizedAdmins = Set(ownerMeta.adminMemberIDs ?? []).union([creatorMemberID])
        let removedMemberIDs = Set(ownerMeta.removedMemberIDs ?? [])
        let protectedMemberIDs = removedMemberIDs.union(bindings.keys)

        if isShareOwner {
            // The owner adding a specified CloudKit participant is the approval
            // handshake for that Apple ID. Only a pristine record from an
            // approved participant may introduce a fresh local member ID.
            // Existing and removed IDs can never be claimed; an admin ID from
            // legacy owner metadata is enrolled here because the trusted owner
            // both granted that role and admitted this CloudKit participant.
            for envelope in structurallyValid
            where envelope.provenance.creatorUserRecordName != ownerUserRecordName {
                let memberID = envelope.snapshot.authorMemberID
                guard bindings[memberID] == nil,
                      !protectedMemberIDs.contains(memberID),
                      envelope.provenance.creatorUserRecordName.map(approvedParticipantUserRecordNames.contains) == true,
                      isPayloadAuthorized(envelope.snapshot, authorizedAdmins: authorizedAdmins) else { continue }
                bindings[memberID] = envelope.provenance.creatorUserRecordName
            }
        }

        // Records left behind by users who are no longer share participants are
        // inert legacy data. Ignoring them lets public-share migration and the
        // normal Leave Club flow converge without weakening checks on records
        // written by identities that still have access.
        let activeEnvelopes = snapshots.filter { envelope in
            envelope.provenance.creatorUserRecordName == ownerUserRecordName
                || envelope.provenance.creatorUserRecordName
                    .map(approvedParticipantUserRecordNames.contains) == true
        }
        let activeStructurallyValid = activeEnvelopes.filter(isStructurallyValid)
        let presentMemberIDs = Set(activeStructurallyValid.map { $0.snapshot.authorMemberID })
        let missingBoundRecordNames = bindings.keys
            .filter { !removedMemberIDs.contains($0) && !presentMemberIDs.contains($0) }
            .map { recordPrefix + $0 }
        let collidingRecordNames = stableObjectOwnershipCollisions(in: activeStructurallyValid)

        var accepted: [MemberShareSnapshot] = []
        var rejected: [String] = []
        for envelope in activeEnvelopes {
            let snapshot = envelope.snapshot
            let creator = envelope.provenance.creatorUserRecordName
            let isBound = creator != nil && bindings[snapshot.authorMemberID] == creator
            let ownsMeta = snapshot.clubMeta == nil || creator == ownerUserRecordName
            if isStructurallyValid(envelope), isBound, ownsMeta,
               isPayloadAuthorized(snapshot, authorizedAdmins: authorizedAdmins) {
                accepted.append(snapshot)
            } else {
                rejected.append(envelope.provenance.recordName)
            }
        }
        rejected.append(contentsOf: missingBoundRecordNames)
        rejected.append(contentsOf: collidingRecordNames)
        rejected = Array(Set(rejected)).sorted()

        return MemberSnapshotAuthorizationResult(
            snapshots: accepted,
            bindings: bindings,
            rejectedRecordNames: rejected,
            bindingsChanged: bindings != existingBindings,
            isTrustEstablished: true
        )
    }

    private static func normalizeCurrentUserAliases(
        _ snapshots: [ProvenancedMemberSnapshot],
        currentUserRecordName: String?
    ) -> [ProvenancedMemberSnapshot] {
        guard let currentUserRecordName = currentUserRecordName?.trimmedOrNil,
              currentUserRecordName != CKCurrentUserDefaultName else {
            return snapshots
        }

        let normalize: (String?) -> String? = { recordName in
            recordName == CKCurrentUserDefaultName ? currentUserRecordName : recordName
        }
        return snapshots.map { envelope in
            ProvenancedMemberSnapshot(
                snapshot: envelope.snapshot,
                provenance: MemberSnapshotProvenance(
                    recordName: envelope.provenance.recordName,
                    creatorUserRecordName: normalize(envelope.provenance.creatorUserRecordName),
                    lastModifiedUserRecordName: normalize(envelope.provenance.lastModifiedUserRecordName)
                )
            )
        }
    }

    private static func normalizeCurrentUserAlias(
        _ recordName: String,
        currentUserRecordName: String?
    ) -> String {
        guard recordName == CKCurrentUserDefaultName,
              let currentUserRecordName = currentUserRecordName?.trimmedOrNil else {
            return recordName
        }
        return currentUserRecordName
    }

    private static func metadataVersion(_ snapshot: MemberShareSnapshot) -> Date {
        guard let meta = snapshot.clubMeta else { return .distantPast }
        return meta.metadataUpdatedAt ?? snapshot.capturedAt
    }

    /// A stable base-object ID belongs to exactly one authenticated snapshot
    /// author. References such as votes and RSVPs may target another member's
    /// object, but submissions, prompts, polls, and meetings may not redefine it.
    private static func stableObjectOwnershipCollisions(
        in envelopes: [ProvenancedMemberSnapshot]
    ) -> [String] {
        var owners: [String: (memberID: String, recordName: String)] = [:]
        var rejected = Set<String>()
        for envelope in envelopes {
            let memberID = envelope.snapshot.authorMemberID
            let recordName = envelope.provenance.recordName
            let keys = envelope.snapshot.submissions.map { "submission:\($0.selectionID)" }
                + envelope.snapshot.prompts.map { "prompt:\($0.promptID)" }
                + envelope.snapshot.polls.map { "poll:\($0.pollID)" }
                + envelope.snapshot.meetings.map { "meeting:\($0.meetingID)" }
            for key in keys where !key.hasSuffix(":") {
                if let prior = owners[key], prior.memberID != memberID {
                    rejected.insert(prior.recordName)
                    rejected.insert(recordName)
                } else {
                    owners[key] = (memberID, recordName)
                }
            }
        }
        return rejected.sorted()
    }

    private static func isStructurallyValid(_ envelope: ProvenancedMemberSnapshot) -> Bool {
        let provenance = envelope.provenance
        guard let creator = provenance.creatorUserRecordName,
              creator == provenance.lastModifiedUserRecordName,
              provenance.recordName == recordPrefix + envelope.snapshot.authorMemberID else {
            return false
        }
        return hasSelfAttributedPayload(envelope.snapshot)
    }

    private static func hasSelfAttributedPayload(_ snapshot: MemberShareSnapshot) -> Bool {
        let author = snapshot.authorMemberID
        guard !author.isEmpty else { return false }
        return snapshot.submissions.allSatisfy { $0.submittedByMemberID == author }
            && (snapshot.detailsOverrides ?? []).allSatisfy { $0.actorMemberID == author }
            && (snapshot.deletedSubmissions ?? []).allSatisfy { $0.actorMemberID == author }
            && snapshot.ratings.allSatisfy { $0.memberID == author }
            && snapshot.notes.allSatisfy { $0.memberID == author }
            && snapshot.prompts.allSatisfy { $0.createdByMemberID == author }
            && snapshot.polls.allSatisfy { $0.createdByMemberID == author }
            && snapshot.votes.allSatisfy { $0.memberID == author }
            && snapshot.meetings.allSatisfy { $0.hostMemberID == author }
            && snapshot.rsvps.allSatisfy { $0.memberID == author }
            && (snapshot.nameProposal == nil || snapshot.nameProposal?.proposerMemberID == author)
    }

    private static func isPayloadAuthorized(
        _ snapshot: MemberShareSnapshot,
        authorizedAdmins: Set<String>
    ) -> Bool {
        guard hasSelfAttributedPayload(snapshot) else { return false }
        if snapshot.nameProposal != nil && !authorizedAdmins.contains(snapshot.authorMemberID) {
            return false
        }
        return true
    }

    private static func bindingDictionary(
        _ bindings: [MemberShareSnapshot.MemberIdentityBinding]
    ) -> [String: String] {
        var result: [String: String] = [:]
        var conflicts = Set<String>()
        for binding in bindings where !binding.memberID.isEmpty && !binding.cloudKitUserRecordName.isEmpty {
            if let existing = result[binding.memberID], existing != binding.cloudKitUserRecordName {
                conflicts.insert(binding.memberID)
            } else {
                result[binding.memberID] = binding.cloudKitUserRecordName
            }
        }
        for memberID in conflicts { result.removeValue(forKey: memberID) }
        return result
    }
}

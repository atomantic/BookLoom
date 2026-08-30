import CloudKit
import Foundation

struct MemberSnapshotProvenance: Equatable, Sendable {
    let recordName: String
    let creatorUserRecordName: String?
    let lastModifiedUserRecordName: String?
    /// CloudKit's server-assigned modification time. This lets the owner
    /// distinguish a freshly republished snapshot after re-invitation from a
    /// legacy record that merely survived an earlier removal.
    let modificationDate: Date?

    init(
        recordName: String,
        creatorUserRecordName: String?,
        lastModifiedUserRecordName: String?,
        modificationDate: Date? = nil
    ) {
        self.recordName = recordName
        self.creatorUserRecordName = creatorUserRecordName
        self.lastModifiedUserRecordName = lastModifiedUserRecordName
        self.modificationDate = modificationDate
    }
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
    /// Owner-authorized removal tombstones that can be retired because the
    /// same CloudKit identity has explicitly rejoined the share. Empty on
    /// participant devices so only the share owner can reactivate membership.
    let reactivatedMemberIDs: Set<String>
    /// Authenticated members whose records are temporarily absent from this
    /// query result. The merge may import verified records that are present,
    /// but must preserve locally cached contributions from these authors until
    /// their snapshots return or the owner explicitly removes them.
    let missingMemberIDs: Set<String>
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
                reactivatedMemberIDs: [],
                missingMemberIDs: [],
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

        let creatorMemberID = ownerMeta.creatorMemberID?.trimmedOrNil ?? ownerMemberID
        let authorizedAdmins = Set(ownerMeta.adminMemberIDs ?? []).union([creatorMemberID])
        let removedMemberIDs = Set(ownerMeta.removedMemberIDs ?? [])

        // A participant who voluntarily left (or was removed directly in the
        // system sharing UI) no longer has authority in this share. Retire that
        // identity's active bindings. Deliberate in-app removals retain their
        // tombstone bindings, however, so a future accepted invitation can be
        // proven to belong to the same CloudKit identity and so every device ID
        // for that removed person remains suppressed in the meantime.
        // The owner binding remains anchored to the provenance-verified share
        // owner even if CloudKit omits the owner from the participant array.
        bindings = bindings.filter { memberID, userRecordName in
            removedMemberIDs.contains(memberID)
                || memberID == ownerMemberID
                || userRecordName == ownerUserRecordName
                || approvedParticipantUserRecordNames.contains(userRecordName)
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
        var reactivatedMemberIDs = Set<String>()
        var staleReinviteRecordNames = Set<String>()
        var freshGenerationMemberIDsByUser: [String: Set<String>] = [:]

        if isShareOwner {
            // The owner adding a specified CloudKit participant is the approval
            // handshake for that Apple ID. Only a pristine record from an
            // accepted participant may introduce a fresh local member ID. A
            // retained tombstone can be reactivated only by its original bound
            // CloudKit user. For build-63-and-earlier removals that discarded
            // that binding, an exact-ID recovery additionally requires a
            // server-dated record newer than the owner's removal metadata.
            for envelope in activeStructurallyValid
            where envelope.provenance.creatorUserRecordName != ownerUserRecordName {
                let memberID = envelope.snapshot.authorMemberID
                guard let creator = envelope.provenance.creatorUserRecordName,
                      approvedParticipantUserRecordNames.contains(creator),
                      envelope.snapshot.clubMeta == nil else { continue }

                let matchingTombstones = removedMemberIDs.filter { bindings[$0] == creator }
                let isLegacyRemovedID = removedMemberIDs.contains(memberID) && bindings[memberID] == nil
                if (!matchingTombstones.isEmpty || isLegacyRemovedID),
                   !isFreshReinvite(envelope, newerThan: ownerEnvelope) {
                    // Re-accepting a CKShare can expose a record that survived
                    // the previous removal. It is authenticated but belongs to
                    // the retired membership generation, so ignore it until
                    // that participant actually republishes after rejoining.
                    staleReinviteRecordNames.insert(envelope.provenance.recordName)
                    continue
                }

                if let boundCreator = bindings[memberID] {
                    guard boundCreator == creator else { continue }
                } else if removedMemberIDs.contains(memberID) {
                    bindings[memberID] = creator
                } else {
                    bindings[memberID] = creator
                }

                // A returning person may publish under the same device ID or a
                // new one. Clear every tombstone authenticated to that CloudKit
                // identity, but never restore their old admin designation.
                reactivatedMemberIDs.formUnion(matchingTombstones)
                if isLegacyRemovedID {
                    reactivatedMemberIDs.insert(memberID)
                }
                if !matchingTombstones.isEmpty || isLegacyRemovedID {
                    freshGenerationMemberIDsByUser[creator, default: []].insert(memberID)
                }
            }

            // Start a fresh membership generation for each reactivated person:
            // retain only device IDs whose records are present and valid now.
            // Otherwise clearing an old tombstone would immediately turn an
            // absent pre-removal device into a missing-bound-record failure.
            let reactivatedUsers = Set(reactivatedMemberIDs.compactMap { bindings[$0] })
            if !reactivatedUsers.isEmpty {
                bindings = bindings.filter { memberID, userRecordName in
                    !reactivatedUsers.contains(userRecordName)
                        || freshGenerationMemberIDsByUser[userRecordName]?.contains(memberID) == true
                }
            }
        }

        let effectiveRemovedMemberIDs = removedMemberIDs.subtracting(reactivatedMemberIDs)
        let eligibleEnvelopes = activeEnvelopes.filter { envelope in
            !effectiveRemovedMemberIDs.contains(envelope.snapshot.authorMemberID)
                && !staleReinviteRecordNames.contains(envelope.provenance.recordName)
        }
        let eligibleStructurallyValid = eligibleEnvelopes.filter(isStructurallyValid)
        let presentMemberIDs = Set(eligibleStructurallyValid.map { $0.snapshot.authorMemberID })
        let missingMemberIDs = Set(bindings.keys.filter {
            !effectiveRemovedMemberIDs.contains($0) && !presentMemberIDs.contains($0)
        })
        let collidingRecordNames = stableObjectOwnershipCollisions(in: eligibleStructurallyValid)

        var accepted: [MemberShareSnapshot] = []
        var rejected: [String] = []
        for envelope in eligibleEnvelopes {
            let snapshot = envelope.snapshot
            let creator = envelope.provenance.creatorUserRecordName
            let isBound = creator != nil && bindings[snapshot.authorMemberID] == creator
            let ownsMeta = snapshot.clubMeta == nil || creator == ownerUserRecordName
            if isStructurallyValid(envelope), isBound, ownsMeta,
               let authorizedSnapshot = authorizedSnapshot(
                   snapshot,
                   authorizedAdmins: authorizedAdmins
               ) {
                accepted.append(authorizedSnapshot)
            } else {
                rejected.append(envelope.provenance.recordName)
            }
        }
        rejected.append(contentsOf: collidingRecordNames)
        rejected = Array(Set(rejected)).sorted()

        return MemberSnapshotAuthorizationResult(
            snapshots: accepted,
            bindings: bindings,
            reactivatedMemberIDs: reactivatedMemberIDs,
            missingMemberIDs: missingMemberIDs,
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
                    lastModifiedUserRecordName: normalize(envelope.provenance.lastModifiedUserRecordName),
                    modificationDate: envelope.provenance.modificationDate
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

    /// Re-accepting a participant proves current share access, but an old record
    /// may have survived the prior removal. Require a server-side rewrite after
    /// the owner snapshot carrying the tombstone before treating that record as
    /// a new membership generation. This also authenticates exact-ID recovery
    /// for legacy removals that did not preserve an identity binding. CloudKit
    /// server dates avoid trusting device clock skew; capture times remain a
    /// compatibility fallback for old/test records without hydrated metadata.
    private static func isFreshReinvite(
        _ envelope: ProvenancedMemberSnapshot,
        newerThan ownerEnvelope: ProvenancedMemberSnapshot
    ) -> Bool {
        let candidateDate = envelope.provenance.modificationDate ?? envelope.snapshot.capturedAt
        let ownerDate = ownerEnvelope.provenance.modificationDate
            ?? metadataVersion(ownerEnvelope.snapshot)
        return candidateDate > ownerDate
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

    /// A non-admin can carry a stale rename proposal immediately after being
    /// removed and re-invited. The proposal is optional authority, not proof of
    /// the rest of the self-authored payload, so strip it while retaining the
    /// verified contributions. The merge engine independently checks proposer
    /// authority before applying any rename.
    private static func authorizedSnapshot(
        _ snapshot: MemberShareSnapshot,
        authorizedAdmins: Set<String>
    ) -> MemberShareSnapshot? {
        guard hasSelfAttributedPayload(snapshot) else { return nil }
        guard snapshot.nameProposal != nil,
              !authorizedAdmins.contains(snapshot.authorMemberID) else {
            return snapshot
        }
        return MemberShareSnapshot(
            schemaVersion: snapshot.schemaVersion,
            capturedAt: snapshot.capturedAt,
            authorMemberID: snapshot.authorMemberID,
            authorName: snapshot.authorName,
            clubMeta: snapshot.clubMeta,
            nameProposal: nil,
            submissions: snapshot.submissions,
            statusOverrides: snapshot.statusOverrides,
            detailsOverrides: snapshot.detailsOverrides ?? [],
            deletedSubmissions: snapshot.deletedSubmissions ?? [],
            ratings: snapshot.ratings,
            notes: snapshot.notes,
            prompts: snapshot.prompts,
            polls: snapshot.polls,
            votes: snapshot.votes,
            meetings: snapshot.meetings,
            rsvps: snapshot.rsvps
        )
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

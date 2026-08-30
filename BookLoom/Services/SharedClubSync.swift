import CloudKit
import Foundation
import Observation
import os
import SwiftData

/// Tracks the most recent CloudKit sync failure per club zone so the UI can
/// surface it to the user. CloudKit publish/fetch failures used to vanish into
/// `os_log` only.
@MainActor
@Observable
final class SharedClubSyncStatus {
    static let shared = SharedClubSyncStatus()

    // Private storage so callers go through `issue(for:)`. The `@Observable`
    // macro still tracks reads of this property made inside a view's `body`
    // (via `issue(for:)`), so updates drive view refreshes.
    private var issuesByZone: [String: SyncIssue] = [:]

    private init() {}

    // Guarded so a flapping network (which produces the same SyncIssue every
    // retry) doesn't republish and rerender observers on every cycle.
    func recordFailure(
        zoneName: String,
        operation: SyncOperation,
        error: Error,
        isShareOwner: Bool = false
    ) {
        let next = SyncIssue.classify(
            error,
            operation: operation,
            isShareOwner: isShareOwner
        )
        guard issuesByZone[zoneName] != next else { return }
        issuesByZone[zoneName] = next
    }

    // Guarded so a steady "no errors" state doesn't mutate observed storage on
    // every successful sync tick — clearFailure is called from each
    // publish/refresh success path.
    func clearFailure(zoneName: String) {
        guard issuesByZone[zoneName] != nil else { return }
        issuesByZone.removeValue(forKey: zoneName)
    }

    func issue(for club: BookClub) -> SyncIssue? {
        issuesByZone[club.cloudZoneName]
    }
}

enum SyncOperation {
    case publish
    case refresh
}

/// Coalesces refresh triggers while guaranteeing that only one refresh body
/// mutates local state at a time. A trigger received during an active refresh
/// schedules one follow-up pass with the newest operation.
@MainActor
final class CloudRefreshCoordinator {
    private var isRunning = false
    private var pending = false
    private var latestOperation: (@MainActor () async -> Void)?

    func request(_ operation: @escaping @MainActor () async -> Void) async {
        latestOperation = operation
        pending = true
        guard !isRunning else { return }

        isRunning = true
        defer {
            isRunning = false
            latestOperation = nil
        }
        repeat {
            pending = false
            guard let latestOperation else { return }
            await latestOperation()
        } while pending
    }
}

/// User-facing classification of a CloudKit sync failure. Hides raw CKError
/// codes and produces copy a non-developer can act on. Transient/network
/// failures render as a soft "offline" indicator rather than an alarming
/// error, since they self-resolve when connectivity returns.
struct SyncIssue: Equatable {
    enum Severity: Equatable {
        /// Transient, self-resolving (network, rate-limit, busy zone). Render
        /// as an unobtrusive offline banner.
        case offline
        /// Needs the user to do something (sign in, free up space, etc.).
        case warning
    }

    let severity: Severity
    let title: String
    let message: String
    let systemImage: String

    static func classify(
        _ error: Error,
        operation: SyncOperation,
        isShareOwner: Bool = false
    ) -> SyncIssue {
        if let direct = directIssue(from: error, isShareOwner: isShareOwner) {
            return direct
        }
        // CloudKit batch operations report the real cause inside partial
        // errors — a single network blip arrives wrapped in `partialFailure`,
        // and falling through would surface a generic warning instead of the
        // friendly offline banner.
        let ns = error as NSError
        if let partials = ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            for inner in partials.values {
                if let issue = directIssue(from: inner, isShareOwner: isShareOwner) {
                    return issue
                }
            }
        }
        return SyncIssue(
            severity: .warning,
            title: operation == .publish ? "Couldn't share latest changes" : "Couldn't fetch latest changes",
            message: "Sync will retry automatically. If this keeps happening, restart the app or check your iCloud connection.",
            systemImage: "exclamationmark.triangle.fill"
        )
    }

    private static func directIssue(from error: Error, isShareOwner: Bool) -> SyncIssue? {
        if let authorizationError = error as? MemberSnapshotAuthorizationError {
            if authorizationError.rejectedRecordNames.isEmpty {
                return SyncIssue(
                    severity: .offline,
                    title: "Waiting for Club data",
                    message: isShareOwner
                        ? "Your verified owner snapshot is still uploading. Keep BookLoom open and it will try again without changing your local data."
                        : "The Club owner's verified snapshot is not available yet. BookLoom will keep trying without changing your local data.",
                    systemImage: "icloud.and.arrow.down"
                )
            }
            return SyncIssue(
                severity: .warning,
                title: "Club data needs attention",
                message: isShareOwner
                    ? "BookLoom received shared changes it couldn't verify, so your local data was left untouched. Ask each current member to open the latest BookLoom, then try again."
                    : "BookLoom received shared changes it couldn't verify, so your local data was left untouched. Ask the Club owner to open the latest version of BookLoom.",
                systemImage: "checkmark.shield.fill"
            )
        }

        let ns = error as NSError

        if ns.domain == NSURLErrorDomain {
            return offline()
        }

        guard ns.domain == CKErrorDomain else { return nil }
        switch ns.code {
        case CKError.networkUnavailable.rawValue,
             CKError.networkFailure.rawValue:
            return offline()
        case CKError.serviceUnavailable.rawValue,
             CKError.requestRateLimited.rawValue,
             CKError.zoneBusy.rawValue:
            return SyncIssue(
                severity: .offline,
                title: "Sync paused",
                message: "iCloud is busy. Changes will sync automatically in a moment.",
                systemImage: "icloud"
            )
        case CKError.notAuthenticated.rawValue:
            return SyncIssue(
                severity: .warning,
                title: "Sign in to iCloud",
                message: "BookLoom needs an iCloud account to keep this club in sync. Open Settings → iCloud to sign in.",
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
        case CKError.accountTemporarilyUnavailable.rawValue:
            return SyncIssue(
                severity: .warning,
                title: "iCloud is unavailable",
                message: "Your iCloud account is temporarily unavailable. Try again after iCloud finishes signing in.",
                systemImage: "icloud.and.arrow.down"
            )
        case CKError.quotaExceeded.rawValue:
            return SyncIssue(
                severity: .warning,
                title: "iCloud storage is full",
                message: "Free up iCloud space to keep syncing this club.",
                systemImage: "externaldrive.fill.badge.exclamationmark"
            )
        default:
            return nil
        }
    }

    private static func offline() -> SyncIssue {
        SyncIssue(
            severity: .offline,
            title: "Working offline",
            message: "Your changes will sync when you reconnect.",
            systemImage: "icloud.slash"
        )
    }
}

@MainActor
extension ModelContext {
    /// Persist pending changes and, if the mutation belongs to an active shared
    /// club, publish the updated member snapshot to CloudKit. Collapses the
    /// `try save(); if let club { SharedClubSync.publishIfNeeded(...) }` pattern
    /// that recurred across the submission/poll/discussion editors.
    ///
    /// Throws if `save()` fails so the caller can surface the error rather than
    /// silently diverging from disk; the publish step is fire-and-forget and
    /// reports its own failures through `SharedClubSyncStatus`.
    func saveAndPublishIfNeeded(club: BookClub?, memberIdentity: MemberIdentity) throws {
        try save()
        if let club {
            SharedClubSync.publishIfNeeded(
                club,
                context: self,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
        }
    }
}

@MainActor
enum SharedClubSync {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "SharedClubSync")
    private struct PublishRequest {
        let club: BookClub
        let context: ModelContext
        let zoneName: String
        let clubName: String
        let target: MemberSnapshotSyncTarget
        let localMemberID: String
        let localMemberName: String
        let service: any MemberSnapshotSyncing
    }

    private static var queuedPublishes: [String: PublishRequest] = [:]
    private static var activePublishes: [String: Task<Bool, Never>] = [:]
    private static var activeRefreshes: [String: Task<Bool, Never>] = [:]

    /// Persist a context mutation made on the publish/refresh path, logging and
    /// recording a sync failure on error instead of swallowing it. These saves
    /// only carry bookkeeping (snapshot timestamps, participant counts, orphan
    /// deletes); a failure means in-memory state has diverged from disk, so we
    /// surface it via `SharedClubSyncStatus` rather than letting it vanish.
    @discardableResult
    private static func saveOrLog(_ context: ModelContext, club: BookClub, what: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            SharedClubSyncStatus.shared.recordFailure(
                zoneName: club.cloudZoneName,
                operation: .publish,
                error: error,
                isShareOwner: club.isShareOwner
            )
            logger.error("Failed to save \(what, privacy: .public) for shared club: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func saveAndPublish(
        context: ModelContext,
        club: BookClub,
        localMemberID: String,
        localMemberName: String
    ) throws {
        CoverDataCleanup.clearPersistedCoverData(in: club)
        try context.save()
        publishIfNeeded(club, context: context, localMemberID: localMemberID, localMemberName: localMemberName)
    }

    static func publishIfNeeded(
        _ club: BookClub,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String,
        service: any MemberSnapshotSyncing = CloudKitSharingService.shared,
        isEnabled: Bool = Features.cloudKitSharing
    ) {
        guard isEnabled, club.shareIsActive else { return }
        guard !localMemberID.isEmpty else {
            logger.error("Cannot publish snapshot for \(club.name, privacy: .private): localMemberID is empty")
            return
        }
        if CoverDataCleanup.clearPersistedCoverData(in: club) {
            saveOrLog(context, club: club, what: "cover-data cleanup")
        }
        let zoneName = club.cloudZoneName
        queuedPublishes[zoneName] = PublishRequest(
            club: club,
            context: context,
            zoneName: zoneName,
            clubName: club.name,
            target: MemberSnapshotSyncTarget(club),
            localMemberID: localMemberID,
            localMemberName: localMemberName,
            service: service
        )
        guard activePublishes[zoneName] == nil else { return }
        activePublishes[zoneName] = Task { @MainActor in
            await drainPublishes(for: zoneName)
        }
    }

    private static func drainPublishes(for zoneName: String) async -> Bool {
        var latestPublishSucceeded = true
        while let request = queuedPublishes.removeValue(forKey: zoneName) {
            latestPublishSucceeded = await publish(request)
        }
        activePublishes.removeValue(forKey: zoneName)
        return latestPublishSucceeded
    }

    private static func publish(_ request: PublishRequest) async -> Bool {
        let club = request.club
        guard club.modelContext != nil else {
            return false
        }
        do {
            if club.isShareOwner,
               let acceptedCount = try? await request.service.fetchAcceptedParticipantCount(target: request.target),
               club.modelContext != nil,
               acceptedCount != club.shareParticipantCount {
                club.shareParticipantCount = acceptedCount
                guard saveOrLog(request.context, club: club, what: "participant-count update") else {
                    return false
                }
            }
            guard club.modelContext != nil else {
                return false
            }
            let snapshot = MemberShareSnapshotStore.snapshot(
                from: club,
                context: request.context,
                authorMemberID: request.localMemberID,
                authorName: request.localMemberName,
                includeClubMeta: club.isShareOwner
            )
            try await request.service.publishMemberSnapshot(
                snapshot,
                target: request.target,
                localMemberID: request.localMemberID
            )
            guard club.modelContext != nil else {
                return false
            }
            // Record completion only after CloudKit accepted this serialized
            // publish; a stale/failed operation must not advance sync state.
            club.lastSharedSnapshotAt = snapshot.capturedAt
            guard saveOrLog(request.context, club: club, what: "snapshot timestamp") else { return false }
            SharedClubSyncStatus.shared.clearFailure(zoneName: request.zoneName)
            logger.info("Published member snapshot for \(request.clubName, privacy: .private) by \(request.localMemberName, privacy: .private)")
            return true
        } catch {
            let description = CloudKitErrorDescriber.describe(error)
            SharedClubSyncStatus.shared.recordFailure(
                zoneName: request.zoneName,
                operation: .publish,
                error: error,
                isShareOwner: club.isShareOwner
            )
            logger.error("Member snapshot publish failed: \(description, privacy: .public)")
            return false
        }
    }

    @discardableResult
    static func refreshIfNeeded(
        _ club: BookClub,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String,
        service: any MemberSnapshotSyncing = CloudKitSharingService.shared,
        isEnabled: Bool = Features.cloudKitSharing,
        removeUnavailableClub: Bool = true
    ) async -> Bool {
        guard isEnabled, club.shareIsActive else { return true }
        let zoneName = club.cloudZoneName
        if let activeRefresh = activeRefreshes[zoneName] {
            return await activeRefresh.value
        }
        let refresh = Task { @MainActor in
            await refreshBody(
                club,
                context: context,
                localMemberID: localMemberID,
                localMemberName: localMemberName,
                service: service,
                isEnabled: isEnabled,
                removeUnavailableClub: removeUnavailableClub
            )
        }
        activeRefreshes[zoneName] = refresh
        let result = await refresh.value
        activeRefreshes.removeValue(forKey: zoneName)
        return result
    }

    private static func refreshBody(
        _ club: BookClub,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String,
        service: any MemberSnapshotSyncing,
        isEnabled: Bool,
        removeUnavailableClub: Bool
    ) async -> Bool {
        guard isEnabled, club.shareIsActive else { return true }
        let target = MemberSnapshotSyncTarget(club)

        // Refreshes can arrive from the scene timer, a CloudKit push, or the
        // page task independently of `synchronizeIfNeeded`. Never let one of
        // those readers query while this zone's queued local snapshot is still
        // being written.
        guard await waitForPendingPublishes(zoneName: target.zoneName) else {
            // Keep the more useful publish failure visible. Fetching an older
            // owner snapshot after a failed write can otherwise manufacture a
            // secondary authorization warning from stale membership metadata.
            return true
        }

        let remoteBatch: MemberSnapshotBatch
        do {
            remoteBatch = try await service.fetchMemberSnapshotBatch(target: target)
        } catch {
            if CKZoneAvailability.classify(error) == .zoneRemoved {
                guard removeUnavailableClub, !club.shareAwaitingInitialSync else {
                    logger.info("Newly accepted shared zone for \(club.name, privacy: .private) is still materializing")
                    return true
                }
                // The owner has deleted the club, or we've been removed from
                // the share. Drop the orphan local row so the UI clears.
                let zoneName = club.cloudZoneName
                let clubName = club.name
                logger.info("Shared zone for \(clubName, privacy: .private) is gone — removing local club")
                SharedClubSyncStatus.shared.clearFailure(zoneName: zoneName)
                queuedPublishes.removeValue(forKey: zoneName)
                context.delete(club)
                saveOrLog(context, club: club, what: "orphan-club delete")
                return false
            } else {
                let description = CloudKitErrorDescriber.describe(error)
                SharedClubSyncStatus.shared.recordFailure(
                    zoneName: club.cloudZoneName,
                    operation: .refresh,
                    error: error,
                    isShareOwner: club.isShareOwner
                )
                logger.error("Member snapshot refresh failed: \(description, privacy: .public)")
            }
            return true
        }
        guard club.modelContext != nil else { return true }
        SharedClubSyncStatus.shared.clearFailure(zoneName: target.zoneName)
        if club.shareAwaitingInitialSync {
            club.shareAwaitingInitialSync = false
            guard saveOrLog(context, club: club, what: "share materialization") else { return false }
        }

        do {
            let authorization = MemberSnapshotAuthorization.authorize(
                remoteBatch,
                existingBindings: club.memberIdentityBindings,
                isShareOwner: club.isShareOwner
            )
            guard authorization.isTrustEstablished,
                  authorization.rejectedRecordNames.isEmpty else {
                let error = MemberSnapshotAuthorizationError(
                    rejectedRecordNames: authorization.rejectedRecordNames
                )
                SharedClubSyncStatus.shared.recordFailure(
                    zoneName: club.cloudZoneName,
                    operation: .refresh,
                    error: error,
                    isShareOwner: club.isShareOwner
                )
                logger.error("Snapshot authorization failed for \(club.name, privacy: .private): \(error.localizedDescription, privacy: .public)")
                return false
            }
            // Always include the local member's freshly-built snapshot in the
            // merge so locally-authored items survive the additive reconcile
            // even if they haven't reached CloudKit yet. Capture it before
            // advancing the binding clock: the merge must first reconcile any
            // newer owner metadata instead of publishing stale local metadata
            // with an artificially newer version.
            let localSnapshot = MemberShareSnapshotStore.snapshot(
                from: club,
                context: context,
                authorMemberID: localMemberID,
                authorName: localMemberName,
                includeClubMeta: club.isShareOwner
            )
            let bindingsChanged = club.memberIdentityBindings != authorization.bindings
            if bindingsChanged {
                // The merger uses this authenticated map to collapse multiple
                // per-device IDs belonging to one CloudKit participant.
                club.memberIdentityBindings = authorization.bindings
            }
            // Keep the authenticated remote snapshot for the local author in
            // the input as well. The local snapshot comes last and therefore
            // wins content upserts, while a newer remote owner metadata clock
            // can still reconcile canonical admin/removal/name state first.
            let merged = authorization.snapshots + [localSnapshot]
            try MemberShareSnapshotStore.merge(
                snapshots: merged,
                into: club,
                context: context,
                localMemberID: localMemberID,
                reactivatedMemberIDs: authorization.reactivatedMemberIDs,
                preservingMemberIDs: authorization.missingMemberIDs
            )
            let membershipMetadataChanged = bindingsChanged
                || !authorization.reactivatedMemberIDs.isEmpty
            if membershipMetadataChanged {
                if club.isShareOwner {
                    let now = Date.now
                    club.clubMetaUpdatedAt = now > club.clubMetaUpdatedAt
                        ? now
                        : club.clubMetaUpdatedAt.addingTimeInterval(0.001)
                }
            }
            if let acceptedCount = try? await service.fetchAcceptedParticipantCount(target: target),
               club.modelContext != nil,
               acceptedCount != club.shareParticipantCount {
                club.shareParticipantCount = acceptedCount
                saveOrLog(context, club: club, what: "participant-count update")
            }
            if membershipMetadataChanged {
                saveOrLog(context, club: club, what: "member identity membership")
                if club.isShareOwner {
                    publishIfNeeded(
                        club,
                        context: context,
                        localMemberID: localMemberID,
                        localMemberName: localMemberName,
                        service: service,
                        isEnabled: isEnabled
                    )
                }
            }
            logger.info("Merged \(authorization.snapshots.count) authenticated member snapshot(s) for \(club.name, privacy: .private)")
        } catch {
            // A merge failure now includes a failed local fetch/save (see
            // MemberShareSnapshotStore.merge). Surface it instead of silently
            // diverging — the merge aborted before any delete pass ran, so no
            // remote-authored rows were dropped on a corrupted local read.
            SharedClubSyncStatus.shared.recordFailure(
                zoneName: club.cloudZoneName,
                operation: .refresh,
                error: error,
                isShareOwner: club.isShareOwner
            )
            logger.error("Member snapshot merge failed: \(CloudKitErrorDescriber.describe(error), privacy: .public)")
        }
        return true
    }

    @discardableResult
    static func waitForPendingPublishes(zoneName: String) async -> Bool {
        await activePublishes[zoneName]?.value ?? true
    }

    static func refreshIfNeeded(
        _ clubs: [BookClub],
        context: ModelContext,
        localMemberID: String,
        localMemberName: String
    ) async {
        for club in clubs where club.shareIsActive {
            await refreshIfNeeded(club, context: context, localMemberID: localMemberID, localMemberName: localMemberName)
        }
    }

    static func synchronizeIfNeeded(
        _ club: BookClub,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String,
        service: any MemberSnapshotSyncing = CloudKitSharingService.shared,
        isEnabled: Bool = Features.cloudKitSharing
    ) async {
        guard isEnabled, club.shareIsActive else { return }
        // A page-level synchronize must not enqueue its write behind a refresh
        // that already started. Wait for that reader first, then publish and
        // fetch as one ordered sequence.
        if let activeRefresh = activeRefreshes[club.cloudZoneName] {
            _ = await activeRefresh.value
        }
        // Publish is queued on a per-zone task. Wait for that task before
        // fetching the zone: the first page appearance used to query while the
        // owner/member snapshot was still being written, which made a healthy
        // club intermittently surface a generic "Couldn't fetch" banner.
        publishIfNeeded(
            club,
            context: context,
            localMemberID: localMemberID,
            localMemberName: localMemberName,
            service: service,
            isEnabled: isEnabled
        )
        guard await waitForPendingPublishes(zoneName: club.cloudZoneName) else {
            return
        }
        await refreshIfNeeded(
            club,
            context: context,
            localMemberID: localMemberID,
            localMemberName: localMemberName,
            service: service,
            isEnabled: isEnabled
        )
    }

    static func synchronizeIfNeeded(
        _ clubs: [BookClub],
        context: ModelContext,
        localMemberID: String,
        localMemberName: String
    ) async {
        for club in clubs where club.shareIsActive {
            await synchronizeIfNeeded(club, context: context, localMemberID: localMemberID, localMemberName: localMemberName)
        }
    }

    static func synchronizeSharedClubs(
        in context: ModelContext,
        localMemberID: String,
        localMemberName: String
    ) async {
        do {
            let clubs = try context.fetch(FetchDescriptor<BookClub>())
            await synchronizeIfNeeded(clubs, context: context, localMemberID: localMemberID, localMemberName: localMemberName)
        } catch {
            logger.error("Failed to fetch shared clubs for synchronization: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func cleanupBeforeDeleteThrowing(_ target: ClubCleanupTarget, localMemberID: String) async throws {
        if Features.cloudKitSharing, target.shareIsActive {
            do {
                if target.isOwner {
                    try await CloudKitSharingService.shared.deleteSharedZone(zoneName: target.zoneName)
                } else {
                    try await CloudKitSharingService.shared.leaveShare(
                        zoneName: target.zoneName,
                        ownerUserRecordName: target.ownerUserRecordName,
                        localMemberID: localMemberID
                    )
                }
            } catch {
                guard CKZoneAvailability.confirmsRemoval(error) else { throw error }
                logger.info("CloudKit already confirms \(target.clubName, privacy: .private) is unavailable")
            }
        }

        // Clear local retry state only after CloudKit cleanup succeeded (or
        // confirmed the zone was already gone). A failed leave/delete keeps
        // the complete local club available for the user to retry.
        SharedClubSyncStatus.shared.clearFailure(zoneName: target.zoneName)
        StatusOverrideStore.clear(forZone: target.zoneName)
        SubmissionDetailsOverrideStore.clear(forZone: target.zoneName)
        SubmissionDeletionStore.clear(forZone: target.zoneName)
        queuedPublishes.removeValue(forKey: target.zoneName)
    }
}

struct ClubCleanupTarget: Codable, Equatable, Sendable {
    let zoneName: String
    let clubName: String
    let ownerUserRecordName: String?
    let shareIsActive: Bool

    var isOwner: Bool { ownerUserRecordName == nil }

    @MainActor
    init(_ club: BookClub) {
        zoneName = club.cloudZoneName
        clubName = club.name
        ownerUserRecordName = club.ownerUserRecordName
        shareIsActive = club.shareIsActive
    }
}

@MainActor
struct ClubAdminSideEffects {
    let cleanupClub: @MainActor (ClubCleanupTarget, String) async throws -> Void
    let revokeMember: @MainActor (BookClub, Set<String>) async throws -> Void

    static let production = ClubAdminSideEffects(
        cleanupClub: { target, memberID in
            try await SharedClubSync.cleanupBeforeDeleteThrowing(target, localMemberID: memberID)
        },
        revokeMember: { club, memberIDs in
            try await CloudKitSharingService.shared.removeMemberSnapshots(for: club, memberIDs: memberIDs)
        }
    )
}

/// Orchestrates the multi-step club-administration workflows that previously
/// lived inline in `ClubManagementView` (delete/leave, remove member, toggle
/// admin, creator backfill). Each method chains a local SwiftData mutation with
/// the matching CloudKit + sync calls and surfaces failures to the caller
/// instead of swallowing them, so the view can alert on a failed save rather
/// than dismissing over a club that's still in the store.
@MainActor
enum ClubAdminService {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "ClubAdminService")

    /// Delete (owner) or leave (participant) a club only after CloudKit has
    /// confirmed the destructive operation. A remote failure preserves the
    /// complete local row and throws so the UI can offer a safe retry.
    static func deleteClub(
        _ club: BookClub,
        context: ModelContext,
        localMemberID: String,
        activeClubStore: ActiveClubStore,
        sideEffects: ClubAdminSideEffects = .production
    ) async throws {
        let zoneName = club.cloudZoneName
        let isActive = zoneName == activeClubStore.activeClubZoneName
        try await sideEffects.cleanupClub(ClubCleanupTarget(club), localMemberID)
        context.delete(club)
        try context.save()
        if isActive {
            activeClubStore.clearActiveClub()
        }
    }

    /// Owner-only: revoke the participant's CloudKit access first, then commit
    /// the local removal tombstones for every device ID bound to that person.
    static func removeMember(
        _ memberID: String,
        from club: BookClub,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String,
        sideEffects: ClubAdminSideEffects = .production
    ) async throws {
        let relatedMemberIDs = club.relatedMemberIDs(to: memberID)
        guard club.isOwner,
              !memberID.isEmpty,
              !relatedMemberIDs.contains(club.creatorMemberID) else { return }
        if club.shareIsActive {
            try await sideEffects.revokeMember(club, relatedMemberIDs)
        }
        club.removeMembers(memberIDs: relatedMemberIDs)
        club.clubMetaUpdatedAt = .now
        try SharedClubSync.saveAndPublish(
            context: context,
            club: club,
            localMemberID: localMemberID,
            localMemberName: localMemberName
        )
        // With the revoked snapshots gone, reconcile immediately so the
        // removed person's activity rows clear from the owner's current UI.
        // Transient refresh failures remain visible through sync status and
        // retry automatically; membership itself is already safely revoked.
        _ = await SharedClubSync.refreshIfNeeded(
            club,
            context: context,
            localMemberID: localMemberID,
            localMemberName: localMemberName
        )
    }

    /// Owner-only: grant/revoke admin status for a member and publish the
    /// updated `ClubMeta`.
    static func setAdmin(
        _ isAdmin: Bool,
        memberID: String,
        in club: BookClub,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String
    ) throws {
        guard club.isOwner else { return }
        for relatedMemberID in club.relatedMemberIDs(to: memberID) {
            club.setAdmin(isAdmin, memberID: relatedMemberID)
        }
        club.clubMetaUpdatedAt = .now
        try SharedClubSync.saveAndPublish(
            context: context,
            club: club,
            localMemberID: localMemberID,
            localMemberName: localMemberName
        )
    }

    /// Rename the club (admin-only) and publish. Returns `true` if a rename was
    /// applied, `false` if the inputs were a no-op or the caller lacks rights.
    static func rename(
        _ club: BookClub,
        to proposedName: String,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String
    ) throws -> Bool {
        guard club.isAdmin(memberID: localMemberID),
              let trimmed = proposedName.trimmedOrNil,
              trimmed != club.name else { return false }
        club.name = trimmed
        club.nameUpdatedAt = .now
        if club.isOwner { club.clubMetaUpdatedAt = club.nameUpdatedAt }
        try SharedClubSync.saveAndPublish(
            context: context,
            club: club,
            localMemberID: localMemberID,
            localMemberName: localMemberName
        )
        return true
    }

    /// Backfill the creator on legacy clubs where the field was never set. Safe
    /// because only the local CKShare owner can have created the club. Logs on
    /// save failure rather than throwing — it runs from `.task` and a miss just
    /// retries on next open.
    static func backfillCreatorIfNeeded(_ club: BookClub, context: ModelContext, localMemberID: String) {
        guard club.creatorMemberID.isEmpty,
              club.isOwner,
              !localMemberID.isEmpty
        else { return }
        club.creatorMemberID = localMemberID
        club.clubMetaUpdatedAt = .now
        do {
            try context.save()
        } catch {
            logger.error("Failed to backfill creator: \(error.localizedDescription, privacy: .public)")
        }
    }
}

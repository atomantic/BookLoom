import CloudKit
import Foundation
import os
import SwiftData

/// Tracks the most recent CloudKit sync failure per club zone so the UI can
/// surface it to the user. CloudKit publish/fetch failures used to vanish into
/// `os_log` only.
@MainActor
final class SharedClubSyncStatus: ObservableObject {
    static let shared = SharedClubSyncStatus()

    // Private storage so callers go through `issue(for:)`. `@Published` still
    // drives view updates via ObservableObject conformance.
    @Published private var issuesByZone: [String: SyncIssue] = [:]

    private init() {}

    // Guarded so a flapping network (which produces the same SyncIssue every
    // retry) doesn't republish and rerender observers on every cycle.
    func recordFailure(zoneName: String, operation: SyncOperation, error: Error) {
        let next = SyncIssue.classify(error, operation: operation)
        guard issuesByZone[zoneName] != next else { return }
        issuesByZone[zoneName] = next
    }

    // Guarded so a steady "no errors" state doesn't fire @Published on every
    // successful sync tick — clearFailure is called from each publish/refresh
    // success path.
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

    static func classify(_ error: Error, operation: SyncOperation) -> SyncIssue {
        if let direct = directIssue(from: error) {
            return direct
        }
        // CloudKit batch operations report the real cause inside partial
        // errors — a single network blip arrives wrapped in `partialFailure`,
        // and falling through would surface a generic warning instead of the
        // friendly offline banner.
        let ns = error as NSError
        if let partials = ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            for inner in partials.values {
                if let issue = directIssue(from: inner) {
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

    private static func directIssue(from error: Error) -> SyncIssue? {
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
enum SharedClubSync {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "SharedClubSync")

    /// Persist a context mutation made on the publish/refresh path, logging and
    /// recording a sync failure on error instead of swallowing it. These saves
    /// only carry bookkeeping (snapshot timestamps, participant counts, orphan
    /// deletes); a failure means in-memory state has diverged from disk, so we
    /// surface it via `SharedClubSyncStatus` rather than letting it vanish.
    private static func saveOrLog(_ context: ModelContext, club: BookClub, what: String) {
        do {
            try context.save()
        } catch {
            SharedClubSyncStatus.shared.recordFailure(zoneName: club.cloudZoneName, operation: .publish, error: error)
            logger.error("Failed to save \(what, privacy: .public) for shared club: \(error.localizedDescription, privacy: .public)")
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
        localMemberName: String
    ) {
        guard Features.cloudKitSharing, club.shareIsActive else { return }
        guard !localMemberID.isEmpty else {
            logger.error("Cannot publish snapshot for \(club.name, privacy: .private): localMemberID is empty")
            return
        }
        if CoverDataCleanup.clearPersistedCoverData(in: club) {
            saveOrLog(context, club: club, what: "cover-data cleanup")
        }
        Task { @MainActor in
            do {
                if club.isShareOwner,
                   let acceptedCount = try? await CloudKitSharingService.shared.fetchAcceptedParticipantCount(for: club),
                   acceptedCount != club.shareParticipantCount {
                    club.shareParticipantCount = acceptedCount
                    saveOrLog(context, club: club, what: "participant-count update")
                }
                let snapshot = MemberShareSnapshotStore.snapshot(
                    from: club,
                    context: context,
                    authorMemberID: localMemberID,
                    authorName: localMemberName,
                    includeClubMeta: club.isShareOwner
                )
                club.lastSharedSnapshotAt = snapshot.capturedAt
                saveOrLog(context, club: club, what: "snapshot timestamp")
                try await CloudKitSharingService.shared.publishMemberSnapshot(snapshot, for: club, localMemberID: localMemberID)
                SharedClubSyncStatus.shared.clearFailure(zoneName: club.cloudZoneName)
                logger.info("Published member snapshot for \(club.name, privacy: .private) by \(localMemberName, privacy: .private)")
            } catch {
                let description = CloudKitErrorDescriber.describe(error)
                SharedClubSyncStatus.shared.recordFailure(zoneName: club.cloudZoneName, operation: .publish, error: error)
                logger.error("Member snapshot publish failed: \(description, privacy: .public)")
            }
        }
    }

    static func refreshIfNeeded(
        _ club: BookClub,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String
    ) async {
        guard Features.cloudKitSharing, club.shareIsActive else { return }

        let remoteSnapshots: [MemberShareSnapshot]
        do {
            remoteSnapshots = try await CloudKitSharingService.shared.fetchMemberSnapshots(for: club)
        } catch {
            if CKZoneAvailability.classify(error) == .zoneRemoved {
                // The owner has deleted the club, or we've been removed from
                // the share. Drop the orphan local row so the UI clears.
                logger.info("Shared zone for \(club.name, privacy: .private) is gone — removing local club")
                SharedClubSyncStatus.shared.clearFailure(zoneName: club.cloudZoneName)
                context.delete(club)
                saveOrLog(context, club: club, what: "orphan-club delete")
            } else {
                let description = CloudKitErrorDescriber.describe(error)
                SharedClubSyncStatus.shared.recordFailure(zoneName: club.cloudZoneName, operation: .refresh, error: error)
                logger.error("Member snapshot refresh failed: \(description, privacy: .public)")
            }
            return
        }
        SharedClubSyncStatus.shared.clearFailure(zoneName: club.cloudZoneName)

        do {
            // Always include the local member's freshly-built snapshot in the
            // merge so locally-authored items survive the additive reconcile
            // even if they haven't reached CloudKit yet.
            let localSnapshot = MemberShareSnapshotStore.snapshot(
                from: club,
                context: context,
                authorMemberID: localMemberID,
                authorName: localMemberName,
                includeClubMeta: club.isShareOwner
            )
            let merged = remoteSnapshots.filter { $0.authorMemberID != localMemberID } + [localSnapshot]
            try MemberShareSnapshotStore.merge(
                snapshots: merged,
                into: club,
                context: context,
                localMemberID: localMemberID
            )
            if let acceptedCount = try? await CloudKitSharingService.shared.fetchAcceptedParticipantCount(for: club),
               acceptedCount != club.shareParticipantCount {
                club.shareParticipantCount = acceptedCount
                saveOrLog(context, club: club, what: "participant-count update")
            }
            logger.info("Merged \(remoteSnapshots.count) member snapshot(s) for \(club.name, privacy: .private)")
        } catch {
            // A merge failure now includes a failed local fetch/save (see
            // MemberShareSnapshotStore.merge). Surface it instead of silently
            // diverging — the merge aborted before any delete pass ran, so no
            // remote-authored rows were dropped on a corrupted local read.
            SharedClubSyncStatus.shared.recordFailure(zoneName: club.cloudZoneName, operation: .refresh, error: error)
            logger.error("Member snapshot merge failed: \(CloudKitErrorDescriber.describe(error), privacy: .public)")
        }
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
        localMemberName: String
    ) async {
        guard Features.cloudKitSharing, club.shareIsActive else { return }
        // Publish kicks off its own Task internally, so it returns immediately
        // and runs concurrently with the refresh fetch+merge.
        publishIfNeeded(club, context: context, localMemberID: localMemberID, localMemberName: localMemberName)
        await refreshIfNeeded(club, context: context, localMemberID: localMemberID, localMemberName: localMemberName)
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

    /// Best-effort CloudKit cleanup before a local club row is deleted. The
    /// caller still removes the SwiftData row regardless of outcome — the
    /// user has asked for it to go away, and the most common failure mode
    /// here is "zone already deleted" which is the desired end state anyway.
    static func cleanupBeforeDelete(_ club: BookClub, localMemberID: String) async {
        let zoneName = club.cloudZoneName
        SharedClubSyncStatus.shared.clearFailure(zoneName: zoneName)
        StatusOverrideStore.clear(forZone: zoneName)
        SubmissionDetailsOverrideStore.clear(forZone: zoneName)
        SubmissionDeletionStore.clear(forZone: zoneName)

        guard Features.cloudKitSharing, club.shareIsActive else { return }
        do {
            if club.isOwner {
                try await CloudKitSharingService.shared.deleteSharedZone(for: club)
            } else {
                try await CloudKitSharingService.shared.leaveShare(
                    for: club,
                    localMemberID: localMemberID
                )
            }
        } catch {
            logger.error("CloudKit cleanup for \(club.name, privacy: .private) failed (continuing with local delete): \(CloudKitErrorDescriber.describe(error), privacy: .public)")
        }
    }
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

    /// Delete (owner) or leave (participant) a club: best-effort CloudKit
    /// cleanup, then remove the local row. Throws if the local delete fails to
    /// persist so the caller can keep the UI in place and alert.
    static func deleteClub(
        _ club: BookClub,
        context: ModelContext,
        localMemberID: String,
        activeClubStore: ActiveClubStore
    ) async throws {
        let zoneName = club.cloudZoneName
        let isActive = zoneName == activeClubStore.activeClubZoneName
        await SharedClubSync.cleanupBeforeDelete(club, localMemberID: localMemberID)
        context.delete(club)
        try context.save()
        if isActive {
            activeClubStore.clearActiveClub()
        }
    }

    /// Owner-only: mark a member removed locally, publish, then delete their
    /// CloudKit snapshot and refresh so the next merge doesn't re-import them.
    static func removeMember(
        _ memberID: String,
        from club: BookClub,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String
    ) throws {
        guard !memberID.isEmpty, memberID != club.creatorMemberID else { return }
        club.removeMember(memberID: memberID)
        try SharedClubSync.saveAndPublish(
            context: context,
            club: club,
            localMemberID: localMemberID,
            localMemberName: localMemberName
        )
        guard Features.cloudKitSharing, club.shareIsActive else { return }
        // The refresh waits for the CloudKit deletion so the next merge doesn't
        // re-import the just-removed snapshot.
        Task { @MainActor in
            try? await CloudKitSharingService.shared.removeMemberSnapshot(for: club, memberID: memberID)
            await SharedClubSync.refreshIfNeeded(
                club,
                context: context,
                localMemberID: localMemberID,
                localMemberName: localMemberName
            )
        }
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
        club.setAdmin(isAdmin, memberID: memberID)
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
        do {
            try context.save()
        } catch {
            logger.error("Failed to backfill creator: \(error.localizedDescription, privacy: .public)")
        }
    }
}

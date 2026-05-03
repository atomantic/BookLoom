import CloudKit
import Foundation
import os
import SwiftData

@MainActor
enum SharedClubSync {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "SharedClubSync")

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
            logger.error("Cannot publish snapshot for \(club.name, privacy: .public): localMemberID is empty")
            return
        }
        if CoverDataCleanup.clearPersistedCoverData(in: club) {
            try? context.save()
        }
        Task { @MainActor in
            do {
                if club.isOwner,
                   let acceptedCount = try? await CloudKitSharingService.shared.fetchAcceptedParticipantCount(for: club),
                   acceptedCount != club.shareParticipantCount {
                    club.shareParticipantCount = acceptedCount
                    try? context.save()
                }
                let snapshot = MemberShareSnapshotStore.snapshot(
                    from: club,
                    context: context,
                    authorMemberID: localMemberID,
                    authorName: localMemberName,
                    includeClubMeta: club.isOwner
                )
                club.lastSharedSnapshotAt = snapshot.capturedAt
                try? context.save()
                try await CloudKitSharingService.shared.publishMemberSnapshot(snapshot, for: club, localMemberID: localMemberID)
                logger.info("Published member snapshot for \(club.name, privacy: .public) by \(localMemberName, privacy: .public)")
            } catch {
                logger.error("Member snapshot publish failed: \(CloudKitErrorDescriber.describe(error), privacy: .public)")
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
                logger.info("Shared zone for \(club.name, privacy: .public) is gone — removing local club")
                context.delete(club)
                try? context.save()
            } else {
                logger.error("Member snapshot refresh failed: \(CloudKitErrorDescriber.describe(error), privacy: .public)")
            }
            return
        }

        do {
            // Always include the local member's freshly-built snapshot in the
            // merge so locally-authored items survive the additive reconcile
            // even if they haven't reached CloudKit yet.
            let localSnapshot = MemberShareSnapshotStore.snapshot(
                from: club,
                context: context,
                authorMemberID: localMemberID,
                authorName: localMemberName,
                includeClubMeta: club.isOwner
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
                try? context.save()
            }
            logger.info("Merged \(remoteSnapshots.count) member snapshot(s) for \(club.name, privacy: .public)")
        } catch {
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
            logger.error("CloudKit cleanup for \(club.name, privacy: .public) failed (continuing with local delete): \(CloudKitErrorDescriber.describe(error), privacy: .public)")
        }
    }
}

import CloudKit
import Foundation
import os
import SwiftData

@MainActor
enum SharedClubSync {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "SharedClubSync")

    static func saveAndPublish(context: ModelContext, club: BookClub) throws {
        CoverDataCleanup.clearPersistedCoverData(in: club)
        try context.save()
        publishIfNeeded(club, context: context)
    }

    static func publishIfNeeded(_ club: BookClub, context: ModelContext) {
        guard Features.cloudKitSharing, club.shareIsActive else { return }
        if CoverDataCleanup.clearPersistedCoverData(in: club) {
            try? context.save()
        }
        let snapshot = SharedClubSnapshotStore.snapshot(from: club, context: context)
        club.lastSharedSnapshotAt = snapshot.capturedAt
        try? context.save()

        Task { @MainActor in
            do {
                try await CloudKitSharingService.shared.publishSnapshot(snapshot, for: club)
                logger.info("Published shared snapshot for \(club.name, privacy: .public)")
            } catch {
                logger.error("Shared snapshot publish failed: \(CloudKitErrorDescriber.describe(error), privacy: .public)")
            }
        }
    }

    static func refreshIfNeeded(_ club: BookClub, context: ModelContext) async {
        guard Features.cloudKitSharing, club.shareIsActive else { return }
        if club.isOwner {
            publishIfNeeded(club, context: context)
            return
        }

        do {
            guard let snapshot = try await CloudKitSharingService.shared.fetchSnapshot(for: club) else {
                return
            }
            try SharedClubSnapshotStore.apply(snapshot, to: club, context: context)
            logger.info("Imported shared snapshot for \(club.name, privacy: .public)")
        } catch {
            logger.error("Shared snapshot refresh failed: \(CloudKitErrorDescriber.describe(error), privacy: .public)")
        }
    }

    static func refreshIfNeeded(_ clubs: [BookClub], context: ModelContext) async {
        for club in clubs where club.shareIsActive {
            await refreshIfNeeded(club, context: context)
        }
    }
}

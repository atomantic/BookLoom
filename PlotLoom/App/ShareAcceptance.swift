import Foundation
import CloudKit
import SwiftData
import SwiftUI
import os

/// Magic strings used when iOS/macOS deliver a CKShare invite via NSUserActivity.
/// These constants are NOT exposed by Apple's SDK — older sample code references
/// `CKShare.Metadata.activityType` which doesn't exist. Hardcode them.
enum ShareAcceptance {
    static let activityType = "com.apple.CloudKit.ShareMetadata"
    static let metadataKey = "CKShareMetadata"

    private static let logger = Logger(subsystem: "net.shadowpuppet.PlotLoom", category: "ShareAccept")

    /// Extract metadata from a `NSUserActivity` payload (used by SwiftUI's
    /// `onContinueUserActivity` modifier).
    static func metadata(from activity: NSUserActivity) -> CKShare.Metadata? {
        activity.userInfo?[metadataKey] as? CKShare.Metadata
    }

    /// Accept an incoming CKShare and insert a local `BookClub` row that
    /// represents the joined club. Idempotent — re-accepting the same share
    /// for an already-joined club won't duplicate the row.
    @MainActor
    static func handleAccept(metadata: CKShare.Metadata, context: ModelContext) async {
        guard Features.cloudKitSharing else {
            logger.info("⏭ Share accept ignored — Features.cloudKitSharing is off")
            return
        }
        do {
            let info = try await CloudKitSharingService.shared.acceptShare(metadata: metadata)

            let zoneName = info.zoneName
            let descriptor = FetchDescriptor<BookClub>(
                predicate: #Predicate { $0.cloudZoneName == zoneName }
            )
            let existing = (try? context.fetch(descriptor)) ?? []
            if existing.isEmpty {
                let joined = BookClub(name: info.title)
                joined.cloudZoneName = info.zoneName
                joined.ownerUserRecordName = info.ownerUserRecordName
                joined.shareIsActive = true
                context.insert(joined)
                logger.info("✅ Accepted share — joined '\(info.title, privacy: .public)' (zone \(info.zoneName, privacy: .public))")
            } else {
                logger.info("↺ Share accept ignored — already joined zone \(info.zoneName, privacy: .public)")
            }
        } catch {
            logger.error("⚠️ Share accept failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

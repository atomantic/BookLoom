import Foundation
import SwiftData
import os

/// Wipe every trace of BookLoom from this device and from the user's iCloud.
/// Called from the Settings "Delete All My Data" flow. After this completes
/// the app is back to first-launch state — the welcome flow will reappear.
@MainActor
enum BookLoomDataReset {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "DataReset")

    /// UserDefaults keys this app owns. Listed explicitly rather than
    /// prefix-matched so we never accidentally clear unrelated apps' values
    /// (UserDefaults.standard is a shared suite on macOS).
    private static let ownedDefaultsKeys: [String] = [
        "net.shadowpuppet.BookLoom.appearance",
        "net.shadowpuppet.BookLoom.replayWelcome",
        "net.shadowpuppet.BookLoom.memberName",
        "net.shadowpuppet.BookLoom.memberID",
        "net.shadowpuppet.BookLoom.notifications.proposals",
        "net.shadowpuppet.BookLoom.notifications.selection",
        "net.shadowpuppet.BookLoom.notifications.discussion",
        "net.shadowpuppet.BookLoom.didSaveSharedRootSubscription",
        "net.shadowpuppet.BookLoom.didSaveSharedRootSubscription.v2",
        "net.shadowpuppet.BookLoom.didSavePrivateMemberSubscription.v3",
        "net.shadowpuppet.BookLoom.didSaveSharedMemberSubscription.v3"
    ]

    /// Run the full reset. Best-effort throughout: a single failed step
    /// should not block the rest, since the user has explicitly asked for
    /// everything to go away.
    static func resetAllData(
        context: ModelContext,
        memberIdentity: MemberIdentity
    ) async {
        logger.info("Beginning full data reset")
        let memberID = memberIdentity.memberID

        // 1. Cleanup CloudKit shared zones / leave member shares.
        let clubs = (try? context.fetch(FetchDescriptor<BookClub>())) ?? []
        for club in clubs {
            await SharedClubSync.cleanupBeforeDelete(club, localMemberID: memberID)
        }

        // 2. Delete every SwiftData row. Cascade rules drop submissions,
        //    ratings, notes, prompts, polls, votes, meetings, and RSVPs.
        for club in clubs {
            context.delete(club)
        }
        try? context.save()

        // 3. Clear file-backed caches.
        await BookCoverCache.shared.purgeAll()
        await BookMetadataCache.shared.purgeAll()

        // 4. Drop every UserDefaults key we own (including the per-zone
        //    StatusOverrideStore entries, which use a known prefix).
        let defaults = UserDefaults.standard
        for key in ownedDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("net.shadowpuppet.BookLoom.statusOverrides.") {
            defaults.removeObject(forKey: key)
        }

        // 5. Reset the in-memory MemberIdentity. Setting these property values
        //    re-persists them into UserDefaults under the cleared keys, so we
        //    do this last.
        memberIdentity.name = ""
        memberIdentity.memberID = UUID().uuidString

        logger.info("Reset complete — \(clubs.count) club(s) removed")
    }
}

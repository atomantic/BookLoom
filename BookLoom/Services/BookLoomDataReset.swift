import Foundation
import SwiftData
import os

@MainActor
protocol DataResetStore {
    func fetchClubs() throws -> [BookClub]
    func fetchLibraryBooks() throws -> [LibraryBook]
    func delete(_ club: BookClub)
    func delete(_ book: LibraryBook)
    func save() throws
}

@MainActor
struct ModelContextDataResetStore: DataResetStore {
    let context: ModelContext

    func fetchClubs() throws -> [BookClub] {
        try context.fetch(FetchDescriptor<BookClub>())
    }

    func fetchLibraryBooks() throws -> [LibraryBook] {
        try context.fetch(FetchDescriptor<LibraryBook>())
    }

    func delete(_ club: BookClub) { context.delete(club) }
    func delete(_ book: LibraryBook) { context.delete(book) }
    func save() throws { try context.save() }
}

@MainActor
protocol ResetMemberIdentity: AnyObject {
    var name: String { get set }
    var memberID: String { get set }
}

extension MemberIdentity: ResetMemberIdentity {}

@MainActor
struct DataResetSideEffects {
    var cleanupCloudKit: @MainActor ([ClubCleanupTarget], String) async throws -> Void
    var purgeCaches: @MainActor () async -> Void
    var clearDefaults: @MainActor () -> Void

    static var production: DataResetSideEffects {
        DataResetSideEffects(
            cleanupCloudKit: { targets, memberID in
                for target in targets {
                    try await SharedClubSync.cleanupBeforeDeleteThrowing(target, localMemberID: memberID)
                }
            },
            purgeCaches: {
                await BookCoverCache.shared.purgeAll()
                await BookMetadataCache.shared.purgeAll()
            },
            clearDefaults: { BookLoomDataReset.clearOwnedDefaults() }
        )
    }
}

/// Wipe every trace of BookLoom from this device and from the user's iCloud.
/// Called from the Settings "Delete All My Data" flow. After this completes
/// the app is back to first-launch state — the welcome flow will reappear.
@MainActor
enum BookLoomDataReset {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "DataReset")
    private static let pendingCleanupKey = "net.shadowpuppet.BookLoom.pendingResetCloudKitCleanup"

    private struct PendingCleanup: Codable {
        let targets: [ClubCleanupTarget]
        let memberID: String
        var isCommitted: Bool
    }

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

    /// Run the full reset. The durable model deletion is the commit point:
    /// identity is not replaced until SwiftData confirms the deletion saved.
    static func resetAllData(
        context: ModelContext,
        memberIdentity: MemberIdentity
    ) async throws {
        try await resetAllData(
            store: ModelContextDataResetStore(context: context),
            memberIdentity: memberIdentity,
            sideEffects: .production,
            persistCleanupRecovery: true
        )
    }

    static func resetAllData(
        store: any DataResetStore,
        memberIdentity: any ResetMemberIdentity,
        sideEffects: DataResetSideEffects,
        persistCleanupRecovery: Bool = false
    ) async throws {
        logger.info("Beginning full data reset")
        let memberID = memberIdentity.memberID

        // Fetch everything before mutating. A failed fetch leaves both the
        // durable store and every external side effect untouched.
        let clubs = try store.fetchClubs()
        let libraryBooks = try store.fetchLibraryBooks()
        // SwiftData models become invalid once their deletion is committed.
        // Capture the value-only CloudKit cleanup inputs while they are live,
        // but defer the actual side effect until after the save succeeds.
        let cleanupTargets = clubs.map(ClubCleanupTarget.init)
        if persistCleanupRecovery, !cleanupTargets.isEmpty {
            savePendingCleanup(PendingCleanup(targets: cleanupTargets, memberID: memberID, isCommitted: false))
        }

        // Delete every SwiftData row. Cascade rules drop submissions,
        //    ratings, notes, prompts, polls, votes, meetings, and RSVPs.
        for club in clubs {
            store.delete(club)
        }
        // LibraryBook is an independent root, not a child of BookClub, so it
        // is not covered by the club cascade.
        for book in libraryBooks {
            store.delete(book)
        }
        do {
            try store.save()
        } catch {
            if persistCleanupRecovery { clearPendingCleanup() }
            throw error
        }

        // The save above is the commit point. External cleanup and identity
        // replacement happen only after durable deletion succeeds.
        if persistCleanupRecovery, !cleanupTargets.isEmpty {
            savePendingCleanup(PendingCleanup(targets: cleanupTargets, memberID: memberID, isCommitted: true))
        }
        try await sideEffects.cleanupCloudKit(cleanupTargets, memberID)
        if persistCleanupRecovery { clearPendingCleanup() }
        await sideEffects.purgeCaches()
        sideEffects.clearDefaults()

        memberIdentity.name = ""
        memberIdentity.memberID = UUID().uuidString

        logger.info("Reset complete — \(clubs.count) club(s) and \(libraryBooks.count) library book(s) removed")
    }

    /// Completes CloudKit cleanup left by a crash or outage after the local
    /// deletion commit. A pre-commit marker is discarded when its clubs still
    /// exist, so a failed local save can never delete live remote data later.
    static func retryPendingCloudKitCleanup(context: ModelContext) async {
        guard var pending = loadPendingCleanup() else { return }
        if !pending.isCommitted {
            let existingZones = (try? context.fetch(FetchDescriptor<BookClub>()))
                .map { Set($0.map(\.cloudZoneName)) } ?? []
            guard pending.targets.allSatisfy({ !existingZones.contains($0.zoneName) }) else {
                clearPendingCleanup()
                return
            }
            pending.isCommitted = true
            savePendingCleanup(pending)
        }

        do {
            try await DataResetSideEffects.production.cleanupCloudKit(pending.targets, pending.memberID)
            clearPendingCleanup()
        } catch {
            logger.error("Pending reset CloudKit cleanup will retry next launch: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func savePendingCleanup(_ pending: PendingCleanup) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: pendingCleanupKey)
    }

    private static func loadPendingCleanup() -> PendingCleanup? {
        guard let data = UserDefaults.standard.data(forKey: pendingCleanupKey) else { return nil }
        return try? JSONDecoder().decode(PendingCleanup.self, from: data)
    }

    private static func clearPendingCleanup() {
        UserDefaults.standard.removeObject(forKey: pendingCleanupKey)
    }

    static func clearOwnedDefaults() {
        // Drop every UserDefaults key we own (including the per-zone club
        // mutation logs, which use known prefixes).
        let defaults = UserDefaults.standard
        for key in ownedDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(StatusOverrideStore.prefix)
                || key.hasPrefix(SubmissionDetailsOverrideStore.prefix)
                || key.hasPrefix(SubmissionDeletionStore.prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

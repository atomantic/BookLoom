import Foundation

/// Status overrides are recorded out-of-band (a small in-memory log on the
/// club) when a user picks/completes/moves-back a book. They are flushed into
/// the local member's published snapshot on each save and persisted across
/// app launches via UserDefaults so unsynced overrides survive a restart.
struct StatusOverrideEntry: Codable, Equatable {
    let submissionSelectionID: String
    let statusRaw: String
    let pickedAt: Date?
    let completedAt: Date?
    let occurredAt: Date
    let actorMemberID: String
}

struct SubmissionDetailsOverrideEntry: Codable, Equatable {
    let submissionSelectionID: String
    let title: String
    let author: String
    let isbn: String
    let bookDescription: String
    let publishedYear: Int?
    let coverURL: String
    let externalProvider: String
    let externalID: String
    let updatedAt: Date
    let actorMemberID: String
}

struct SubmissionDeletionEntry: Codable, Equatable {
    let submissionSelectionID: String
    let deletedAt: Date
    let actorMemberID: String
}

extension BookClub {
    /// In-memory cache of recent status overrides that haven't yet been
    /// observed in a remote snapshot for confirmation. Backed by UserDefaults
    /// keyed on the cloud zone so the log survives app restarts.
    var statusOverrideLog: [StatusOverrideEntry] {
        StatusOverrideStore.entries(forZone: cloudZoneName)
    }

    var submissionDetailsOverrideLog: [SubmissionDetailsOverrideEntry] {
        SubmissionDetailsOverrideStore.entries(forZone: cloudZoneName)
    }

    var submissionDeletionLog: [SubmissionDeletionEntry] {
        SubmissionDeletionStore.entries(forZone: cloudZoneName)
    }

    func recordStatusOverride(_ entry: StatusOverrideEntry) {
        StatusOverrideStore.append(entry, forZone: cloudZoneName)
    }

    func recordSubmissionDetailsOverride(_ entry: SubmissionDetailsOverrideEntry) {
        SubmissionDetailsOverrideStore.append(entry, forZone: cloudZoneName)
    }

    func recordSubmissionDeletion(_ entry: SubmissionDeletionEntry) {
        SubmissionDeletionStore.append(entry, forZone: cloudZoneName)
    }

    func pruneAcknowledgedStatusOverrides(merged: [MemberShareSnapshot.StatusOverride]) {
        let keys: Set<String> = Set(merged.map { "\($0.submissionSelectionID)|\($0.occurredAt.timeIntervalSince1970)" })
        StatusOverrideStore.pruneEntries(forZone: cloudZoneName, where: { entry in
            keys.contains("\(entry.submissionSelectionID)|\(entry.occurredAt.timeIntervalSince1970)")
        })
    }

    func pruneAcknowledgedSubmissionDetailsOverrides(merged: [MemberShareSnapshot.SubmissionDetailsOverride]) {
        let keys: Set<String> = Set(merged.map { "\($0.submissionSelectionID)|\($0.updatedAt.timeIntervalSince1970)" })
        SubmissionDetailsOverrideStore.pruneEntries(forZone: cloudZoneName, where: { entry in
            keys.contains("\(entry.submissionSelectionID)|\(entry.updatedAt.timeIntervalSince1970)")
        })
    }

    func pruneAcknowledgedSubmissionDeletions(merged: [MemberShareSnapshot.SubmissionDeletion]) {
        let keys: Set<String> = Set(merged.map { "\($0.submissionSelectionID)|\($0.deletedAt.timeIntervalSince1970)" })
        SubmissionDeletionStore.pruneEntries(forZone: cloudZoneName, where: { entry in
            keys.contains("\(entry.submissionSelectionID)|\(entry.deletedAt.timeIntervalSince1970)")
        })
    }
}

private struct ZoneOverrideStore<Entry: Codable> {
    let prefix: String
    let supersedes: (Entry, Entry) -> Bool

    func entries(forZone zone: String) -> [Entry] {
        guard !zone.isEmpty,
              let data = UserDefaults.standard.data(forKey: prefix + zone),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    func append(_ entry: Entry, forZone zone: String) {
        guard !zone.isEmpty else { return }
        var current = entries(forZone: zone)
        current.removeAll { supersedes(entry, $0) }
        current.append(entry)
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: prefix + zone)
        }
    }

    func pruneEntries(forZone zone: String, where shouldRemove: (Entry) -> Bool) {
        guard !zone.isEmpty else { return }
        let kept = entries(forZone: zone).filter { !shouldRemove($0) }
        if let data = try? JSONEncoder().encode(kept) {
            UserDefaults.standard.set(data, forKey: prefix + zone)
        }
    }

    func clear(forZone zone: String) {
        guard !zone.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: prefix + zone)
    }
}

enum StatusOverrideStore {
    static let prefix = "net.shadowpuppet.BookLoom.statusOverrides."
    private static var store: ZoneOverrideStore<StatusOverrideEntry> {
        ZoneOverrideStore(prefix: prefix) {
            $0.submissionSelectionID == $1.submissionSelectionID && $0.actorMemberID == $1.actorMemberID
        }
    }

    static func entries(forZone zone: String) -> [StatusOverrideEntry] { store.entries(forZone: zone) }
    static func append(_ entry: StatusOverrideEntry, forZone zone: String) { store.append(entry, forZone: zone) }
    static func pruneEntries(forZone zone: String, where shouldRemove: (StatusOverrideEntry) -> Bool) { store.pruneEntries(forZone: zone, where: shouldRemove) }
    static func clear(forZone zone: String) { store.clear(forZone: zone) }
}

enum SubmissionDetailsOverrideStore {
    static let prefix = "net.shadowpuppet.BookLoom.submissionDetailsOverrides."
    private static var store: ZoneOverrideStore<SubmissionDetailsOverrideEntry> {
        ZoneOverrideStore(prefix: prefix) {
            $0.submissionSelectionID == $1.submissionSelectionID && $0.actorMemberID == $1.actorMemberID
        }
    }

    static func entries(forZone zone: String) -> [SubmissionDetailsOverrideEntry] {
        store.entries(forZone: zone)
    }

    static func append(_ entry: SubmissionDetailsOverrideEntry, forZone zone: String) {
        store.append(entry, forZone: zone)
    }

    static func pruneEntries(forZone zone: String, where shouldRemove: (SubmissionDetailsOverrideEntry) -> Bool) {
        store.pruneEntries(forZone: zone, where: shouldRemove)
    }

    static func clear(forZone zone: String) {
        store.clear(forZone: zone)
    }
}

enum SubmissionDeletionStore {
    static let prefix = "net.shadowpuppet.BookLoom.submissionDeletions."
    private static var store: ZoneOverrideStore<SubmissionDeletionEntry> {
        ZoneOverrideStore(prefix: prefix) {
            $0.submissionSelectionID == $1.submissionSelectionID && $0.actorMemberID == $1.actorMemberID
        }
    }

    static func entries(forZone zone: String) -> [SubmissionDeletionEntry] {
        store.entries(forZone: zone)
    }

    static func append(_ entry: SubmissionDeletionEntry, forZone zone: String) {
        store.append(entry, forZone: zone)
    }

    static func pruneEntries(forZone zone: String, where shouldRemove: (SubmissionDeletionEntry) -> Bool) {
        store.pruneEntries(forZone: zone, where: shouldRemove)
    }

    static func clear(forZone zone: String) {
        store.clear(forZone: zone)
    }
}

import Foundation

extension String {
    /// Whitespace-trimmed value, or `nil` if the trim leaves nothing.
    /// Lives in `Shared/` because the share extension can't import the main
    /// app's design system where `String.trimmedOrNil` lives.
    fileprivate var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// App Group-backed queue for handing book imports from the Share Extension to
/// the main app. The extension enqueues a Goodreads URL here; the main app
/// reflects those items on the Books screen Shelf and presents the import sheet
/// when a row is opened.
///
/// Stored as a JSON array under a single key so multiple shares stack instead
/// of overwriting each other when the user shares several books before
/// returning to BookLoom.
enum SharedImportInbox {
    static let appGroupID = "group.net.shadowpuppet.PlotLoom"
    static let queueKey = "pendingGoodreadsImportQueue"
    static let legacyURLKey = "pendingGoodreadsImportURL"
    static let legacyTimestampKey = "pendingGoodreadsImportTimestamp"
    static let pendingMaxAge: TimeInterval = 60 * 60 * 24 * 7 // 7 days
    /// Hard cap so a misbehaving share loop can't balloon the App Group blob.
    static let maxQueueLength = 50

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// All metadata fields are `Optional` so App-Group blobs encoded before
    /// they were added still decode cleanly — users with pending pre-update
    /// shares don't lose their queue.
    struct PendingImport: Codable, Equatable, Identifiable {
        let url: URL
        let enqueuedAt: Date
        var title: String? = nil
        var author: String? = nil
        var coverURLString: String? = nil
        var bookDescription: String? = nil
        var publishedYear: Int? = nil
        var isbn: String? = nil
        var externalProvider: String? = nil
        var externalID: String? = nil
        var metadataFetchedAt: Date? = nil

        var id: String { url.absoluteString }

        var coverURL: URL? {
            guard let value = coverURLString?.trimmedNonEmpty else { return nil }
            return URL(string: value)
        }

        var hasResolvedMetadata: Bool {
            metadataFetchedAt != nil
        }

        var displayTitle: String? { title?.trimmedNonEmpty }
        var displayAuthor: String? { author?.trimmedNonEmpty }
    }

    /// Append a Goodreads URL to the back of the queue. Duplicate URLs already
    /// in the queue are skipped so re-sharing the same book doesn't pile up.
    /// If the queue grows past `maxQueueLength`, the oldest entries are dropped.
    static func enqueue(_ url: URL, defaults: UserDefaults? = SharedImportInbox.defaults, now: Date = .now) {
        guard let defaults else { return }
        var queue = readQueue(defaults: defaults, now: now)
        if queue.contains(where: { $0.url == url }) { return }
        queue.append(PendingImport(url: url, enqueuedAt: now))
        if queue.count > maxQueueLength {
            queue.removeFirst(queue.count - maxQueueLength)
        }
        writeQueue(queue, defaults: defaults)
    }

    /// Returns all pending imports oldest-first (insertion order).
    /// Aged entries are pruned as a side effect.
    static func peekAll(defaults: UserDefaults? = SharedImportInbox.defaults, now: Date = .now) -> [PendingImport] {
        guard let defaults else { return [] }
        return readQueue(defaults: defaults, now: now)
    }

    static func peekNext(defaults: UserDefaults? = SharedImportInbox.defaults, now: Date = .now) -> URL? {
        peekAll(defaults: defaults, now: now).first?.url
    }

    static func remove(_ url: URL, defaults: UserDefaults? = SharedImportInbox.defaults, now: Date = .now) {
        guard let defaults else { return }
        var queue = readQueue(defaults: defaults, now: now)
        queue.removeAll { $0.url == url }
        writeQueue(queue, defaults: defaults)
    }

    /// Mutates the queue entry for `url` in place. Returns `true` if a matching
    /// entry was found and updated. The caller's closure receives an inout copy
    /// of the entry so it can write resolved metadata fields without having to
    /// reconstruct identity (`url`, `enqueuedAt`).
    @discardableResult
    static func update(
        _ url: URL,
        defaults: UserDefaults? = SharedImportInbox.defaults,
        now: Date = .now,
        mutation: (inout PendingImport) -> Void
    ) -> Bool {
        guard let defaults else { return false }
        var queue = readQueue(defaults: defaults, now: now)
        guard let index = queue.firstIndex(where: { $0.url == url }) else { return false }
        mutation(&queue[index])
        writeQueue(queue, defaults: defaults)
        return true
    }

    static func clear(defaults: UserDefaults? = SharedImportInbox.defaults) {
        guard let defaults else { return }
        defaults.removeObject(forKey: queueKey)
        defaults.removeObject(forKey: legacyURLKey)
        defaults.removeObject(forKey: legacyTimestampKey)
    }

    static func pendingCount(defaults: UserDefaults? = SharedImportInbox.defaults, now: Date = .now) -> Int {
        peekAll(defaults: defaults, now: now).count
    }

    static func shareConfirmationMessage(pendingCount: Int) -> String {
        if pendingCount > 1 {
            return "\(pendingCount) books are waiting on your Shelf on the Books screen. Open BookLoom to add them to a club."
        }
        return "This book is waiting on your Shelf on the Books screen. Open BookLoom to add it to a club."
    }

    // MARK: - Internal

    /// Decodes the queue, migrates a legacy single-URL entry into it, prunes
    /// aged entries, and writes back if anything changed. The "read" mutates
    /// — necessary so legacy migration and pruning happen lazily on access.
    private static func readQueue(defaults: UserDefaults, now: Date) -> [PendingImport] {
        var queue: [PendingImport] = []
        if let data = defaults.data(forKey: queueKey),
           let decoded = try? JSONDecoder().decode([PendingImport].self, from: data) {
            queue = decoded
        }

        var migratedLegacy = false
        if let legacy = drainLegacyEntry(defaults: defaults),
           !queue.contains(where: { $0.url == legacy.url }) {
            queue.append(legacy)
            migratedLegacy = true
        }

        let cutoff = now.timeIntervalSince1970 - pendingMaxAge
        let pruned = queue.filter { $0.enqueuedAt.timeIntervalSince1970 >= cutoff }
        if migratedLegacy || pruned.count != queue.count {
            writeQueue(pruned, defaults: defaults)
        }
        return pruned
    }

    private static func writeQueue(_ queue: [PendingImport], defaults: UserDefaults) {
        if queue.isEmpty {
            defaults.removeObject(forKey: queueKey)
            return
        }
        guard let data = try? JSONEncoder().encode(queue) else { return }
        defaults.set(data, forKey: queueKey)
    }

    private static func drainLegacyEntry(defaults: UserDefaults) -> PendingImport? {
        guard let raw = defaults.string(forKey: legacyURLKey),
              let url = URL(string: raw) else {
            return nil
        }
        let timestamp = defaults.double(forKey: legacyTimestampKey)
        defaults.removeObject(forKey: legacyURLKey)
        defaults.removeObject(forKey: legacyTimestampKey)
        let date = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : .now
        return PendingImport(url: url, enqueuedAt: date)
    }
}

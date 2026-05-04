import Foundation

/// App Group-backed queue for handing book imports from the Share Extension to
/// the main app. The extension enqueues a Goodreads URL here; the main app
/// drains items on launch / foreground / `bookloom://import` and presents the
/// import sheet for each.
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

    struct PendingImport: Codable, Equatable, Identifiable {
        let url: URL
        let enqueuedAt: Date

        var id: String { url.absoluteString }
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

    static func clear(defaults: UserDefaults? = SharedImportInbox.defaults) {
        guard let defaults else { return }
        defaults.removeObject(forKey: queueKey)
        defaults.removeObject(forKey: legacyURLKey)
        defaults.removeObject(forKey: legacyTimestampKey)
    }

    static func pendingCount(defaults: UserDefaults? = SharedImportInbox.defaults, now: Date = .now) -> Int {
        peekAll(defaults: defaults, now: now).count
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

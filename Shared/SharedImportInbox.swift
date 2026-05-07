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

/// Queue for handing book imports to the main app. On iOS this is App
/// Group-backed because the Share Extension enqueues Goodreads URLs from a
/// separate process. On macOS there is no share extension, so the queue stays
/// in the app's own defaults to avoid cross-app container prompts.
///
/// Stored as a JSON array under a single key so multiple shares stack instead
/// of overwriting each other when the user shares several books before
/// returning to BookLoom.
enum SharedImportInbox {
    static let appGroupID = "group.net.shadowpuppet.PlotLoom"
    static let queueKey = "pendingGoodreadsImportQueue"
    static let queueFileName = "pendingGoodreadsImportQueue.json"
    static let legacyURLKey = "pendingGoodreadsImportURL"
    static let legacyTimestampKey = "pendingGoodreadsImportTimestamp"
    static let pendingMaxAge: TimeInterval = 60 * 60 * 24 * 7 // 7 days
    /// Hard cap so a misbehaving share loop can't balloon the App Group blob.
    static let maxQueueLength = 50

    #if os(macOS)
    nonisolated(unsafe) static let defaults: UserDefaults? = .standard
    #else
    nonisolated(unsafe) static let defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    #endif

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
    static func enqueue(
        _ url: URL,
        defaults: UserDefaults? = SharedImportInbox.defaults,
        now: Date = .now,
        fileURL: URL? = nil
    ) {
        let resolvedFileURL = resolvedQueueFileURL(defaults: defaults, explicitFileURL: fileURL)
        var queue = readQueue(defaults: defaults, now: now, fileURL: resolvedFileURL)
        if queue.contains(where: { $0.url == url }) { return }
        queue.append(PendingImport(url: url, enqueuedAt: now))
        if queue.count > maxQueueLength {
            queue.removeFirst(queue.count - maxQueueLength)
        }
        writeQueue(queue, defaults: defaults, fileURL: resolvedFileURL)
    }

    /// Returns all pending imports oldest-first (insertion order).
    /// Aged entries are pruned as a side effect.
    static func peekAll(
        defaults: UserDefaults? = SharedImportInbox.defaults,
        now: Date = .now,
        fileURL: URL? = nil
    ) -> [PendingImport] {
        readQueue(defaults: defaults, now: now, fileURL: resolvedQueueFileURL(defaults: defaults, explicitFileURL: fileURL))
    }

    static func peekNext(
        defaults: UserDefaults? = SharedImportInbox.defaults,
        now: Date = .now,
        fileURL: URL? = nil
    ) -> URL? {
        peekAll(defaults: defaults, now: now, fileURL: fileURL).first?.url
    }

    static func remove(
        _ url: URL,
        defaults: UserDefaults? = SharedImportInbox.defaults,
        now: Date = .now,
        fileURL: URL? = nil
    ) {
        let resolvedFileURL = resolvedQueueFileURL(defaults: defaults, explicitFileURL: fileURL)
        var queue = readQueue(defaults: defaults, now: now, fileURL: resolvedFileURL)
        queue.removeAll { $0.url == url }
        writeQueue(queue, defaults: defaults, fileURL: resolvedFileURL)
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
        fileURL: URL? = nil,
        mutation: (inout PendingImport) -> Void
    ) -> Bool {
        let resolvedFileURL = resolvedQueueFileURL(defaults: defaults, explicitFileURL: fileURL)
        var queue = readQueue(defaults: defaults, now: now, fileURL: resolvedFileURL)
        guard let index = queue.firstIndex(where: { $0.url == url }) else { return false }
        mutation(&queue[index])
        writeQueue(queue, defaults: defaults, fileURL: resolvedFileURL)
        return true
    }

    /// Replace the entire queue in a single read-modify-write. Used by
    /// screenshot seeding to avoid N round-trips through UserDefaults + the
    /// App Group file mirror when populating multiple resolved entries at once.
    static func replaceAll(
        _ entries: [PendingImport],
        defaults: UserDefaults? = SharedImportInbox.defaults,
        fileURL: URL? = nil
    ) {
        let resolvedFileURL = resolvedQueueFileURL(defaults: defaults, explicitFileURL: fileURL)
        writeQueue(entries, defaults: defaults, fileURL: resolvedFileURL)
    }

    static func clear(defaults: UserDefaults? = SharedImportInbox.defaults, fileURL: URL? = nil) {
        let resolvedFileURL = resolvedQueueFileURL(defaults: defaults, explicitFileURL: fileURL)
        defaults?.removeObject(forKey: queueKey)
        defaults?.removeObject(forKey: legacyURLKey)
        defaults?.removeObject(forKey: legacyTimestampKey)
        defaults?.synchronize()
        if let resolvedFileURL {
            try? FileManager.default.removeItem(at: resolvedFileURL)
        }
    }

    static func pendingCount(
        defaults: UserDefaults? = SharedImportInbox.defaults,
        now: Date = .now,
        fileURL: URL? = nil
    ) -> Int {
        peekAll(defaults: defaults, now: now, fileURL: fileURL).count
    }

    static func shareConfirmationMessage(pendingCount: Int) -> String {
        if pendingCount > 1 {
            return "\(pendingCount) books are waiting in Imports. Open BookLoom to choose Shelf and club destinations."
        }
        return "This book is waiting in Imports. Open BookLoom to choose Shelf and club destinations."
    }

    // MARK: - Internal

    /// Decodes the queue, migrates a legacy single-URL entry into it, prunes
    /// aged entries, and writes back if anything changed. The "read" mutates
    /// — necessary so legacy migration and pruning happen lazily on access.
    private static func readQueue(defaults: UserDefaults?, now: Date, fileURL: URL?) -> [PendingImport] {
        let defaultsQueue: [PendingImport]
        if let data = defaults?.data(forKey: queueKey),
           let decoded = try? JSONDecoder().decode([PendingImport].self, from: data) {
            defaultsQueue = decoded
        } else {
            defaultsQueue = []
        }

        let fileQueue = readQueueFile(fileURL: fileURL)
        var queue = mergedQueue(defaultsQueue + fileQueue)

        var migratedLegacy = false
        if let defaults,
           let legacy = drainLegacyEntry(defaults: defaults),
           !queue.contains(where: { $0.url == legacy.url }) {
            queue.append(legacy)
            migratedLegacy = true
        }

        let cutoff = now.timeIntervalSince1970 - pendingMaxAge
        let pruned = queue.filter { $0.enqueuedAt.timeIntervalSince1970 >= cutoff }
        if migratedLegacy || pruned != defaultsQueue || pruned != fileQueue || pruned.count != queue.count {
            writeQueue(pruned, defaults: defaults, fileURL: fileURL)
        }
        return pruned
    }

    private static func writeQueue(_ queue: [PendingImport], defaults: UserDefaults?, fileURL: URL?) {
        if queue.isEmpty {
            defaults?.removeObject(forKey: queueKey)
            defaults?.synchronize()
            if let fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            return
        }
        guard let data = try? JSONEncoder().encode(queue) else { return }
        defaults?.set(data, forKey: queueKey)
        defaults?.synchronize()
        writeQueueFile(data, fileURL: fileURL)
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

    private static func resolvedQueueFileURL(defaults: UserDefaults?, explicitFileURL: URL?) -> URL? {
        if let explicitFileURL { return explicitFileURL }
        if ProcessInfo.processInfo.arguments.contains("-SeedSampleData") { return nil }
        #if os(macOS)
        return nil
        #else
        guard defaults === SharedImportInbox.defaults else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(queueFileName, isDirectory: false)
        #endif
    }

    private static func readQueueFile(fileURL: URL?) -> [PendingImport] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PendingImport].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func writeQueueFile(_ data: Data, fileURL: URL?) {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // The UserDefaults queue remains the primary store; the file mirror is
            // only a cross-process durability fallback for the share extension.
        }
    }

    private static func mergedQueue(_ queue: [PendingImport]) -> [PendingImport] {
        var merged: [URL: PendingImport] = [:]
        for entry in queue {
            if let existing = merged[entry.url] {
                merged[entry.url] = preferredEntry(existing, entry)
            } else {
                merged[entry.url] = entry
            }
        }
        return merged.values.sorted { $0.enqueuedAt < $1.enqueuedAt }
    }

    private static func preferredEntry(_ lhs: PendingImport, _ rhs: PendingImport) -> PendingImport {
        switch (lhs.metadataFetchedAt, rhs.metadataFetchedAt) {
        case let (left?, right?):
            return right > left ? rhs : lhs
        case (nil, _?):
            return rhs
        default:
            return lhs
        }
    }
}

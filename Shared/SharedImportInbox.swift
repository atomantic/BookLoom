import Foundation

/// App Group-backed store for handing imports from the Share Extension to
/// the main app. The extension writes a pending Goodreads URL here; the
/// main app drains it on launch / foreground / `bookloom://import`.
enum SharedImportInbox {
    static let appGroupID = "group.net.shadowpuppet.PlotLoom"
    private static let pendingURLKey = "pendingGoodreadsImportURL"
    private static let pendingTimestampKey = "pendingGoodreadsImportTimestamp"
    private static let pendingMaxAge: TimeInterval = 60 * 60 // 1 hour

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func savePendingGoodreadsURL(_ url: URL) {
        guard let defaults else { return }
        defaults.set(url.absoluteString, forKey: pendingURLKey)
        defaults.set(Date.now.timeIntervalSince1970, forKey: pendingTimestampKey)
    }

    /// Returns and clears the pending URL if it was written within the past
    /// hour. Older entries are discarded so a stale share doesn't surprise
    /// the user weeks later.
    @discardableResult
    static func consumePendingGoodreadsURL() -> URL? {
        guard let defaults,
              let raw = defaults.string(forKey: pendingURLKey),
              let url = URL(string: raw) else {
            return nil
        }
        let timestamp = defaults.double(forKey: pendingTimestampKey)
        defaults.removeObject(forKey: pendingURLKey)
        defaults.removeObject(forKey: pendingTimestampKey)

        let age = Date.now.timeIntervalSince1970 - timestamp
        guard age >= 0, age < pendingMaxAge else { return nil }
        return url
    }
}

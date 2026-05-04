import Foundation
import Observation
import os

/// Live, observable view of `SharedImportInbox` for SwiftUI. The underlying
/// queue lives in App Group `UserDefaults` so the iOS Share Extension can
/// enqueue items even while the host app is suspended; views subscribe
/// through this model so the queue is reflected in the UI without polling.
///
/// Two presentation paths feed `presentedItem`:
///   • `presentNextIfNeeded()` — used by auto-pop on app launch / foreground.
///     Records URLs that were skipped (closed without saving) so the same
///     book doesn't pop again every time the app returns to active.
///   • `present(_:)` — used when the user explicitly taps a row in the
///     visible Import Inbox banner. Bypasses the skip set.
///
/// `prefetchAll()` resolves Goodreads metadata for unresolved entries in the
/// background so the banner can show real titles/covers without the user
/// opening every row.
@Observable
@MainActor
final class GoodreadsImportInbox {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "ImportInbox")

    private(set) var pending: [SharedImportInbox.PendingImport] = []
    var presentedItem: SharedImportInbox.PendingImport?
    private var skippedThisSession: Set<URL> = []
    private var prefetching: Set<URL> = []
    private var failedThisSession: Set<URL> = []
    private var prefetchTask: Task<Void, Never>?
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = SharedImportInbox.defaults) {
        self.defaults = defaults
        refresh()
    }

    func refresh() {
        let next = SharedImportInbox.peekAll(defaults: defaults)
        if next != pending { pending = next }
    }

    func presentNextIfNeeded() {
        guard presentedItem == nil else { return }
        refresh()
        guard let next = pending.first(where: { !skippedThisSession.contains($0.url) }) else { return }
        skippedThisSession.insert(next.url)
        presentedItem = next
    }

    func present(_ url: URL) {
        refresh()
        if let match = pending.first(where: { $0.url == url }) {
            presentedItem = match
        }
    }

    func dismiss(saved: Bool) {
        if saved, let url = presentedItem?.url {
            SharedImportInbox.remove(url, defaults: defaults)
            forget(url)
        }
        presentedItem = nil
        refresh()
    }

    func remove(_ url: URL) {
        SharedImportInbox.remove(url, defaults: defaults)
        forget(url)
        refresh()
    }

    /// Idempotent: callers can fire this on every foreground without worrying
    /// about duplicate work — entries already in flight or marked failed this
    /// session are skipped. Failures are forgotten on relaunch (the common
    /// recovery case after a network hiccup). Runs serially in a single Task
    /// to avoid both fan-out rate-limits and read-modify-write contention on
    /// the App-Group blob.
    func prefetchAll(metadataService: BookMetadataService = BookMetadataService()) {
        refresh()
        let toFetch = pending.filter(shouldPrefetch)
        guard !toFetch.isEmpty else { return }
        for item in toFetch { prefetching.insert(item.url) }
        let urls = toFetch.map(\.url)
        prefetchTask = Task { [weak self] in
            for url in urls {
                guard !Task.isCancelled else { return }
                await self?.runPrefetch(url, service: metadataService)
            }
        }
    }

    private func shouldPrefetch(_ item: SharedImportInbox.PendingImport) -> Bool {
        if item.hasResolvedMetadata { return false }
        if prefetching.contains(item.url) { return false }
        if failedThisSession.contains(item.url) { return false }
        return true
    }

    private func runPrefetch(_ url: URL, service: BookMetadataService) async {
        defer { prefetching.remove(url) }
        do {
            let candidate = try await service.importFromGoodreads(url: url)
            var resolved: SharedImportInbox.PendingImport?
            let written = SharedImportInbox.update(url, defaults: defaults) { entry in
                entry.apply(candidate)
                resolved = entry
            }
            if written, let resolved {
                Self.logger.info("📚 Prefetched \(url.absoluteString, privacy: .public): \(candidate.title, privacy: .public)")
                spliceInPlace(resolved)
            }
        } catch {
            failedThisSession.insert(url)
            Self.logger.error("⚠️ Prefetch failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Update the published `pending` array without re-reading the App Group
    /// blob. Avoids one full disk read + JSON decode per successful prefetch.
    private func spliceInPlace(_ updated: SharedImportInbox.PendingImport) {
        guard let index = pending.firstIndex(where: { $0.url == updated.url }) else { return }
        pending[index] = updated
    }

    private func forget(_ url: URL) {
        skippedThisSession.remove(url)
        prefetching.remove(url)
        failedThisSession.remove(url)
    }
}

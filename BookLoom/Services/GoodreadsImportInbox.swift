import Foundation
import Observation

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
@Observable
final class GoodreadsImportInbox {
    private(set) var pending: [SharedImportInbox.PendingImport] = []
    var presentedItem: SharedImportInbox.PendingImport?
    private var skippedThisSession: Set<URL> = []
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
            skippedThisSession.remove(url)
        }
        presentedItem = nil
        refresh()
    }

    func remove(_ url: URL) {
        SharedImportInbox.remove(url, defaults: defaults)
        skippedThisSession.remove(url)
        refresh()
    }
}

import UIKit
import UniformTypeIdentifiers
import os

private let shareLogger = Logger(subsystem: "net.shadowpuppet.BookLoom.ShareExtension", category: "Share")

/// Share Extension entry point. Reads a shared URL/text, extracts a Goodreads
/// book URL, queues it for the main app via the App Group import inbox, and
/// shows a confirmation alert so the user knows the share succeeded.
///
/// We don't try to launch the host app from here. Apple disallows share
/// extensions launching their containing app via `UIApplication.openURL` on
/// the responder chain (the `perform` returns truthy but no launch happens),
/// which previously caused the extension to flash a blank screen and dump
/// the user back into the source app with no feedback.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handleSharedItems() }
    }

    private func handleSharedItems() async {
        guard let url = await firstGoodreadsURL() else {
            shareLogger.error("📥 Share: no Goodreads URL found in shared items")
            await present(
                title: "No Book Link Found",
                message: "BookLoom couldn't find a Goodreads link in what you shared. Try sharing the book's page from inside Goodreads.",
                success: false
            )
            return
        }

        SharedImportInbox.enqueue(url)
        let pending = SharedImportInbox.pendingCount()
        shareLogger.info("📥 Share: queued Goodreads URL \(url.absoluteString, privacy: .public) (\(pending, privacy: .public) pending)")

        let detail = pending > 1
            ? "\(pending) books are waiting in your Import Inbox. Open BookLoom to add them to a club."
            : "Open BookLoom to add this book to a club."
        await present(
            title: "Saved to BookLoom",
            message: detail,
            success: true
        )
    }

    private func firstGoodreadsURL() async -> URL? {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        for item in inputItems {
            for provider in item.attachments ?? [] {
                if let url = await loadURL(from: provider),
                   let canonical = GoodreadsLinkExtractor.extract(from: url) {
                    return canonical
                }
                if let text = await loadText(from: provider),
                   let canonical = GoodreadsLinkExtractor.extract(fromText: text) {
                    return canonical
                }
            }
        }
        return nil
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    @MainActor
    private func present(title: String, message: String, success: Bool) async {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: success ? "Done" : "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        present(alert, animated: true)
    }
}

import UIKit
import UniformTypeIdentifiers
import os

private let shareLogger = Logger(subsystem: "net.shadowpuppet.BookLoom.ShareExtension", category: "Share")

/// Share Extension entry point. Reads a shared URL/text, extracts a Goodreads
/// book URL, hands it to the main app via the App Group pending-import store,
/// and attempts to launch BookLoom via its custom URL scheme.
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
            await present(message: "BookLoom couldn't find a Goodreads link in what you shared.", success: false)
            return
        }

        SharedImportInbox.savePendingGoodreadsURL(url)
        shareLogger.info("📥 Share: queued Goodreads URL \(url.absoluteString, privacy: .public)")

        if openMainApp(with: url) {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            await present(message: "Saved! Open BookLoom to finish adding this book.", success: true)
        }
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

    /// Tries to open the main app via custom URL scheme using the responder chain.
    /// Returns true if the open call dispatched; the system may still ignore it.
    @discardableResult
    private func openMainApp(with goodreadsURL: URL) -> Bool {
        guard var components = URLComponents(string: "bookloom://import") else { return false }
        components.queryItems = [URLQueryItem(name: "url", value: goodreadsURL.absoluteString)]
        guard let openURL = components.url else { return false }

        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: openURL)
                return true
            }
            responder = current.next
        }
        return false
    }

    @MainActor
    private func present(message: String, success: Bool) async {
        let alert = UIAlertController(title: success ? "Saved to BookLoom" : "Couldn't Save", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        present(alert, animated: true)
    }
}

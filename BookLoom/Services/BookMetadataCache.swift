import CryptoKit
import Foundation

private func sha256Hex(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}

actor BookMetadataCache {
    static let shared = BookMetadataCache()

    private struct SearchPayload: Codable {
        let storedAt: Date
        let candidates: [BookMetadataCandidate]
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let timeToLive: TimeInterval

    init(
        rootURL: URL? = nil,
        timeToLive: TimeInterval = 60 * 60 * 24 * 30,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.timeToLive = timeToLive
        let baseURL = rootURL
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.rootURL = baseURL.appendingPathComponent("BookMetadataCache", isDirectory: true)
    }

    func cachedResults(title: String, author: String, now: Date = .now) -> [BookMetadataCandidate]? {
        let url = searchURL(title: title, author: author)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(SearchPayload.self, from: data),
              now.timeIntervalSince(payload.storedAt) <= timeToLive else {
            return nil
        }
        return payload.candidates
    }

    func store(_ candidates: [BookMetadataCandidate], title: String, author: String, now: Date = .now) {
        let payload = SearchPayload(storedAt: now, candidates: candidates)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? data.write(to: searchURL(title: title, author: author), options: [.atomic])
    }

    func cachedISBN(_ isbn: String, now: Date = .now) -> BookMetadataCandidate? {
        let url = isbnURL(isbn)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(SearchPayload.self, from: data),
              now.timeIntervalSince(payload.storedAt) <= timeToLive else {
            return nil
        }
        return payload.candidates.first
    }

    func store(_ candidate: BookMetadataCandidate, isbn: String, now: Date = .now) {
        let payload = SearchPayload(storedAt: now, candidates: [candidate])
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? data.write(to: isbnURL(isbn), options: [.atomic])
    }

    func purgeAll() {
        try? fileManager.removeItem(at: rootURL)
    }

    private func searchURL(title: String, author: String) -> URL {
        let key = ["search", normalized(title), normalized(author)].joined(separator: "|")
        return rootURL.appendingPathComponent("\(sha256Hex(key)).json", isDirectory: false)
    }

    private func isbnURL(_ isbn: String) -> URL {
        let key = ["isbn", normalized(isbn)].joined(separator: "|")
        return rootURL.appendingPathComponent("\(sha256Hex(key)).json", isDirectory: false)
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

actor BookCoverCache {
    static let shared = BookCoverCache()

    /// URL scheme used for user-uploaded covers. The bytes live in App Support
    /// (persistent, not iCloud-synced) and the synthetic URL string is what's
    /// stored in `coverURL` on `BookSubmission` / `LibraryBook` so the existing
    /// rendering path picks them up via the cache.
    static let manualCoverScheme = "bookloom"
    static let manualCoverHost = "manual-cover"

    private let fileManager: FileManager
    private let rootURL: URL
    private let manualRootURL: URL
    private let maxCoverBytes = 700 * 1024

    init(rootURL: URL? = nil, manualRootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = Self.defaultRootURL(rootURL: rootURL, fileManager: fileManager)
        self.manualRootURL = Self.defaultManualRootURL(rootURL: manualRootURL, fileManager: fileManager)
    }

    func cachedData(for url: URL) -> Data? {
        let fileURL = Self.isManualCoverURL(url)
            ? Self.manualFileURL(identifier: url.lastPathComponent, in: manualRootURL)
            : Self.cacheFileURL(for: url, in: rootURL)
        guard let data = try? Data(contentsOf: fileURL),
              data.count <= maxCoverBytes else {
            return nil
        }
        return data
    }

    func data(for url: URL, urlSession: URLSession = .shared) async -> Data? {
        if let cached = cachedData(for: url) {
            return cached
        }

        // Manual covers never network-fetch. If the bytes aren't on disk
        // (e.g. the user uploaded on another device), render the placeholder.
        if Self.isManualCoverURL(url) {
            return nil
        }

        guard let (data, response) = try? await urlSession.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= maxCoverBytes else {
            return nil
        }

        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? data.write(to: Self.cacheFileURL(for: url, in: rootURL), options: [.atomic])
        return data
    }

    /// Persist a user-uploaded cover under a stable identifier. Returns the
    /// synthetic URL to store on the model, or nil if the bytes exceed
    /// `maxCoverBytes` or disk write fails.
    @discardableResult
    func storeManual(data: Data, identifier: String) -> URL? {
        guard data.count > 0, data.count <= maxCoverBytes else { return nil }
        let trimmedID = Self.sanitizedIdentifier(identifier)
        guard !trimmedID.isEmpty else { return nil }
        try? fileManager.createDirectory(at: manualRootURL, withIntermediateDirectories: true)
        let fileURL = Self.manualFileURL(identifier: trimmedID, in: manualRootURL)
        guard (try? data.write(to: fileURL, options: [.atomic])) != nil else { return nil }
        return Self.manualCoverURL(identifier: trimmedID)
    }

    func removeManual(identifier: String) {
        let trimmedID = Self.sanitizedIdentifier(identifier)
        guard !trimmedID.isEmpty else { return }
        try? fileManager.removeItem(at: Self.manualFileURL(identifier: trimmedID, in: manualRootURL))
    }

    func purgeAll() {
        try? fileManager.removeItem(at: rootURL)
        try? fileManager.removeItem(at: manualRootURL)
    }

    /// Seed the on-disk cache synchronously. MUST be called before any
    /// `BookCoverCache.shared` access — there is no internal locking, so callers
    /// rely on a happens-before ordering with the first actor read.
    nonisolated static func seedSync(_ mappings: [(url: URL, data: Data)], fileManager: FileManager = .default) {
        let rootURL = defaultRootURL(rootURL: nil, fileManager: fileManager)
        let manualURL = defaultManualRootURL(rootURL: nil, fileManager: fileManager)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: manualURL, withIntermediateDirectories: true)
        for (url, data) in mappings {
            let fileURL: URL = isManualCoverURL(url)
                ? manualFileURL(identifier: url.lastPathComponent, in: manualURL)
                : cacheFileURL(for: url, in: rootURL)
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    nonisolated static func manualCoverURL(identifier: String) -> URL {
        let trimmed = sanitizedIdentifier(identifier)
        return URL(string: "\(manualCoverScheme)://\(manualCoverHost)/\(trimmed)")
            ?? URL(string: "\(manualCoverScheme)://\(manualCoverHost)/unknown")!
    }

    nonisolated static func isManualCoverURL(_ url: URL) -> Bool {
        url.scheme == manualCoverScheme && url.host == manualCoverHost
    }

    private static func defaultRootURL(rootURL: URL?, fileManager: FileManager) -> URL {
        let baseURL = rootURL
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent("BookCoverCache", isDirectory: true)
    }

    /// Manual covers go in App Support so iOS doesn't purge them like cache.
    private static func defaultManualRootURL(rootURL: URL?, fileManager: FileManager) -> URL {
        if let rootURL { return rootURL }
        let appSupport = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport.appendingPathComponent("ManualBookCovers", isDirectory: true)
    }

    private static func cacheFileURL(for url: URL, in rootURL: URL) -> URL {
        rootURL.appendingPathComponent("\(sha256Hex(url.absoluteString)).data", isDirectory: false)
    }

    private static func manualFileURL(identifier: String, in rootURL: URL) -> URL {
        rootURL.appendingPathComponent("\(sanitizedIdentifier(identifier)).data", isDirectory: false)
    }

    /// Strip anything that isn't a safe filename character. Identifiers come
    /// from user-controlled IDs (selectionID / libraryID) so we don't trust
    /// them with raw path components.
    private static func sanitizedIdentifier(_ identifier: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return identifier.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : Character("_") }
            .map(String.init)
            .joined()
    }
}

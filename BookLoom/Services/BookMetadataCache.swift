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

    private let fileManager: FileManager
    private let rootURL: URL
    private let maxCoverBytes = 700 * 1024

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = Self.defaultRootURL(rootURL: rootURL, fileManager: fileManager)
    }

    func cachedData(for url: URL) -> Data? {
        guard let data = try? Data(contentsOf: Self.cacheFileURL(for: url, in: rootURL)),
              data.count <= maxCoverBytes else {
            return nil
        }
        return data
    }

    func data(for url: URL, urlSession: URLSession = .shared) async -> Data? {
        if let cached = cachedData(for: url) {
            return cached
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

    func purgeAll() {
        try? fileManager.removeItem(at: rootURL)
    }

    /// Seed the on-disk cache synchronously. MUST be called before any
    /// `BookCoverCache.shared` access — there is no internal locking, so callers
    /// rely on a happens-before ordering with the first actor read.
    nonisolated static func seedSync(_ mappings: [(url: URL, data: Data)], fileManager: FileManager = .default) {
        let rootURL = defaultRootURL(rootURL: nil, fileManager: fileManager)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for (url, data) in mappings {
            let fileURL = cacheFileURL(for: url, in: rootURL)
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    private static func defaultRootURL(rootURL: URL?, fileManager: FileManager) -> URL {
        let baseURL = rootURL
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent("BookCoverCache", isDirectory: true)
    }

    private static func cacheFileURL(for url: URL, in rootURL: URL) -> URL {
        rootURL.appendingPathComponent("\(sha256Hex(url.absoluteString)).data", isDirectory: false)
    }
}

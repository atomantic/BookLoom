import Foundation

/// Extracts canonical Goodreads book URLs from raw URLs or text payloads
/// (e.g. share-sheet attachments which often arrive as either a `URL` or a
/// `String` from the iOS Goodreads app).
enum GoodreadsLinkExtractor {
    /// Returns a canonical `https://www.goodreads.com/book/show/<id>` URL when
    /// the input points to a Goodreads book, or `nil` otherwise.
    static func extract(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), host.contains("goodreads.com") else { return nil }
        guard let bookID = bookID(in: url.path) else { return nil }
        return URL(string: "https://www.goodreads.com/book/show/\(bookID)")
    }

    /// Searches arbitrary text for the first Goodreads book URL and returns
    /// it in canonical form. Useful when the share payload arrives as a
    /// pasted message ("Check out: https://www.goodreads.com/book/show/123").
    static func extract(fromText text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, let canonical = extract(from: url) {
                return canonical
            }
        }
        return nil
    }

    private static func bookID(in path: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "/book/show/(\\d+)") else { return nil }
        let range = NSRange(path.startIndex..., in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              let idRange = Range(match.range(at: 1), in: path) else {
            return nil
        }
        return String(path[idRange])
    }
}

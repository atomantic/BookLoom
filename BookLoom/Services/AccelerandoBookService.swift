import Foundation

struct DownloadedAccelerandoBook: Sendable {
    let text: String
    let sections: [RapidReaderSection]
    let loadedFromCache: Bool
}

enum AccelerandoBookError: LocalizedError, Equatable {
    case unavailable
    case invalidSource
    case invalidResponse
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Accelerando could not be downloaded from the author's site."
        case .invalidSource: return "The downloaded page was not a recognized Accelerando edition."
        case .invalidResponse: return "The Accelerando download returned an invalid response."
        case .tooLarge: return "The Accelerando download is larger than the allowed cache size."
        }
    }
}

struct AccelerandoBookService {
    static let maxSourceBytes = 2 * 1024 * 1024
    static let requestTimeout: TimeInterval = 20

    let urlSession: URLSession
    let cacheURL: URL

    init(urlSession: URLSession = .shared, cacheURL: URL? = nil) {
        self.urlSession = urlSession
        self.cacheURL = cacheURL ?? Self.defaultCacheURL()
    }

    func load() async throws -> DownloadedAccelerandoBook {
        if let cached = try? Data(contentsOf: cacheURL),
           cached.count <= Self.maxSourceBytes,
           let book = Self.extractBook(from: cached) {
            return DownloadedAccelerandoBook(text: book.text, sections: book.sections, loadedFromCache: true)
        }

        var request = URLRequest(url: AccelerandoBook.sourceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = Self.requestTimeout
        request.setValue("BookLoom-RapidReader/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AccelerandoBookError.unavailable
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AccelerandoBookError.invalidResponse
        }
        guard data.count <= Self.maxSourceBytes else {
            throw AccelerandoBookError.tooLarge
        }
        guard let book = Self.extractBook(from: data) else {
            throw AccelerandoBookError.invalidSource
        }

        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            return DownloadedAccelerandoBook(text: book.text, sections: book.sections, loadedFromCache: false)
        }
        return DownloadedAccelerandoBook(text: book.text, sections: book.sections, loadedFromCache: false)
    }

    /// Extracts only the official `#book` body and converts its simple HTML to
    /// readable text. The source is fixed in code, so this is not a general URL
    /// or HTML proxy; marker checks ensure an error page cannot be cached.
    static func extractText(from data: Data) -> String? {
        extractBook(from: data)?.text
    }

    static func extractSections(from data: Data) -> [RapidReaderSection] {
        extractBook(from: data)?.sections ?? []
    }

    private static func extractBook(from data: Data) -> (text: String, sections: [RapidReaderSection])? {
        let html = String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .utf8)
            ?? ""
        guard let body = extractBookBody(from: html) else { return nil }
        let text = plainText(from: body)
        let requiredMarkers = [
            "A novel by Charles Stross",
            "Creative Commons Attribution-NonCommercial-NoDerivs 2.5",
            "Chapter 1:"
        ]
        guard requiredMarkers.allSatisfy(text.contains) else { return nil }
        return (text: text, sections: sections(in: body, text: text))
    }

    private static func extractBookBody(from html: String) -> String? {
        guard let openRange = html.range(of: #"<div\b[^>]*\bid\s*=\s*(["'])book\1[^>]*>"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let bodyStart = openRange.upperBound
        guard let bodyEnd = html.range(of: "</div>", options: [.backwards, .caseInsensitive], range: bodyStart..<html.endIndex) else {
            return nil
        }
        return String(html[bodyStart..<bodyEnd.lowerBound])
    }

    private static func plainText(from source: String) -> String {
        var body = source
        body = body.replacingOccurrences(of: #"<!--(?s:.*?)-->"#, with: "", options: .regularExpression)
        body = body.replacingOccurrences(of: #"(?is)<(script|style|noscript)\b.*?</\1\s*>"#, with: "", options: .regularExpression)
        body = body.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        body = body.replacingOccurrences(of: #"(?i)</?(p|h[1-6]|li|tr)\b[^>]*>"#, with: "\n\n", options: .regularExpression)
        body = body.replacingOccurrences(of: #"(?i)<[^>]+>"#, with: "", options: .regularExpression)
        body = decodeEntities(body)

        let lines = body
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n\n")
    }

    private static func sections(in body: String, text: String) -> [RapidReaderSection] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<h[23]\b[^>]*>(.*?)</h[23]\s*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let bodyRange = NSRange(body.startIndex..<body.endIndex, in: body)
        let maxWordIndex = max(0, RapidReaderProgressStore.words(in: text).count - 1)
        return regex.matches(in: body, range: bodyRange).compactMap { match in
            guard let headingRange = Range(match.range, in: body),
                  let titleRange = Range(match.range(at: 1), in: body) else { return nil }
            let title = plainText(from: String(body[titleRange])).trimmed
            let lowercased = title.lowercased()
            let kind: RapidReaderSection.Kind
            if lowercased.hasPrefix("chapter") {
                kind = .chapter
            } else if lowercased.hasPrefix("part") {
                kind = .part
            } else {
                return nil
            }
            let beforeHeading = plainText(from: String(body[..<headingRange.lowerBound]))
            let wordIndex = min(RapidReaderProgressStore.words(in: beforeHeading).count, maxWordIndex)
            return RapidReaderSection(
                id: sectionID(title: title, index: match.range.location),
                title: title,
                kind: kind,
                wordIndex: wordIndex
            )
        }
    }

    private static func sectionID(title: String, index: Int) -> String {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(slug.isEmpty ? "section" : slug)-\(index)"
    }

    private static func decodeEntities(_ text: String) -> String {
        var decoded = text
        let entities = [
            "&amp;": "&", "&apos;": "'", "&copy;": "©", "&gt;": ">", "&lt;": "<",
            "&mdash;": "—", "&ndash;": "–", "&nbsp;": " ", "&quot;": "\"",
            "&ccedil;": "ç", "&ecirc;": "ê", "&eacute;": "é", "&egrave;": "è",
            "&igrave;": "ì", "&Mu;": "Μ", "&ograve;": "ò", "&ouml;": "ö", "&uuml;": "ü"
        ]
        for (entity, value) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: value)
        }
        let pattern = #"&#(x[0-9a-fA-F]+|[0-9]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return decoded }
        let range = NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)
        for match in regex.matches(in: decoded, range: range).reversed() {
            guard let entityRange = Range(match.range, in: decoded),
                  let valueRange = Range(match.range(at: 1), in: decoded) else { continue }
            let rawValue = String(decoded[valueRange])
            let scalarValue: UInt32?
            if rawValue.hasPrefix("x") {
                scalarValue = UInt32(rawValue.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(rawValue, radix: 10)
            }
            guard let scalarValue, let scalar = UnicodeScalar(scalarValue) else { continue }
            decoded.replaceSubrange(entityRange, with: String(scalar))
        }
        return decoded
    }

    private static func defaultCacheURL() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("BookLoom/Accelerando/accelerando.html")
    }
}

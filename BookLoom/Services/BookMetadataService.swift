import Foundation

enum BookMetadataProvider: String, Sendable, Equatable, Hashable, Codable {
    case openLibrary = "Open Library"
    case googleBooks = "Google Books"
    case goodreads = "Goodreads"

    var displayName: String { rawValue }

    static func openLibraryCoverURL(coverID: Int) -> URL? {
        URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-L.jpg?default=false")
    }
}

struct BookMetadataCandidate: Identifiable, Equatable, Hashable, Codable, Sendable {
    let provider: BookMetadataProvider
    let externalID: String
    let title: String
    let authors: [String]
    let publishedYear: Int?
    let isbn: String?
    let coverURL: URL?
    let description: String?
    let sourceURL: URL?

    var id: String { "\(provider.rawValue):\(externalID)" }

    var authorLine: String {
        authors.joined(separator: ", ")
    }

    var primaryISBN: String {
        isbn ?? ""
    }

    func merging(description: String?, coverURL: URL?) -> BookMetadataCandidate {
        BookMetadataCandidate(
            provider: provider,
            externalID: externalID,
            title: title,
            authors: authors,
            publishedYear: publishedYear,
            isbn: isbn,
            coverURL: self.coverURL ?? coverURL,
            description: self.description ?? description,
            sourceURL: sourceURL
        )
    }
}

enum BookMetadataError: LocalizedError {
    case missingTitle
    case invalidISBN
    case isbnNotFound
    case requestFailed
    case invalidURL
    case invalidGoodreadsURL
    case goodreadsParseFailed

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "Enter a title before searching."
        case .invalidISBN:
            return "That doesn't look like an ISBN. Scan or enter the ISBN barcode from the back of the book."
        case .isbnNotFound:
            return "Couldn't find book details for that ISBN. You can still enter the book manually."
        case .requestFailed:
            return "Book details are temporarily unavailable. The ISBN was scanned, so you can save it now or try details again later."
        case .invalidURL:
            return "Couldn't build a valid request for that search. Try adjusting the title or author."
        case .invalidGoodreadsURL:
            return "That doesn't look like a Goodreads book link. Paste a URL like https://www.goodreads.com/book/show/60233239."
        case .goodreadsParseFailed:
            return "Couldn't read the Goodreads page. Try entering the title and author manually."
        }
    }
}

struct BookMetadataService: Sendable {
    var urlSession: URLSession = .shared
    var cache: BookMetadataCache? = .shared
    private let openLibraryUserAgent = "BookLoom iOS (https://github.com/atomantic/BookLoom; net.shadowpuppet.PlotLoom)"

    init(urlSession: URLSession = .shared, cache: BookMetadataCache? = .shared) {
        self.urlSession = urlSession
        self.cache = cache
    }

    func search(title: String, author: String) async throws -> [BookMetadataCandidate] {
        let trimmedTitle = title.trimmed
        guard !trimmedTitle.isEmpty else { throw BookMetadataError.missingTitle }
        let trimmedAuthor = author.trimmed

        if let cache, let cached = await cache.cachedResults(title: trimmedTitle, author: trimmedAuthor) {
            return cached
        }

        let openLibrary = try await searchOpenLibrary(title: trimmedTitle, author: trimmedAuthor)
        var candidates = await enrichOpenLibraryCandidates(openLibrary)

        if candidates.prefix(3).allSatisfy({ ($0.description ?? "").isEmpty }) {
            let google = (try? await searchGoogleBooks(title: trimmedTitle, author: trimmedAuthor)) ?? []
            candidates.append(contentsOf: google.filter { candidate in
                !candidates.contains { existing in
                    normalized(existing.title) == normalized(candidate.title)
                        && normalized(existing.authorLine) == normalized(candidate.authorLine)
                }
            })
        }

        let results = ranked(candidates, title: trimmedTitle, author: trimmedAuthor)
        if let cache {
            await cache.store(results, title: trimmedTitle, author: trimmedAuthor)
        }
        return results
    }

    func lookupISBN(_ isbn: String) async throws -> BookMetadataCandidate {
        guard let cleanISBN = Self.normalizedISBN(isbn) else {
            throw BookMetadataError.invalidISBN
        }

        if let cache, let cached = await cache.cachedISBN(cleanISBN) {
            return cached
        }

        var reachedProvider = false
        var lastError: Error?

        do {
            let candidates = try await searchOpenLibraryByISBN(cleanISBN)
            reachedProvider = true
            if let candidate = await enrichOpenLibraryCandidates(candidates).first {
                if let cache {
                    await cache.store(candidate, isbn: cleanISBN)
                }
                return candidate
            }
        } catch {
            lastError = error
        }

        do {
            let candidates = try await searchGoogleBooksByISBN(cleanISBN)
            reachedProvider = true
            if let candidate = candidates.first {
                if let cache {
                    await cache.store(candidate, isbn: cleanISBN)
                }
                return candidate
            }
        } catch {
            lastError = error
        }

        if reachedProvider {
            throw BookMetadataError.isbnNotFound
        }
        throw lastError as? BookMetadataError ?? BookMetadataError.requestFailed
    }

    private func searchOpenLibrary(title: String, author: String) async throws -> [BookMetadataCandidate] {
        guard var components = URLComponents(string: "https://openlibrary.org/search.json") else {
            throw BookMetadataError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "author", value: author.isEmpty ? nil : author),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,cover_i,isbn"),
            URLQueryItem(name: "limit", value: "8")
        ].filter { $0.value != nil }

        guard let url = components.url else { throw BookMetadataError.invalidURL }
        let response: OpenLibrarySearchResponse = try await fetch(openLibraryRequest(url: url))
        return response.docs.compactMap(Self.openLibraryCandidate(from:))
    }

    private func searchOpenLibraryByISBN(_ isbn: String) async throws -> [BookMetadataCandidate] {
        guard var components = URLComponents(string: "https://openlibrary.org/search.json") else {
            throw BookMetadataError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "isbn", value: isbn),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,cover_i,isbn"),
            URLQueryItem(name: "limit", value: "3")
        ]

        guard let url = components.url else { throw BookMetadataError.invalidURL }
        let response: OpenLibrarySearchResponse = try await fetch(openLibraryRequest(url: url))
        return response.docs.compactMap(Self.openLibraryCandidate(from:))
    }

    private static func openLibraryCandidate(from doc: OpenLibrarySearchDoc) -> BookMetadataCandidate? {
        guard let key = doc.key, let title = doc.title?.trimmedOrNil else { return nil }
        let coverURL = doc.coverI.flatMap { BookMetadataProvider.openLibraryCoverURL(coverID: $0) }
        let externalID = key
            .replacingOccurrences(of: "/works/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return BookMetadataCandidate(
            provider: .openLibrary,
            externalID: externalID,
            title: title,
            authors: doc.authorName ?? [],
            publishedYear: doc.firstPublishYear,
            isbn: doc.isbn?.first,
            coverURL: coverURL,
            description: nil,
            sourceURL: URL(string: "https://openlibrary.org\(key)")
        )
    }

    private func enrichOpenLibraryCandidates(_ candidates: [BookMetadataCandidate]) async -> [BookMetadataCandidate] {
        let head = Array(candidates.prefix(5))
        let details: [OpenLibraryWorkDetail?] = await withTaskGroup(of: (Int, OpenLibraryWorkDetail?).self) { group in
            for (index, candidate) in head.enumerated() {
                group.addTask {
                    (index, try? await openLibraryWorkDetail(workID: candidate.externalID))
                }
            }
            var collected = Array<OpenLibraryWorkDetail?>(repeating: nil, count: head.count)
            for await (index, detail) in group {
                collected[index] = detail
            }
            return collected
        }

        let enriched = zip(head, details).map { candidate, detail in
            candidate.merging(
                description: detail?.description?.cleanedBookDescription,
                coverURL: detail?.covers?.first.flatMap { BookMetadataProvider.openLibraryCoverURL(coverID: $0) }
            )
        }
        return enriched + candidates.dropFirst(5)
    }

    private func openLibraryWorkDetail(workID: String) async throws -> OpenLibraryWorkDetail {
        guard let url = URL(string: "https://openlibrary.org/works/\(workID).json") else {
            throw BookMetadataError.invalidURL
        }
        return try await fetch(openLibraryRequest(url: url))
    }

    private func searchGoogleBooks(title: String, author: String) async throws -> [BookMetadataCandidate] {
        var query = "intitle:\(title)"
        if !author.isEmpty {
            query += " inauthor:\(author)"
        }
        return try await searchGoogleBooks(query: query, maxResults: 5)
    }

    private func searchGoogleBooksByISBN(_ isbn: String) async throws -> [BookMetadataCandidate] {
        try await searchGoogleBooks(query: "isbn:\(isbn)", maxResults: 1)
    }

    private func searchGoogleBooks(query: String, maxResults: Int) async throws -> [BookMetadataCandidate] {
        guard var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes") else {
            throw BookMetadataError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
            URLQueryItem(name: "printType", value: "books")
        ]

        guard let url = components.url else { throw BookMetadataError.invalidURL }
        let response: GoogleBooksResponse = try await fetch(url)
        return response.items?.compactMap { item in
            let info = item.volumeInfo
            guard let title = info.title?.trimmedOrNil else { return nil }
            return BookMetadataCandidate(
                provider: .googleBooks,
                externalID: item.id,
                title: title,
                authors: info.authors ?? [],
                publishedYear: Self.year(from: info.publishedDate),
                isbn: info.industryIdentifiers?.first { $0.type == "ISBN_13" }?.identifier
                    ?? info.industryIdentifiers?.first?.identifier,
                coverURL: Self.httpsURL(from: info.imageLinks?.thumbnail),
                description: info.description?.cleanedBookDescription,
                sourceURL: URL(string: "https://books.google.com/books?id=\(item.id)")
            )
        } ?? []
    }

    static func normalizedISBN(_ value: String) -> String? {
        let clean = value
            .uppercased()
            .filter { $0.isNumber || $0 == "X" }
            .map(String.init)
            .joined()

        if clean.count == 10 {
            return clean
        }
        if clean.count == 13, clean.hasPrefix("978") || clean.hasPrefix("979") {
            return clean
        }
        return nil
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BookMetadataError.requestFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func fetch<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BookMetadataError.requestFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func openLibraryRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(openLibraryUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func importFromGoodreads(url: URL) async throws -> BookMetadataCandidate {
        guard let bookID = Self.goodreadsBookID(from: url) else {
            throw BookMetadataError.invalidGoodreadsURL
        }

        guard let canonicalURL = URL(string: "https://www.goodreads.com/book/show/\(bookID)") else {
            throw BookMetadataError.invalidGoodreadsURL
        }
        var request = URLRequest(url: canonicalURL)
        // Goodreads serves a stripped/blocked response without a real browser UA.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw BookMetadataError.requestFailed
        }

        guard let candidate = Self.parseGoodreadsHTML(html, bookID: bookID, sourceURL: canonicalURL) else {
            throw BookMetadataError.goodreadsParseFailed
        }

        // Goodreads's og:description / JSON-LD are sometimes truncated (~200 chars).
        // If we ended up with a short description but have an ISBN, enrich from
        // Google Books — typically returns the full publisher description.
        if Self.descriptionNeedsEnrichment(candidate.description),
           let isbn = candidate.isbn?.trimmedOrNil,
           let enriched = try? await fetchDescription(byISBN: isbn),
           enriched.count > (candidate.description?.count ?? 0) {
            return BookMetadataCandidate(
                provider: candidate.provider,
                externalID: candidate.externalID,
                title: candidate.title,
                authors: candidate.authors,
                publishedYear: candidate.publishedYear,
                isbn: candidate.isbn,
                coverURL: candidate.coverURL,
                description: enriched,
                sourceURL: candidate.sourceURL
            )
        }

        return candidate
    }

    private static func descriptionNeedsEnrichment(_ description: String?) -> Bool {
        guard let description = description?.trimmed, !description.isEmpty else { return true }
        // Truncated og:description / JSON-LD blurbs are typically <250 chars or
        // end with an ellipsis. Above that, we trust Goodreads has the full text.
        if description.count < 250 { return true }
        if description.hasSuffix("…") || description.hasSuffix("...") { return true }
        return false
    }

    private func fetchDescription(byISBN isbn: String) async throws -> String? {
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "").trimmed
        guard !cleanISBN.isEmpty else { return nil }

        guard var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes") else {
            throw BookMetadataError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: "isbn:\(cleanISBN)"),
            URLQueryItem(name: "maxResults", value: "1")
        ]

        guard let url = components.url else { throw BookMetadataError.invalidURL }
        let response: GoogleBooksResponse = try await fetch(url)
        let description = response.items?.first?.volumeInfo.description?.cleanedBookDescription
        return description?.trimmedOrNil
    }

    static func goodreadsBookID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), host.contains("goodreads.com") else { return nil }
        let path = url.path
        guard let regex = try? NSRegularExpression(pattern: "/book/show/(\\d+)") else { return nil }
        let range = NSRange(path.startIndex..., in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              let idRange = Range(match.range(at: 1), in: path) else {
            return nil
        }
        return String(path[idRange])
    }

    static func parseGoodreadsHTML(_ html: String, bookID: String, sourceURL: URL) -> BookMetadataCandidate? {
        var title: String?
        var authors: [String] = []
        var isbn: String?
        var coverURL: URL?
        var description: String?
        var publishedYear: Int?

        for blob in jsonLDBlobs(in: html) {
            guard let data = blob.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            for book in goodreadsBookObjects(in: object) {
                if title == nil, let value = book["name"] as? String, !value.isEmpty {
                    title = value.htmlDecoded
                }
                if authors.isEmpty {
                    authors = goodreadsAuthors(from: book["author"])
                }
                if isbn == nil, let value = book["isbn"] as? String, !value.isEmpty {
                    isbn = value
                }
                if coverURL == nil, let value = book["image"] as? String, let url = URL(string: value) {
                    coverURL = url
                }
                if let value = book["description"] as? String, !value.isEmpty {
                    let cleaned = value.cleanedBookDescription
                    if (description?.count ?? 0) < cleaned.count {
                        description = cleaned
                    }
                }
                if publishedYear == nil, let value = book["datePublished"] as? String {
                    publishedYear = Self.year(from: value)
                }
            }
        }

        // Goodreads's full description lives in the Apollo cache embedded in
        // __NEXT_DATA__. JSON-LD's `description` field is sometimes the same
        // truncated text as og:description (~200 chars), so prefer the longer
        // value found anywhere under a key containing "description".
        if let fuller = longestDescription(inNextData: html), fuller.count > (description?.count ?? 0) {
            description = fuller
        }

        if title == nil {
            title = metaContent(in: html, property: "og:title")?.htmlDecoded
        }
        if coverURL == nil, let value = metaContent(in: html, property: "og:image"), let url = URL(string: value) {
            coverURL = url
        }
        if description == nil {
            description = (metaContent(in: html, property: "og:description")
                ?? metaContent(in: html, name: "description"))?
                .htmlDecoded.cleanedBookDescription
        }
        if isbn == nil {
            isbn = metaContent(in: html, property: "books:isbn")
        }

        guard let resolvedTitle = title?.trimmedOrNil else { return nil }

        return BookMetadataCandidate(
            provider: .goodreads,
            externalID: bookID,
            title: resolvedTitle,
            authors: authors,
            publishedYear: publishedYear,
            isbn: isbn?.trimmedOrNil,
            coverURL: coverURL,
            description: description?.trimmedOrNil,
            sourceURL: sourceURL
        )
    }

    // Walk the __NEXT_DATA__ JSON tree and return the longest string found
    // under any key containing "description". Goodreads stores the full
    // description in the Apollo cache under encoded GraphQL keys like
    // `description({"stripped":true})`, so we match by substring.
    private static func longestDescription(inNextData html: String) -> String? {
        guard let blob = nextDataBlob(in: html),
              let data = blob.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        var longest: String?
        collectDescriptionStrings(from: json, into: &longest)
        return longest?.cleanedBookDescription.trimmedOrNil
    }

    private static func nextDataBlob(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<script[^>]*id=\"__NEXT_DATA__\"[^>]*>([\\s\\S]*?)</script>",
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let r = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[r])
    }

    private static func collectDescriptionStrings(from json: Any, into longest: inout String?) {
        if let array = json as? [Any] {
            for value in array {
                collectDescriptionStrings(from: value, into: &longest)
            }
            return
        }
        guard let dict = json as? [String: Any] else { return }
        for (key, value) in dict {
            if key.lowercased().contains("description"), let stringValue = value as? String {
                let stripped = stripHTMLTags(stringValue).htmlDecoded.trimmed
                if stripped.count > (longest?.count ?? 0) {
                    longest = stripped
                }
            } else {
                collectDescriptionStrings(from: value, into: &longest)
            }
        }
    }

    private static func stripHTMLTags(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>") else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
    }

    private static func jsonLDBlobs(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "<script[^>]*type=\"application/ld\\+json\"[^>]*>([\\s\\S]*?)</script>",
            options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[r])
        }
    }

    private static func goodreadsBookObjects(in json: Any) -> [[String: Any]] {
        if let array = json as? [Any] {
            return array.flatMap { goodreadsBookObjects(in: $0) }
        }
        guard let dict = json as? [String: Any] else { return [] }
        if let type = dict["@type"] as? String, type.caseInsensitiveCompare("Book") == .orderedSame {
            return [dict]
        }
        if let graph = dict["@graph"] {
            return goodreadsBookObjects(in: graph)
        }
        return []
    }

    private static func goodreadsAuthors(from value: Any?) -> [String] {
        if let array = value as? [Any] {
            return array.flatMap { goodreadsAuthors(from: $0) }
        }
        if let dict = value as? [String: Any], let name = dict["name"] as? String {
            return [name.htmlDecoded]
        }
        if let name = value as? String, !name.isEmpty {
            return [name.htmlDecoded]
        }
        return []
    }

    private static func metaContent(in html: String, property: String? = nil, name: String? = nil) -> String? {
        let key: String
        let attr: String
        if let property {
            key = property
            attr = "property"
        } else if let name {
            key = name
            attr = "name"
        } else {
            return nil
        }

        let pattern = "<meta[^>]*\(attr)=\"\(NSRegularExpression.escapedPattern(for: key))\"[^>]*content=\"([^\"]*)\""
        let altPattern = "<meta[^>]*content=\"([^\"]*)\"[^>]*\(attr)=\"\(NSRegularExpression.escapedPattern(for: key))\""
        for candidate in [pattern, altPattern] {
            guard let regex = try? NSRegularExpression(pattern: candidate, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let r = Range(match.range(at: 1), in: html) {
                let raw = String(html[r])
                return raw.isEmpty ? nil : raw
            }
        }
        return nil
    }


    private func ranked(_ candidates: [BookMetadataCandidate], title: String, author: String) -> [BookMetadataCandidate] {
        candidates
            .sorted { score($0, title: title, author: author) > score($1, title: title, author: author) }
            .prefix(8)
            .map { $0 }
    }

    private func score(_ candidate: BookMetadataCandidate, title: String, author: String) -> Int {
        let wantedTitle = normalized(title)
        let foundTitle = normalized(candidate.title)
        let wantedAuthor = normalized(author)
        let foundAuthor = normalized(candidate.authorLine)

        var score = 0
        if foundTitle == wantedTitle {
            score += 100
        } else if foundTitle.hasPrefix(wantedTitle) || wantedTitle.hasPrefix(foundTitle) {
            score += 55
        } else if foundTitle.contains(wantedTitle) || wantedTitle.contains(foundTitle) {
            score += 30
        }

        if !wantedAuthor.isEmpty {
            if foundAuthor == wantedAuthor {
                score += 60
            } else if foundAuthor.contains(wantedAuthor) || wantedAuthor.contains(foundAuthor) {
                score += 30
            }
        }

        if candidate.coverURL != nil { score += 10 }
        if !(candidate.description ?? "").isEmpty { score += 10 }
        if candidate.provider == .openLibrary { score += 3 }
        return score
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func year(from value: String?) -> Int? {
        guard let value, value.count >= 4 else { return nil }
        return Int(value.prefix(4))
    }

    private static func httpsURL(from value: String?) -> URL? {
        guard var value, !value.isEmpty else { return nil }
        if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        }
        return URL(string: value)
    }
}

private struct OpenLibrarySearchResponse: Decodable {
    let docs: [OpenLibrarySearchDoc]
}

private struct OpenLibrarySearchDoc: Decodable {
    let key: String?
    let title: String?
    let authorName: [String]?
    let firstPublishYear: Int?
    let coverI: Int?
    let isbn: [String]?

    private enum CodingKeys: String, CodingKey {
        case key
        case title
        case authorName = "author_name"
        case firstPublishYear = "first_publish_year"
        case coverI = "cover_i"
        case isbn
    }
}

private struct OpenLibraryWorkDetail: Decodable {
    let description: FlexibleString?
    let covers: [Int]?
}

private struct GoogleBooksResponse: Decodable {
    let items: [GoogleBookItem]?
}

private struct GoogleBookItem: Decodable {
    let id: String
    let volumeInfo: GoogleVolumeInfo
}

private struct GoogleVolumeInfo: Decodable {
    let title: String?
    let authors: [String]?
    let publishedDate: String?
    let description: String?
    let imageLinks: GoogleImageLinks?
    let industryIdentifiers: [GoogleIndustryIdentifier]?
}

private struct GoogleImageLinks: Decodable {
    let thumbnail: String?
}

private struct GoogleIndustryIdentifier: Decodable {
    let type: String
    let identifier: String
}

private enum FlexibleString: Decodable {
    case string(String)
    case object(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        let object = try container.decode(DescriptionObject.self)
        self = .object(object.value)
    }

    var value: String {
        switch self {
        case .string(let value), .object(let value):
            value
        }
    }
}

private struct DescriptionObject: Decodable {
    let value: String
}

private extension FlexibleString {
    var cleanedBookDescription: String? {
        value.cleanedBookDescription
    }
}

private extension String {
    var cleanedBookDescription: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmed
    }

    // Decodes a small set of common HTML/XML entities surfaced by Goodreads JSON-LD
    // (titles like "Babel: An Arcane History" don't usually need decoding, but
    // apostrophes/quotes do: &#39; &amp; &quot; &lt; &gt; &nbsp; &#x27;).
    var htmlDecoded: String {
        var result = self
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&#x27;", "'"),
            ("&#x2019;", "\u{2019}"),
            ("&#8217;", "\u{2019}"),
            ("&#8216;", "\u{2018}"),
            ("&#8220;", "\u{201C}"),
            ("&#8221;", "\u{201D}"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " "),
            ("&mdash;", "\u{2014}"),
            ("&ndash;", "\u{2013}"),
            ("&hellip;", "\u{2026}")
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}

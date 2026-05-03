import Foundation

enum BookMetadataProvider: String, Sendable, Equatable, Hashable, Codable {
    case openLibrary = "Open Library"
    case googleBooks = "Google Books"

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
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "Enter a title before searching."
        case .requestFailed:
            return "Couldn't search for book details. Check your connection and try again."
        }
    }
}

struct BookMetadataService: Sendable {
    var urlSession: URLSession = .shared
    var cache: BookMetadataCache? = .shared

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

    private func searchOpenLibrary(title: String, author: String) async throws -> [BookMetadataCandidate] {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "author", value: author.isEmpty ? nil : author),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,cover_i,isbn"),
            URLQueryItem(name: "limit", value: "8")
        ].filter { $0.value != nil }

        let response: OpenLibrarySearchResponse = try await fetch(components.url!)
        return response.docs.compactMap { doc in
            guard let key = doc.key, let title = doc.title?.trimmedOrNil else { return nil }
            let coverURL = doc.coverI.flatMap { BookMetadataProvider.openLibraryCoverURL(coverID: $0) }
            let workID = key.replacingOccurrences(of: "/works/", with: "")
            return BookMetadataCandidate(
                provider: .openLibrary,
                externalID: workID,
                title: title,
                authors: doc.authorName ?? [],
                publishedYear: doc.firstPublishYear,
                isbn: doc.isbn?.first,
                coverURL: coverURL,
                description: nil,
                sourceURL: URL(string: "https://openlibrary.org\(key)")
            )
        }
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
        try await fetch(URL(string: "https://openlibrary.org/works/\(workID).json")!)
    }

    private func searchGoogleBooks(title: String, author: String) async throws -> [BookMetadataCandidate] {
        var query = "intitle:\(title)"
        if !author.isEmpty {
            query += " inauthor:\(author)"
        }

        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "5"),
            URLQueryItem(name: "printType", value: "books")
        ]

        let response: GoogleBooksResponse = try await fetch(components.url!)
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

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BookMetadataError.requestFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
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
}

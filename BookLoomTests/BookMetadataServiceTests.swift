import Foundation
import XCTest
@testable import BookLoom

final class BookMetadataServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.responses = [:]
    }

    func test_searchReturnsRankedOpenLibraryMetadataWithDescriptionAndCover() async throws {
        MockURLProtocol.responses = [
            "https://openlibrary.org/search.json?title=Hyperion&author=Dan%20Simmons&fields=key,title,author_name,first_publish_year,cover_i,isbn&limit=8": """
            {
              "docs": [
                {
                  "key": "/works/OL1963251W",
                  "title": "The Fall of Hyperion",
                  "author_name": ["Dan Simmons"],
                  "first_publish_year": 1990,
                  "cover_i": 484900,
                  "isbn": ["9780575099937"]
                },
                {
                  "key": "/works/OL1963268W",
                  "title": "Hyperion",
                  "author_name": ["Dan Simmons"],
                  "first_publish_year": 1989,
                  "cover_i": 380332,
                  "isbn": ["9780553283686"]
                }
              ]
            }
            """.data(using: .utf8)!,
            "https://openlibrary.org/works/OL1963251W.json": """
            {"description": "Second book.", "covers": [484900]}
            """.data(using: .utf8)!,
            "https://openlibrary.org/works/OL1963268W.json": """
            {"description": {"value": "**The Hyperion Cantos begins.**"}, "covers": [380332]}
            """.data(using: .utf8)!
        ]

        let service = BookMetadataService(urlSession: .mocked, cache: nil)
        let results = try await service.search(title: "Hyperion", author: "Dan Simmons")

        XCTAssertEqual(results.first?.title, "Hyperion")
        XCTAssertEqual(results.first?.authorLine, "Dan Simmons")
        XCTAssertEqual(results.first?.publishedYear, 1989)
        XCTAssertEqual(results.first?.isbn, "9780553283686")
        XCTAssertEqual(results.first?.description, "The Hyperion Cantos begins.")
        XCTAssertEqual(results.first?.coverURL?.absoluteString, "https://covers.openlibrary.org/b/id/380332-L.jpg?default=false")
    }

    func test_submissionPersistsImportedMetadataFields() throws {
        let submission = BookSubmission(
            title: "Piranesi",
            author: "Susanna Clarke",
            isbn: "9781635575637",
            bookDescription: "A labyrinthine novel.",
            publishedYear: 2020,
            coverURL: "https://covers.openlibrary.org/b/id/10226290-L.jpg?default=false",
            externalProvider: "Open Library",
            externalID: "OL20893680W",
            submittedBy: "Alex"
        )

        XCTAssertEqual(submission.bookDescription, "A labyrinthine novel.")
        XCTAssertEqual(submission.publishedYear, 2020)
        XCTAssertEqual(submission.coverImageURL?.host(), "covers.openlibrary.org")
        XCTAssertEqual(submission.externalProvider, "Open Library")
        XCTAssertEqual(submission.externalID, "OL20893680W")
    }

    func test_goodreadsBookID_extractsIDFromVariousURLShapes() {
        XCTAssertEqual(
            BookMetadataService.goodreadsBookID(from: URL(string: "https://www.goodreads.com/book/show/60233239")!),
            "60233239"
        )
        XCTAssertEqual(
            BookMetadataService.goodreadsBookID(from: URL(string: "https://www.goodreads.com/book/show/60233239-babel")!),
            "60233239"
        )
        XCTAssertEqual(
            BookMetadataService.goodreadsBookID(from: URL(string: "https://goodreads.com/book/show/12345-some-slug?utm=foo")!),
            "12345"
        )
        XCTAssertNil(
            BookMetadataService.goodreadsBookID(from: URL(string: "https://www.goodreads.com/author/show/123")!)
        )
        XCTAssertNil(
            BookMetadataService.goodreadsBookID(from: URL(string: "https://example.com/book/show/60233239")!)
        )
    }

    func test_parseGoodreadsHTML_pullsTitleAuthorISBNCoverDescriptionFromJSONLD() throws {
        let html = """
        <html><head>
        <meta property="og:title" content="Babel: An Arcane History"/>
        <meta property="og:image" content="https://example.com/og-cover.jpg"/>
        <meta name="description" content="Falls into a tale of language and empire."/>
        <script type="application/ld+json">
        {
          "@context":"https://schema.org",
          "@type":"Book",
          "name":"Babel: Or the Necessity of Violence",
          "image":"https://example.com/cover.jpg",
          "isbn":"0063021420",
          "datePublished":"2022-08-23",
          "author":[{"@type":"Person","name":"R.F. Kuang"}],
          "description":"An incandescent novel about translation, power, and revolution."
        }
        </script>
        </head><body></body></html>
        """

        let candidate = BookMetadataService.parseGoodreadsHTML(
            html,
            bookID: "60233239",
            sourceURL: URL(string: "https://www.goodreads.com/book/show/60233239")!
        )

        XCTAssertEqual(candidate?.provider, .goodreads)
        XCTAssertEqual(candidate?.externalID, "60233239")
        XCTAssertEqual(candidate?.title, "Babel: Or the Necessity of Violence")
        XCTAssertEqual(candidate?.authors, ["R.F. Kuang"])
        XCTAssertEqual(candidate?.isbn, "0063021420")
        XCTAssertEqual(candidate?.publishedYear, 2022)
        XCTAssertEqual(candidate?.coverURL?.absoluteString, "https://example.com/cover.jpg")
        XCTAssertEqual(candidate?.description, "An incandescent novel about translation, power, and revolution.")
    }

    func test_parseGoodreadsHTML_fallsBackToOpenGraphWhenJSONLDIsMissing() throws {
        let html = """
        <html><head>
        <meta property="og:title" content="Some Book Title"/>
        <meta property="og:image" content="https://example.com/cover.jpg"/>
        <meta property="og:description" content="A great read."/>
        <meta property="books:isbn" content="9781234567890"/>
        </head><body></body></html>
        """

        let candidate = BookMetadataService.parseGoodreadsHTML(
            html,
            bookID: "999",
            sourceURL: URL(string: "https://www.goodreads.com/book/show/999")!
        )

        XCTAssertEqual(candidate?.title, "Some Book Title")
        XCTAssertEqual(candidate?.coverURL?.absoluteString, "https://example.com/cover.jpg")
        XCTAssertEqual(candidate?.isbn, "9781234567890")
        XCTAssertEqual(candidate?.description, "A great read.")
    }

    func test_parseGoodreadsHTML_decodesAmpersandsAndApostrophesInTitleAndAuthor() throws {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context":"https://schema.org",
          "@type":"Book",
          "name":"Tom &amp; Jerry's Big Day",
          "author":[{"@type":"Person","name":"Jane O&#39;Hara"}]
        }
        </script>
        </head></html>
        """

        let candidate = BookMetadataService.parseGoodreadsHTML(
            html,
            bookID: "1",
            sourceURL: URL(string: "https://www.goodreads.com/book/show/1")!
        )

        XCTAssertEqual(candidate?.title, "Tom & Jerry's Big Day")
        XCTAssertEqual(candidate?.authors, ["Jane O'Hara"])
    }

    func test_importFromGoodreads_fetchesAndParsesPage() async throws {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context":"https://schema.org",
          "@type":"Book",
          "name":"Imported Book",
          "image":"https://example.com/cover.jpg",
          "isbn":"9780000000001",
          "author":[{"@type":"Person","name":"Author One"}]
        }
        </script>
        </head></html>
        """

        MockURLProtocol.responses = [
            "https://www.goodreads.com/book/show/60233239": html.data(using: .utf8)!
        ]

        let service = BookMetadataService(urlSession: .mocked, cache: nil)
        let candidate = try await service.importFromGoodreads(
            url: URL(string: "https://www.goodreads.com/book/show/60233239-babel")!
        )

        XCTAssertEqual(candidate.title, "Imported Book")
        XCTAssertEqual(candidate.authors, ["Author One"])
        XCTAssertEqual(candidate.isbn, "9780000000001")
        XCTAssertEqual(candidate.coverURL?.absoluteString, "https://example.com/cover.jpg")
        XCTAssertEqual(candidate.provider, .goodreads)
    }

    func test_parseGoodreadsHTML_prefersLongerNextDataDescriptionOverJSONLD() throws {
        let truncated = "A masterful tale of language and revolution."
        let full = String(repeating: "Lorem ipsum dolor sit amet consectetur. ", count: 25)
            + "An incandescent novel about translation, power, and revolution."
        let nextDataJSON = """
        {"props":{"pageProps":{"apolloState":{
            "Book:kca:abc": {
                "__typename": "Book",
                "title": "Babel",
                "description({\\"stripped\\":true})": "\(full)"
            }
        }}}}
        """
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Book","name":"Babel","author":[{"@type":"Person","name":"R.F. Kuang"}],"description":"\(truncated)","isbn":"0063021420"}
        </script>
        <script id="__NEXT_DATA__" type="application/json">\(nextDataJSON)</script>
        </head></html>
        """

        let candidate = BookMetadataService.parseGoodreadsHTML(
            html,
            bookID: "60233239",
            sourceURL: URL(string: "https://www.goodreads.com/book/show/60233239")!
        )

        XCTAssertEqual(candidate?.description, full)
        XCTAssertGreaterThan(candidate?.description?.count ?? 0, truncated.count)
    }

    func test_parseGoodreadsHTML_stripsHTMLAndDecodesEntitiesInNextDataDescription() throws {
        let nextDataJSON = """
        {"props":{"pageProps":{"apolloState":{
            "Book:kca:xyz": {
                "description": "<p>Once upon a time &amp; long ago, there was a world.</p><p>Then it changed.</p>"
            }
        }}}}
        """
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Book","name":"Some Book"}
        </script>
        <script id="__NEXT_DATA__" type="application/json">\(nextDataJSON)</script>
        </head></html>
        """

        let candidate = BookMetadataService.parseGoodreadsHTML(
            html,
            bookID: "1",
            sourceURL: URL(string: "https://www.goodreads.com/book/show/1")!
        )

        XCTAssertEqual(candidate?.description, "Once upon a time & long ago, there was a world.Then it changed.")
    }

    func test_importFromGoodreads_fillsShortDescriptionFromGoogleBooksByISBN() async throws {
        let goodreadsHTML = """
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Book","name":"Imported Book","isbn":"9780000000001","description":"Short blurb…","author":[{"@type":"Person","name":"Author One"}]}
        </script>
        </head></html>
        """
        let fullDescription = String(repeating: "Full publisher description sentence. ", count: 20)
        let googleResponse = """
        {"items":[{"id":"abc123","volumeInfo":{"title":"Imported Book","authors":["Author One"],"description":"\(fullDescription)","industryIdentifiers":[{"type":"ISBN_13","identifier":"9780000000001"}]}}]}
        """

        MockURLProtocol.responses = [
            "https://www.goodreads.com/book/show/60233239": goodreadsHTML.data(using: .utf8)!,
            "https://www.googleapis.com/books/v1/volumes?q=isbn:9780000000001&maxResults=1": googleResponse.data(using: .utf8)!
        ]

        let service = BookMetadataService(urlSession: .mocked, cache: nil)
        let candidate = try await service.importFromGoodreads(
            url: URL(string: "https://www.goodreads.com/book/show/60233239-imported")!
        )

        XCTAssertEqual(candidate.title, "Imported Book")
        XCTAssertEqual(candidate.isbn, "9780000000001")
        XCTAssertEqual(candidate.provider, .goodreads)
        XCTAssertEqual(candidate.description, fullDescription.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertGreaterThan(candidate.description?.count ?? 0, "Short blurb…".count)
    }

    func test_importFromGoodreads_keepsFullGoodreadsDescriptionWithoutEnrichment() async throws {
        let fullDescription = String(repeating: "A long full description from Goodreads itself. ", count: 12)
        let goodreadsHTML = """
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Book","name":"Self-Sufficient Book","isbn":"9780000000002","description":"\(fullDescription)","author":[{"@type":"Person","name":"A. Author"}]}
        </script>
        </head></html>
        """

        MockURLProtocol.responses = [
            "https://www.goodreads.com/book/show/777": goodreadsHTML.data(using: .utf8)!
        ]

        let service = BookMetadataService(urlSession: .mocked, cache: nil)
        let candidate = try await service.importFromGoodreads(
            url: URL(string: "https://www.goodreads.com/book/show/777")!
        )

        XCTAssertEqual(candidate.description, fullDescription.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func test_importFromGoodreads_rejectsNonGoodreadsURL() async {
        let service = BookMetadataService(urlSession: .mocked, cache: nil)
        do {
            _ = try await service.importFromGoodreads(url: URL(string: "https://example.com/book/show/123")!)
            XCTFail("Expected invalidGoodreadsURL error")
        } catch let error as BookMetadataError {
            switch error {
            case .invalidGoodreadsURL: break
            default: XCTFail("Unexpected BookMetadataError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_searchUsesCachedMetadataWhenNetworkIsUnavailable() async throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLoomMetadataCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        MockURLProtocol.responses = [
            "https://openlibrary.org/search.json?title=Piranesi&author=Susanna%20Clarke&fields=key,title,author_name,first_publish_year,cover_i,isbn&limit=8": """
            {
              "docs": [
                {
                  "key": "/works/OL20893680W",
                  "title": "Piranesi",
                  "author_name": ["Susanna Clarke"],
                  "first_publish_year": 2020,
                  "cover_i": 10226290,
                  "isbn": ["9781635575637"]
                }
              ]
            }
            """.data(using: .utf8)!,
            "https://openlibrary.org/works/OL20893680W.json": """
            {"description": "A labyrinthine novel.", "covers": [10226290]}
            """.data(using: .utf8)!
        ]

        let cache = BookMetadataCache(rootURL: cacheURL)
        let service = BookMetadataService(urlSession: .mocked, cache: cache)
        let first = try await service.search(title: "Piranesi", author: "Susanna Clarke")
        MockURLProtocol.responses = [:]
        let second = try await service.search(title: "Piranesi", author: "Susanna Clarke")

        XCTAssertEqual(second, first)
        XCTAssertEqual(second.first?.description, "A labyrinthine novel.")
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let data = Self.responses[url.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSession {
    static var mocked: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

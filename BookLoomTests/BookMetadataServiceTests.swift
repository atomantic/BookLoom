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

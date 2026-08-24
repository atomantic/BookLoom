import Foundation
import XCTest
@testable import BookLoom

final class GoodreadsLinkExtractorTests: XCTestCase {
    func test_canonicalizesShortBookURL() throws {
        let url = URL(string: "https://www.goodreads.com/book/show/60233239")!
        XCTAssertEqual(
            GoodreadsLinkExtractor.extract(from: url)?.absoluteString,
            "https://www.goodreads.com/book/show/60233239"
        )
    }

    func test_canonicalizesURLWithSlugAndQuery() throws {
        let url = URL(string: "https://www.goodreads.com/book/show/60233239-babel?ref=share")!
        XCTAssertEqual(
            GoodreadsLinkExtractor.extract(from: url)?.absoluteString,
            "https://www.goodreads.com/book/show/60233239"
        )
    }

    func test_acceptsNonWWWHost() throws {
        let url = URL(string: "https://goodreads.com/book/show/12345")!
        XCTAssertEqual(
            GoodreadsLinkExtractor.extract(from: url)?.absoluteString,
            "https://www.goodreads.com/book/show/12345"
        )
    }

    func test_rejectsNonGoodreadsURL() throws {
        let url = URL(string: "https://www.amazon.com/dp/B09RM2FCMP")!
        XCTAssertNil(GoodreadsLinkExtractor.extract(from: url))
    }

    func test_rejectsGoodreadsHostWithoutBookPath() throws {
        let url = URL(string: "https://www.goodreads.com/user/show/12345")!
        XCTAssertNil(GoodreadsLinkExtractor.extract(from: url))
    }

    func test_extractsURLEmbeddedInText() throws {
        let text = "Check this out: https://www.goodreads.com/book/show/60233239-babel — really good"
        XCTAssertEqual(
            GoodreadsLinkExtractor.extract(fromText: text)?.absoluteString,
            "https://www.goodreads.com/book/show/60233239"
        )
    }

    func test_returnsNilWhenTextHasNoGoodreadsURL() throws {
        XCTAssertNil(GoodreadsLinkExtractor.extract(fromText: "no link here"))
        XCTAssertNil(GoodreadsLinkExtractor.extract(fromText: "https://example.com"))
    }
}

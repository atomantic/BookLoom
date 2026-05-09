import Foundation
import XCTest
@testable import BookLoom

final class BookCoverCacheManualTests: XCTestCase {
    private var tempRoot: URL!
    private var tempManualRoot: URL!
    private var cache: BookCoverCache!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookCoverCacheTests-\(UUID().uuidString)", isDirectory: true)
        tempRoot = base.appendingPathComponent("remote", isDirectory: true)
        tempManualRoot = base.appendingPathComponent("manual", isDirectory: true)
        cache = BookCoverCache(rootURL: tempRoot, manualRootURL: tempManualRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot.deletingLastPathComponent())
        super.tearDown()
    }

    func test_manualCoverURL_buildsExpectedSyntheticURL() {
        let url = BookCoverCache.manualCoverURL(identifier: "ABC-123")
        XCTAssertEqual(url.scheme, "bookloom")
        XCTAssertEqual(url.host, "manual-cover")
        XCTAssertEqual(url.lastPathComponent, "ABC-123")
        XCTAssertTrue(BookCoverCache.isManualCoverURL(url))
    }

    func test_manualCoverURL_sanitizesPathComponents() {
        let url = BookCoverCache.manualCoverURL(identifier: "../../etc/passwd")
        XCTAssertTrue(BookCoverCache.isManualCoverURL(url))
        XCTAssertFalse(url.path.contains("/etc/"))
    }

    func test_isManualCoverURL_rejectsRemoteURLs() {
        let remote = URL(string: "https://covers.openlibrary.org/b/id/123-L.jpg")!
        XCTAssertFalse(BookCoverCache.isManualCoverURL(remote))
    }

    func test_storeManual_persistsBytesAndReturnsSyntheticURL() async {
        let bytes = Data(repeating: 0xAB, count: 1024)
        let returned = await cache.storeManual(data: bytes, identifier: "submission-1")
        XCTAssertNotNil(returned)
        XCTAssertEqual(returned?.scheme, "bookloom")

        let retrieved = await cache.cachedData(for: returned!)
        XCTAssertEqual(retrieved, bytes)
    }

    func test_storeManual_rejectsTooLargeData() async {
        let oversized = Data(repeating: 0x00, count: 800 * 1024)
        let returned = await cache.storeManual(data: oversized, identifier: "submission-2")
        XCTAssertNil(returned)
    }

    func test_storeManual_rejectsEmptyData() async {
        let returned = await cache.storeManual(data: Data(), identifier: "submission-3")
        XCTAssertNil(returned)
    }

    func test_removeManual_removesPersistedBytes() async {
        let bytes = Data(repeating: 0xCC, count: 2048)
        let url = await cache.storeManual(data: bytes, identifier: "submission-4")
        XCTAssertNotNil(url)

        await cache.removeManual(identifier: "submission-4")

        let retrieved = await cache.cachedData(for: url!)
        XCTAssertNil(retrieved)
    }

    func test_data_returnsNilForMissingManualCoverWithoutNetworking() async {
        let url = BookCoverCache.manualCoverURL(identifier: "never-stored")
        let result = await cache.data(for: url)
        XCTAssertNil(result)
    }

    func test_data_returnsStoredBytesForManualCover() async {
        let bytes = Data(repeating: 0x10, count: 4096)
        let url = await cache.storeManual(data: bytes, identifier: "submission-5")
        XCTAssertNotNil(url)

        let result = await cache.data(for: url!)
        XCTAssertEqual(result, bytes)
    }

    func test_purgeAll_clearsManualAndRemoteRoots() async {
        let manualURL = await cache.storeManual(data: Data(repeating: 1, count: 64), identifier: "submission-6")
        XCTAssertNotNil(manualURL)

        await cache.purgeAll()

        let result = await cache.cachedData(for: manualURL!)
        XCTAssertNil(result)
    }
}

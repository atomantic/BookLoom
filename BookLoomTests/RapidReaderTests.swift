import SwiftData
import XCTest
@testable import BookLoom

final class RapidReaderTests: XCTestCase {
    func test_accelerandoHTMLExtractionKeepsBookTextAndRemovesNonContent() throws {
        let html = """
        <html><body><div id="book">
        <p>A novel by Charles Stross</p>
        <script>alert('not book text')</script>
        <p>Copyright &copy; Charles Stross</p>
        <p>This work is licensed under a Creative Commons Attribution-NonCommercial-NoDerivs 2.5 License.</p>
        <h3>Chapter 1:</h3><p>Start &mdash; here.</p>
        </div></body></html>
        """

        let text = try XCTUnwrap(AccelerandoBookService.extractText(from: Data(html.utf8)))
        XCTAssertTrue(text.contains("A novel by Charles Stross"))
        XCTAssertTrue(text.contains("Copyright © Charles Stross"))
        XCTAssertTrue(text.contains("Chapter 1:"))
        XCTAssertTrue(text.contains("Start — here."))
        XCTAssertFalse(text.contains("not book text"))
    }

    func test_readerWordsFoldDanglingPunctuationIntoReadableFrames() {
        XCTAssertEqual(
            RapidReaderProgressStore.words(in: #"She said " hello," then paused…"#),
            ["She", "said", #""hello,""#, "then", "paused…"]
        )
        XCTAssertEqual(
            RapidReaderProgressStore.words(in: "wait — really?"),
            ["wait—", "really?"]
        )
    }

    func test_accelerandoSectionsUseReaderWordOffsets() throws {
        let html = """
        <header>site masthead</header>
        <div id="book">
        <p>A novel by Charles Stross</p>
        <p>Creative Commons Attribution-NonCommercial-NoDerivs 2.5</p>
        <h2><a name="PART1">PART 1: Start</a></h2>
        <p>Opening text.</p>
        <h3><a name="ChapterOne">Chapter 1: Alpha</a></h3>
        <p>Chapter text.</p>
        </div>
        """

        let data = Data(html.utf8)
        let text = try XCTUnwrap(AccelerandoBookService.extractText(from: data))
        let sections = AccelerandoBookService.extractSections(from: data)

        XCTAssertEqual(sections.map(\.title), ["PART 1: Start", "Chapter 1: Alpha"])
        XCTAssertEqual(sections.map(\.kind), [.part, .chapter])
        XCTAssertEqual(sections.first?.wordIndex, 9)
        XCTAssertEqual(sections.last?.wordIndex, 14)
        XCTAssertEqual(RapidReaderProgressStore.words(in: text)[sections.last?.wordIndex ?? 0], "Chapter")
    }

    func test_accelerandoHTMLExtractionRejectsUnrecognizedPage() {
        XCTAssertNil(AccelerandoBookService.extractText(from: Data("<html>error</html>".utf8)))
    }

    func test_accelerandoDownloadCachesValidatedSource() async throws {
        let html = """
        <div id="book"><p>A novel by Charles Stross</p>
        <p>Creative Commons Attribution-NonCommercial-NoDerivs 2.5</p>
        <h3>Chapter 1:</h3><p>Cached &amp; ready.</p></div>
        """
        TestURLProtocol.responseData = Data(html.utf8)
        TestURLProtocol.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLoom-RapidReader-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let session = URLSession(configuration: configuration)
        let service = AccelerandoBookService(urlSession: session, cacheURL: cacheURL)
        let downloaded = try await service.load()
        let cached = try await service.load()

        XCTAssertFalse(downloaded.loadedFromCache)
        XCTAssertTrue(cached.loadedFromCache)
        XCTAssertEqual(TestURLProtocol.requestCount, 1)
        XCTAssertEqual(downloaded.text, cached.text)
    }

    func test_progressIsFingerprintedAndDoesNotStoreSourceText() throws {
        let suiteName = "BookLoom.RapidReaderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = RapidReaderProgressStore(defaults: defaults, key: "progress")
        let text = "first private word second third fourth fifth"

        let saved = store.write(text: text, wordIndex: 2, wpm: 20, chunkSize: 9, now: Date(timeIntervalSince1970: 42))
        XCTAssertEqual(saved?.wordIndex, 2)
        XCTAssertEqual(saved?.wpm, 100)
        XCTAssertEqual(saved?.chunkSize, 1)
        XCTAssertEqual(store.read(text: text)?.wordIndex, 2)
        XCTAssertFalse(String(data: try XCTUnwrap(defaults.data(forKey: "progress")), encoding: .utf8)?.contains(text) == true)

        XCTAssertNil(store.read(text: "a different document"))
        store.clear(text: text)
        XCTAssertNil(store.read(text: text))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_progressSupportsFastReadingSpeeds() {
        XCTAssertEqual(RapidReaderProgressStore.clampWPM(1_500), 1_500)
        XCTAssertEqual(RapidReaderProgressStore.clampWPM(2_000), 1_500)
    }

    func test_seekWordIndexUsesThirtySecondsAtConfiguredWPMAndClamps() {
        XCTAssertEqual(
            RapidReaderProgressStore.seekWordIndex(from: 100, seconds: -30, wordCount: 1_000, wpm: 600),
            0
        )
        XCTAssertEqual(
            RapidReaderProgressStore.seekWordIndex(from: 100, seconds: 30, wordCount: 1_000, wpm: 600),
            400
        )
        XCTAssertEqual(
            RapidReaderProgressStore.seekWordIndex(from: 500, seconds: 30, wordCount: 600, wpm: 1_500),
            599
        )
    }

    func test_remainingTimeAndLongCountdownFormatting() {
        XCTAssertEqual(
            RapidReaderProgressStore.remainingSeconds(wordIndex: 10, wordCount: 110, currentWordCount: 2, wpm: 100),
            58.8,
            accuracy: 0.001
        )
        XCTAssertEqual(RapidReaderProgressStore.formatRemainingTime(3661), "1:01:01")
        XCTAssertEqual(RapidReaderProgressStore.formatRemainingTime(65), "1:05")
    }

    @MainActor
    func test_defaultAccelerandoBookIsInstalledOnlyOnce() throws {
        UserDefaults.standard.removeObject(forKey: AccelerandoBook.installationDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: AccelerandoBook.installationDefaultsKey) }
        let container = try ModelContainer(
            for: LibraryBook.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let first = try XCTUnwrap(AccelerandoBook.ensureOnShelf(context: context))
        let second = try XCTUnwrap(AccelerandoBook.ensureOnShelf(context: context))
        let books = try context.fetch(FetchDescriptor<LibraryBook>())

        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
        XCTAssertEqual(books.count, 1)
        XCTAssertTrue(first.isAccelerando)
        XCTAssertEqual(first.format, .ebook)
        XCTAssertTrue(first.countsAsOwned)
        XCTAssertEqual(first.sourceURLString, AccelerandoBook.sourceURL.absoluteString)
    }

    @MainActor
    func test_defaultAccelerandoDuplicatesAreReconciled() throws {
        UserDefaults.standard.removeObject(forKey: AccelerandoBook.installationDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: AccelerandoBook.installationDefaultsKey) }
        let container = try ModelContainer(
            for: LibraryBook.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let first = try XCTUnwrap(AccelerandoBook.ensureOnShelf(context: context))
        let duplicate = AccelerandoBook.makeShelfBook(now: first.addedAt.addingTimeInterval(1))
        context.insert(duplicate)
        try context.save()

        let retained = try XCTUnwrap(AccelerandoBook.ensureOnShelf(context: context))
        let books = try context.fetch(FetchDescriptor<LibraryBook>())

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(retained.persistentModelID, first.persistentModelID)
    }
}

private final class TestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

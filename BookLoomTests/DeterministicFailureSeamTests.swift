import CloudKit
import SwiftData
import XCTest
@testable import BookLoom

@MainActor
final class DeterministicFailureSeamTests: XCTestCase {
    func test_snapshotQueryDiscardsFirstPageWhenLaterPageFails() async {
        let record = CKRecord(recordType: "MemberShareSnapshot")
        let query = StubSnapshotQuery(
            first: MemberSnapshotQueryPage(records: [.success(record)], hasMore: true),
            nextError: TestFailure.expected
        )
        var decodedRecordNames: [String] = []

        do {
            _ = try await CloudKitSharingService.fetchMemberSnapshots(
                zoneID: .default,
                query: query,
                decode: { record in
                    decodedRecordNames.append(record.recordID.recordName)
                    return MemberShareSnapshot(authorMemberID: "member", authorName: "Reader")
                }
            )
            XCTFail("Expected the later page failure to abort the query")
        } catch {
            XCTAssertEqual(error as? TestFailure, .expected)
        }

        XCTAssertEqual(decodedRecordNames, [record.recordID.recordName])
        XCTAssertEqual(query.nextPageCallCount, 1)
    }

    func test_snapshotQueryRejectsIndividualRecordFailure() async {
        let good = CKRecord(recordType: "MemberShareSnapshot")
        let query = StubSnapshotQuery(
            first: MemberSnapshotQueryPage(
                records: [.success(good), .failure(TestFailure.expected)],
                hasMore: false
            )
        )

        do {
            _ = try await CloudKitSharingService.fetchMemberSnapshots(
                zoneID: .default,
                query: query,
                decode: { _ in MemberShareSnapshot(authorMemberID: "member", authorName: "Reader") }
            )
            XCTFail("Expected an individual record failure to abort the snapshot set")
        } catch {
            XCTAssertEqual(error as? TestFailure, .expected)
        }
    }

    func test_refreshRequestsCoalesceAndNeverOverlap() async throws {
        let coordinator = CloudRefreshCoordinator()
        let gate = ManualGate()
        var events: [String] = []
        var activeCount = 0
        var maximumActiveCount = 0

        let first = Task { @MainActor in
            await coordinator.request {
                activeCount += 1
                maximumActiveCount = max(maximumActiveCount, activeCount)
                events.append("first-start")
                await gate.wait()
                events.append("first-end")
                activeCount -= 1
            }
        }
        try await waitUntil { events == ["first-start"] }

        await coordinator.request {
            activeCount += 1
            maximumActiveCount = max(maximumActiveCount, activeCount)
            events.append("second-start")
            events.append("second-end")
            activeCount -= 1
        }
        gate.release()
        await first.value

        XCTAssertEqual(events, ["first-start", "first-end", "second-start", "second-end"])
        XCTAssertEqual(maximumActiveCount, 1)
    }

    func test_overlappingPublishesSerializeAndNewestSnapshotWins() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let club = BookClub(name: "First")
        club.shareIsActive = true
        club.creatorMemberID = "local"
        context.insert(club)
        try context.save()
        let service = ControlledSnapshotService()

        SharedClubSync.publishIfNeeded(
            club,
            context: context,
            localMemberID: "local",
            localMemberName: "Reader",
            service: service,
            isEnabled: true
        )
        try await waitUntil { service.published.count == 1 }

        club.name = "Newest"
        SharedClubSync.publishIfNeeded(
            club,
            context: context,
            localMemberID: "local",
            localMemberName: "Reader",
            service: service,
            isEnabled: true
        )
        service.releaseFirstPublish()
        await SharedClubSync.waitForPendingPublishes(zoneName: club.cloudZoneName)

        XCTAssertEqual(service.maximumActivePublishes, 1)
        XCTAssertEqual(service.published.count, 2)
        XCTAssertEqual(service.published.last?.clubMeta?.name, "Newest")
    }

    func test_publishCompletionDoesNotTouchClubDeletedWhileRequestWasInFlight() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let club = BookClub(name: "Delete during publish")
        club.shareIsActive = true
        club.creatorMemberID = "local"
        context.insert(club)
        try context.save()
        let zoneName = club.cloudZoneName
        let service = ControlledSnapshotService()

        SharedClubSync.publishIfNeeded(
            club,
            context: context,
            localMemberID: "local",
            localMemberName: "Reader",
            service: service,
            isEnabled: true
        )
        try await waitUntil { service.published.count == 1 }

        context.delete(club)
        try context.save()
        service.releaseFirstPublish()
        await SharedClubSync.waitForPendingPublishes(zoneName: zoneName)

        XCTAssertTrue(try context.fetch(FetchDescriptor<BookClub>()).isEmpty)
    }

    func test_queuedPublishDoesNotReadClubDeletedBeforeTaskStarts() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let club = BookClub(name: "Delete before publish task")
        club.shareIsActive = true
        club.creatorMemberID = "local"
        context.insert(club)
        try context.save()
        let zoneName = club.cloudZoneName
        let service = ControlledSnapshotService()

        SharedClubSync.publishIfNeeded(
            club,
            context: context,
            localMemberID: "local",
            localMemberName: "Reader",
            service: service,
            isEnabled: true
        )
        context.delete(club)
        try context.save()
        await SharedClubSync.waitForPendingPublishes(zoneName: zoneName)

        XCTAssertTrue(service.published.isEmpty)
    }

    func test_persistentBootstrapFailureSelectsOnlyRecoveryPresentation() {
        let factory = FailingPersistentContainerFactory()

        let bootstrap = ModelBootstrap.make(
            schema: BookLoomApp.appSchema,
            sampleDataEnabled: false,
            factory: factory
        )

        XCTAssertEqual(factory.requestedStorage, [.persistentCloudKit, .memory])
        XCTAssertEqual(bootstrap.presentation, .recovery)
        XCTAssertNotNil(bootstrap.errorMessage)
    }

    func test_resetFetchFailurePreservesIdentityRowsAndSideEffects() async {
        let club = BookClub(name: "Keep")
        let book = LibraryBook(title: "Keep")
        let store = StubResetStore(clubs: [club], books: [book], failure: .fetch)
        let identity = StubIdentity(name: "Reader", memberID: "stable-id")
        let effects = ResetEffectsRecorder()

        await XCTAssertThrowsErrorAsync {
            try await BookLoomDataReset.resetAllData(
                store: store,
                memberIdentity: identity,
                sideEffects: effects.sideEffects
            )
        }

        XCTAssertEqual(store.durableClubs.count, 1)
        XCTAssertEqual(store.durableBooks.count, 1)
        XCTAssertEqual(identity.memberID, "stable-id")
        XCTAssertEqual(identity.name, "Reader")
        XCTAssertEqual(effects.callCount, 0)
    }

    func test_resetSaveFailurePreservesIdentityDurableRowsAndSideEffects() async {
        let club = BookClub(name: "Keep")
        let book = LibraryBook(title: "Keep")
        let store = StubResetStore(clubs: [club], books: [book], failure: .save)
        let identity = StubIdentity(name: "Reader", memberID: "stable-id")
        let effects = ResetEffectsRecorder()

        await XCTAssertThrowsErrorAsync {
            try await BookLoomDataReset.resetAllData(
                store: store,
                memberIdentity: identity,
                sideEffects: effects.sideEffects
            )
        }

        XCTAssertEqual(store.durableClubs.count, 1)
        XCTAssertEqual(store.durableBooks.count, 1)
        XCTAssertEqual(identity.memberID, "stable-id")
        XCTAssertEqual(identity.name, "Reader")
        XCTAssertEqual(effects.callCount, 0)
    }

    func test_successfulResetDeletesClubCascadesAndIndependentLibraryRoots() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let club = BookClub(name: "Delete")
        club.cloudZoneName = "BookClub-Reset"
        context.insert(club)
        context.insert(LibraryBook(title: "Independent root"))
        try context.save()
        let identity = StubIdentity(name: "Reader", memberID: "old-id")
        let effects = ResetEffectsRecorder()

        try await BookLoomDataReset.resetAllData(
            store: ModelContextDataResetStore(context: context),
            memberIdentity: identity,
            sideEffects: effects.sideEffects
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<BookClub>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LibraryBook>()).isEmpty)
        XCTAssertEqual(identity.name, "")
        XCTAssertNotEqual(identity.memberID, "old-id")
        XCTAssertEqual(effects.callCount, 3)
        XCTAssertEqual(effects.cleanupTargets.map(\.zoneName), ["BookClub-Reset"])
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: BookLoomApp.appSchema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: BookLoomApp.appSchema, configurations: [configuration])
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw TestFailure.timeout }
            await Task.yield()
        }
    }
}

private enum TestFailure: Error, Equatable {
    case expected
    case timeout
}

@MainActor
private final class StubSnapshotQuery: MemberSnapshotQuerying {
    let first: MemberSnapshotQueryPage
    let nextError: Error?
    private(set) var nextPageCallCount = 0

    init(first: MemberSnapshotQueryPage, nextError: Error? = nil) {
        self.first = first
        self.nextError = nextError
    }

    func firstPage(recordType: String, zoneID: CKRecordZone.ID) async throws -> MemberSnapshotQueryPage {
        first
    }

    func nextPage() async throws -> MemberSnapshotQueryPage {
        nextPageCallCount += 1
        if let nextError { throw nextError }
        return MemberSnapshotQueryPage(records: [], hasMore: false)
    }
}

@MainActor
private final class ManualGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ControlledSnapshotService: MemberSnapshotSyncing {
    private(set) var published: [MemberShareSnapshot] = []
    private(set) var maximumActivePublishes = 0
    private var activePublishes = 0
    private var firstContinuation: CheckedContinuation<Void, Never>?

    func publishMemberSnapshot(_ snapshot: MemberShareSnapshot, for club: BookClub, localMemberID: String) async throws {
        activePublishes += 1
        maximumActivePublishes = max(maximumActivePublishes, activePublishes)
        published.append(snapshot)
        if published.count == 1 {
            await withCheckedContinuation { firstContinuation = $0 }
        }
        activePublishes -= 1
    }

    func fetchMemberSnapshots(for club: BookClub) async throws -> [MemberShareSnapshot] { [] }
    func fetchAcceptedParticipantCount(for club: BookClub) async throws -> Int { 1 }

    func releaseFirstPublish() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}

@MainActor
private final class FailingPersistentContainerFactory: ModelContainerBuilding {
    private(set) var requestedStorage: [ModelContainerStorage] = []

    func makeContainer(schema: Schema, storage: ModelContainerStorage) throws -> ModelContainer {
        requestedStorage.append(storage)
        if storage == .persistentCloudKit { throw TestFailure.expected }
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

@MainActor
private final class StubIdentity: ResetMemberIdentity {
    var name: String
    var memberID: String

    init(name: String, memberID: String) {
        self.name = name
        self.memberID = memberID
    }
}

@MainActor
private final class StubResetStore: DataResetStore {
    enum Failure { case fetch, save }

    private(set) var durableClubs: [BookClub]
    private(set) var durableBooks: [LibraryBook]
    private let failure: Failure
    private var deletedClubs: [BookClub] = []
    private var deletedBooks: [LibraryBook] = []

    init(clubs: [BookClub], books: [LibraryBook], failure: Failure) {
        durableClubs = clubs
        durableBooks = books
        self.failure = failure
    }

    func fetchClubs() throws -> [BookClub] {
        if failure == .fetch { throw TestFailure.expected }
        return durableClubs
    }

    func fetchLibraryBooks() throws -> [LibraryBook] { durableBooks }
    func delete(_ club: BookClub) { deletedClubs.append(club) }
    func delete(_ book: LibraryBook) { deletedBooks.append(book) }

    func save() throws {
        if failure == .save { throw TestFailure.expected }
        durableClubs.removeAll { club in deletedClubs.contains { $0 === club } }
        durableBooks.removeAll { book in deletedBooks.contains { $0 === book } }
    }
}

@MainActor
private final class ResetEffectsRecorder {
    private(set) var callCount = 0
    private(set) var cleanupTargets: [ClubCleanupTarget] = []

    var sideEffects: DataResetSideEffects {
        DataResetSideEffects(
            cleanupCloudKit: { [weak self] targets, _ in
                self?.cleanupTargets = targets
                self?.callCount += 1
            },
            purgeCaches: { [weak self] in self?.callCount += 1 },
            clearDefaults: { [weak self] in self?.callCount += 1 }
        )
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: @MainActor () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        // Expected.
    }
}

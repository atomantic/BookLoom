import Foundation
import SwiftData
import XCTest
@testable import BookLoom

/// `ActiveClubStore` is pure selection/fallback logic over a UserDefaults-backed
/// zone name. `resolveActiveClub` must never mutate; `reconcileWithVisibleClubs`,
/// `setActiveClub`, and `clearActiveClub` own the side effects. These tests
/// exercise the resolve/fallback/clear branches directly.
///
/// `ActiveClubStore` reads `UserDefaults.standard` (the production defaults key
/// is not injectable), so each test snapshots and restores that key to avoid
/// leaking state across runs.
@MainActor
final class ActiveClubStoreTests: XCTestCase {
    private static let defaultsKey = "net.shadowpuppet.BookLoom.activeClubZoneName"
    private var savedValue: String?

    override func setUp() {
        super.setUp()
        savedValue = UserDefaults.standard.string(forKey: Self.defaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    override func tearDown() {
        if let savedValue {
            UserDefaults.standard.set(savedValue, forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
        super.tearDown()
    }

    private func club(_ zone: String, name: String = "Club") -> BookClub {
        let club = BookClub(name: name)
        club.cloudZoneName = zone
        return club
    }

    func test_resolveReturnsNilWhenNoClubsExist() {
        let store = ActiveClubStore()
        XCTAssertNil(store.resolveActiveClub(from: []))
    }

    func test_resolveReturnsStoredMatchWhenPresent() {
        UserDefaults.standard.set("zone-b", forKey: Self.defaultsKey)
        let store = ActiveClubStore()
        let a = club("zone-a")
        let b = club("zone-b")

        let resolved = store.resolveActiveClub(from: [a, b])

        XCTAssertTrue(resolved === b, "Stored zone should resolve to its matching club")
    }

    func test_resolveFallsBackToFirstClubWhenStoredZoneMissing() {
        UserDefaults.standard.set("zone-gone", forKey: Self.defaultsKey)
        let store = ActiveClubStore()
        let a = club("zone-a")
        let b = club("zone-b")

        let resolved = store.resolveActiveClub(from: [a, b])

        XCTAssertTrue(resolved === a, "Unresolvable stored zone falls back to the first visible club")
    }

    func test_resolveDoesNotMutateStoredZoneOnFallback() {
        UserDefaults.standard.set("zone-gone", forKey: Self.defaultsKey)
        let store = ActiveClubStore()

        _ = store.resolveActiveClub(from: [club("zone-a")])

        XCTAssertEqual(store.activeClubZoneName, "zone-gone", "resolve must be pure — no persistence side effects")
        XCTAssertEqual(UserDefaults.standard.string(forKey: Self.defaultsKey), "zone-gone")
    }

    func test_setActiveClubPersistsZoneName() {
        let store = ActiveClubStore()
        let a = club("zone-a")

        store.setActiveClub(a)

        XCTAssertEqual(store.activeClubZoneName, "zone-a")
        XCTAssertEqual(UserDefaults.standard.string(forKey: Self.defaultsKey), "zone-a")
    }

    func test_clearActiveClubRemovesPersistedZone() {
        UserDefaults.standard.set("zone-a", forKey: Self.defaultsKey)
        let store = ActiveClubStore()

        store.clearActiveClub()

        XCTAssertNil(store.activeClubZoneName)
        XCTAssertNil(UserDefaults.standard.string(forKey: Self.defaultsKey))
    }

    func test_reconcileClearsStoredZoneWhenNoClubsRemain() {
        UserDefaults.standard.set("zone-a", forKey: Self.defaultsKey)
        let store = ActiveClubStore()

        store.reconcileWithVisibleClubs([])

        XCTAssertNil(store.activeClubZoneName, "Reconcile with no clubs must clear the stale selection")
        XCTAssertNil(UserDefaults.standard.string(forKey: Self.defaultsKey))
    }

    func test_reconcileKeepsValidStoredZoneUntouched() {
        UserDefaults.standard.set("zone-b", forKey: Self.defaultsKey)
        let store = ActiveClubStore()

        store.reconcileWithVisibleClubs([club("zone-a"), club("zone-b")])

        XCTAssertEqual(store.activeClubZoneName, "zone-b", "A still-visible stored zone must not be reassigned")
    }

    func test_reconcilePersistsFallbackWhenStoredZoneMissing() {
        UserDefaults.standard.set("zone-gone", forKey: Self.defaultsKey)
        let store = ActiveClubStore()

        store.reconcileWithVisibleClubs([club("zone-a"), club("zone-b")])

        XCTAssertEqual(store.activeClubZoneName, "zone-a", "Reconcile should adopt and persist the first club as fallback")
        XCTAssertEqual(UserDefaults.standard.string(forKey: Self.defaultsKey), "zone-a")
    }
}

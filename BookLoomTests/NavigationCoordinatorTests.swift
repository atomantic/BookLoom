import SwiftUI
import XCTest
@testable import BookLoom

/// Exercises the top-level navigation state extracted out of `MainTabs` into
/// `NavigationCoordinator` (#22). The coordinator is a pure, dependency-free
/// navigation-state object: `applyScreenshotRoute` takes its club-derived side
/// effects as closures, so these tests assert the route-to-tab mapping, the
/// no-club guard, path resets, and that the correct closure fires per route —
/// without any SwiftData/environment setup.
@MainActor
final class NavigationCoordinatorTests: XCTestCase {
    /// Records which screenshot-route closures fired so a test can assert exactly
    /// one of them was invoked for a given route.
    private struct RouteEffects {
        var presentedImport = 0
        var pushedCurrentRead = 0
        var pushedSelectionPoll = 0
        var pushedMeeting = 0
    }

    /// Drives `applyScreenshotRoute`, counting each closure invocation and
    /// pushing a stub `Int` value onto the matching path so path mutations are
    /// observable. Returns the recorded effects.
    @discardableResult
    private func apply(
        _ route: String,
        hasClub: Bool,
        on coordinator: NavigationCoordinator
    ) -> RouteEffects {
        var effects = RouteEffects()
        coordinator.applyScreenshotRoute(
            route,
            hasClub: hasClub,
            presentFirstPendingImport: { effects.presentedImport += 1 },
            pushCurrentRead: {
                effects.pushedCurrentRead += 1
                coordinator.pushBooks(1)
            },
            pushFirstSelectionPoll: {
                effects.pushedSelectionPoll += 1
                coordinator.pushBooks(2)
            },
            pushFirstMeeting: {
                effects.pushedMeeting += 1
                coordinator.pushSchedule(3)
            }
        )
        return effects
    }

    func test_defaultSelectionMatchesPlatform() {
        let coordinator = NavigationCoordinator()
        XCTAssertEqual(coordinator.selectedTab, MainTab.defaultSelection)
        XCTAssertTrue(coordinator.booksPath.isEmpty)
        XCTAssertTrue(coordinator.discussionsPath.isEmpty)
        XCTAssertTrue(coordinator.schedulePath.isEmpty)
    }

    func test_selectSetsTab() {
        let coordinator = NavigationCoordinator()
        coordinator.select(.discussions)
        XCTAssertEqual(coordinator.selectedTab, .discussions)
    }

    func test_pushHelpersAppendToTheirOwnPaths() {
        let coordinator = NavigationCoordinator()
        coordinator.pushBooks("a")
        coordinator.pushSchedule(42)

        XCTAssertEqual(coordinator.booksPath.count, 1)
        XCTAssertEqual(coordinator.schedulePath.count, 1)
        XCTAssertTrue(coordinator.discussionsPath.isEmpty)
    }

    func test_resetPathsEmptiesAllThreeStacks() {
        let coordinator = NavigationCoordinator()
        coordinator.pushBooks("a")
        coordinator.pushSchedule(1)
        coordinator.discussionsPath.append("c")

        coordinator.resetPaths()

        XCTAssertTrue(coordinator.booksPath.isEmpty)
        XCTAssertTrue(coordinator.schedulePath.isEmpty)
        XCTAssertTrue(coordinator.discussionsPath.isEmpty)
    }

    // MARK: - applyScreenshotRoute

    func test_screenshotRouteWithoutClubForcesBooksAndResetsPaths() {
        let coordinator = NavigationCoordinator()
        coordinator.select(.schedule)
        coordinator.pushBooks("stale")
        coordinator.pushSchedule(9)

        // A route that would otherwise select .schedule must still collapse to
        // .books when there is no visible club, matching the original guard.
        let effects = apply("schedule", hasClub: false, on: coordinator)

        XCTAssertEqual(coordinator.selectedTab, .books)
        XCTAssertTrue(coordinator.booksPath.isEmpty, "paths reset before the no-club guard returns")
        XCTAssertTrue(coordinator.schedulePath.isEmpty)
        XCTAssertEqual(effects.pushedCurrentRead, 0)
        XCTAssertEqual(effects.pushedMeeting, 0)
    }

    func test_screenshotRouteResetsExistingPaths() {
        let coordinator = NavigationCoordinator()
        coordinator.pushBooks("stale")
        coordinator.pushSchedule(7)

        // "library" pushes nothing, so all paths should be empty afterward.
        apply("library", hasClub: true, on: coordinator)

        XCTAssertEqual(coordinator.selectedTab, .library)
        XCTAssertTrue(coordinator.booksPath.isEmpty)
        XCTAssertTrue(coordinator.schedulePath.isEmpty)
    }

    func test_tabOnlyRoutesSelectTheExpectedTabWithoutPushing() {
        let cases: [(route: String, tab: MainTab)] = [
            ("library", .library),
            ("books", .books),
            ("clubs", .books),
            ("clubHome", .books),
            ("shelf", .books),
            ("polls", .books),
            ("schedule", .schedule),
            ("discussion", .discussions),
            ("discussions", .discussions),
            ("settings", .settings),
            ("totally-unknown", .books) // default
        ]

        for testCase in cases {
            let coordinator = NavigationCoordinator()
            let effects = apply(testCase.route, hasClub: true, on: coordinator)

            XCTAssertEqual(coordinator.selectedTab, testCase.tab, "route \(testCase.route)")
            XCTAssertTrue(coordinator.booksPath.isEmpty, "route \(testCase.route) should not push")
            XCTAssertTrue(coordinator.schedulePath.isEmpty, "route \(testCase.route) should not push")
            XCTAssertEqual(effects.presentedImport, 0, "route \(testCase.route)")
            XCTAssertEqual(effects.pushedCurrentRead, 0, "route \(testCase.route)")
            XCTAssertEqual(effects.pushedSelectionPoll, 0, "route \(testCase.route)")
            XCTAssertEqual(effects.pushedMeeting, 0, "route \(testCase.route)")
        }
    }

    func test_importRoutePresentsPendingImportOnBooksTab() {
        let coordinator = NavigationCoordinator()
        let effects = apply("import", hasClub: true, on: coordinator)

        XCTAssertEqual(coordinator.selectedTab, .books)
        XCTAssertEqual(effects.presentedImport, 1)
        XCTAssertTrue(coordinator.booksPath.isEmpty)
    }

    func test_currentReadRoutePushesOntoBooks() {
        let coordinator = NavigationCoordinator()
        let effects = apply("currentRead", hasClub: true, on: coordinator)

        XCTAssertEqual(coordinator.selectedTab, .books)
        XCTAssertEqual(effects.pushedCurrentRead, 1)
        XCTAssertEqual(coordinator.booksPath.count, 1)
        XCTAssertTrue(coordinator.schedulePath.isEmpty)
    }

    func test_pollAndVoteRoutesPushSelectionPollOntoBooks() {
        for route in ["poll", "vote"] {
            let coordinator = NavigationCoordinator()
            let effects = apply(route, hasClub: true, on: coordinator)

            XCTAssertEqual(coordinator.selectedTab, .books, "route \(route)")
            XCTAssertEqual(effects.pushedSelectionPoll, 1, "route \(route)")
            XCTAssertEqual(coordinator.booksPath.count, 1, "route \(route)")
        }
    }

    func test_meetingRoutesPushMeetingOntoSchedule() {
        for route in ["meeting", "meetings"] {
            let coordinator = NavigationCoordinator()
            let effects = apply(route, hasClub: true, on: coordinator)

            XCTAssertEqual(coordinator.selectedTab, .schedule, "route \(route)")
            XCTAssertEqual(effects.pushedMeeting, 1, "route \(route)")
            XCTAssertEqual(coordinator.schedulePath.count, 1, "route \(route)")
            XCTAssertTrue(coordinator.booksPath.isEmpty, "route \(route)")
        }
    }
}

import Foundation
import SwiftUI

/// The app's custom URL scheme and the deep-link hosts it serves. Centralized so
/// the scheme string isn't retyped at every `url.scheme ==` / `url.host ==` site,
/// where a typo would silently drop the link instead of failing to compile.
enum BookLoomURL {
    /// `bookloom://…` — the app's registered custom scheme. Also the scheme of
    /// the internal `manual-cover` URLs minted by `BookMetadataCache`.
    static let scheme = "bookloom"

    enum Host {
        /// `bookloom://screenshot/<route>` — drives the App Store screenshot harness.
        static let screenshot = "screenshot"
        /// `bookloom://import?url=…` — Share Extension / shelf import landing.
        static let `import` = "import"
    }
}

/// The navigation targets reachable via the screenshot harness
/// (`-screenshotRoute <name>`) and `bookloom://screenshot/<route>` deep links.
/// Several routes share a destination tab; the raw values are the on-the-wire
/// strings the harness passes. Unknown strings fall back to `.books`.
enum ScreenshotRoute: String {
    case library
    case books
    case clubs
    case clubHome
    case shelf
    case `import`
    case imports
    case currentRead
    case polls
    case poll
    case vote
    case schedule
    case meeting
    case meetings
    case discussion
    case discussions
    case settings

    /// Maps any raw route string to a case, defaulting to `.books` for unknown
    /// input so a stale or mistyped route still lands somewhere sensible.
    init(rawValueOrBooks raw: String) {
        self = ScreenshotRoute(rawValue: raw) ?? .books
    }

    var usesFullScreenImport: Bool { self == .import }
    var clearsSampleImports: Bool { self == .library }
}

/// Centralizes top-level navigation state for `MainTabs` and `RegularWidthMainView`.
///
/// Owns the selected tab plus the per-tab `NavigationPath` instances that were
/// previously scattered as individual `@State` values, and exposes typed
/// navigation entry points (`navigate(to:)`, screenshot-route handling, and the
/// URL-driven library/club import landings). Because a single instance is shared
/// across the compact `TabView` path and the regular-width split path, tab
/// selection and pushed paths survive size-class transitions exactly as before.
///
/// The screenshot/route helpers take their club data as parameters rather than
/// reaching into the SwiftData/environment layer, so the coordinator stays a
/// pure navigation-state object that is trivial to reason about and test.
@Observable
@MainActor
final class NavigationCoordinator {
    var selectedTab: MainTab = MainTab.defaultSelection
    var booksPath = NavigationPath()
    var discussionsPath = NavigationPath()
    var schedulePath = NavigationPath()

    /// Resets every per-tab navigation stack to its root.
    func resetPaths() {
        booksPath = NavigationPath()
        schedulePath = NavigationPath()
        discussionsPath = NavigationPath()
    }

    /// Selects a tab.
    func select(_ tab: MainTab) {
        selectedTab = tab
    }

    /// Appends a value to the books stack, preserving its concrete type so
    /// `navigationDestination(for:)` matchers resolve correctly.
    func pushBooks<V: Hashable>(_ value: V) {
        booksPath.append(value)
    }

    /// Appends a value to the schedule stack, preserving its concrete type.
    func pushSchedule<V: Hashable>(_ value: V) {
        schedulePath.append(value)
    }

    /// Applies a screenshot/deep-link route. The caller supplies the club-derived
    /// side effects (active-club selection, import presentation) and the actual
    /// path pushes via the supplied closures, which call `pushBooks`/`pushSchedule`
    /// with the correct concrete types. This keeps the coordinator free of the
    /// SwiftData model layer while still owning every tab/path mutation.
    ///
    /// - Parameters:
    ///   - route: The route name from the screenshot harness or `bookloom://screenshot/...` URL.
    ///   - hasClub: Whether a visible club exists to resolve targets against.
    ///   - presentFirstPendingImport: Invoked for the `import` route.
    ///   - pushCurrentRead: Pushes the current-read target for the `currentRead` route.
    ///   - pushFirstSelectionPoll: Pushes the first selection poll for `poll`/`vote`.
    ///   - pushFirstMeeting: Pushes the first/most-recent meeting for `meeting`/`meetings`.
    func applyScreenshotRoute(
        _ route: ScreenshotRoute,
        hasClub: Bool,
        presentFirstPendingImport: () -> Void,
        pushCurrentRead: () -> Void,
        pushFirstSelectionPoll: () -> Void,
        pushFirstMeeting: () -> Void
    ) {
        resetPaths()

        guard hasClub else {
            selectedTab = .books
            return
        }

        switch route {
        case .library:
            selectedTab = .library
        case .books, .clubs, .clubHome, .shelf, .imports:
            selectedTab = .books
        case .import:
            selectedTab = .books
            presentFirstPendingImport()
        case .currentRead:
            selectedTab = .books
            pushCurrentRead()
        case .polls:
            selectedTab = .books
        case .poll, .vote:
            selectedTab = .books
            pushFirstSelectionPoll()
        case .schedule:
            selectedTab = .schedule
        case .meeting, .meetings:
            selectedTab = .schedule
            pushFirstMeeting()
        case .discussion, .discussions:
            selectedTab = .discussions
        case .settings:
            selectedTab = .settings
        }
    }
}

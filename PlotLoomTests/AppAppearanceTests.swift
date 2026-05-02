import XCTest
import SwiftUI
@testable import PlotLoom

final class AppAppearanceTests: XCTestCase {
    func test_resolvedFallsBackToSystemForUnknownRawValue() {
        XCTAssertEqual(AppAppearance.resolved(from: "unknown"), .system)
    }

    func test_preferredColorSchemesMatchAppearanceChoices() {
        XCTAssertNil(AppAppearance.system.preferredColorScheme)
        XCTAssertEqual(AppAppearance.light.preferredColorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.preferredColorScheme, .dark)
    }
}

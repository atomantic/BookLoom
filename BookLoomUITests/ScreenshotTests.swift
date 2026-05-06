import XCTest
#if canImport(UIKit)
import UIKit
#endif

final class ScreenshotTests: XCTestCase {
    private static let projectDir: String = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }()

    private var app: XCUIApplication!

    private var config: [String: String] {
        for path in [
            "\(Self.projectDir)/.screenshot_config.json",
            "/tmp/bookloom_screenshot_config.json"
        ] {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
                continue
            }
            return dict
        }
        return [:]
    }

    private var locale: String { config["locale"] ?? "en" }
    private var outputDir: String { config["output_dir"] ?? "\(Self.projectDir)/screenshots" }
    @MainActor private var deviceType: String {
        if let device = config["device"] { return device }
        return isIPad ? "ipad_13" : "iphone_6.7"
    }
    private var targetScreen: String? {
        let screen = config["target_screen"] ?? ""
        return screen.isEmpty ? nil : screen
    }

    @MainActor private var isIPad: Bool {
        if let device = config["device"] { return device.hasPrefix("ipad") }
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    @MainActor func testCaptureIPhoneScreenshots() {
        guard !isIPad else { return }
        captureStandardScreens()
    }

    @MainActor func testCaptureIPadScreenshots() {
        guard isIPad else { return }
        captureStandardScreens()
    }

    /// Captures the Books, Polls, and Schedule tabs at the largest accessibility
    /// text size. Used to verify Dynamic Type doesn't break the layout. Output
    /// lands in `screenshots/{locale}/{device}_a11y/` so it doesn't clobber the
    /// App Store-bound captures.
    @MainActor func testCaptureLargestDynamicType() {
        captureRoute("a11y_01_books", route: "books", waitForText: "Currently Reading", dynamicType: "accessibility5", outputSuffix: "_a11y")
        captureRoute("a11y_05_polls", route: "polls", waitForText: "June Pick Shortlist", dynamicType: "accessibility5", outputSuffix: "_a11y")
        captureRoute("a11y_08_schedule", route: "schedule", waitForText: "Small Fires Discussion", dynamicType: "accessibility5", outputSuffix: "_a11y")
    }

    @MainActor
    private func captureStandardScreens() {
        captureRoute("01_books", route: "books", waitForText: "Currently Reading")
        captureShelf()
        captureRoute("03_import", route: "import", waitForText: "Add to Proposals")
        captureRoute("04_current_read", route: "currentRead", waitForText: "Discussion")
        captureRoute("05_polls", route: "polls", waitForText: "June Pick Shortlist")
        captureRoute("06_vote", route: "vote", waitForText: "Save Ballot")
        captureRoute("07_discussions", route: "discussions", waitForText: "Current Read")
        captureRoute("08_schedule", route: "schedule", waitForText: "Small Fires Discussion")
        captureRoute("09_meeting", route: "meeting", waitForText: "Save RSVP")
        captureAddBook()
    }

    @MainActor
    private func captureRoute(_ name: String, route: String, waitForText expectedText: String, dynamicType: String? = nil, outputSuffix: String = "") {
        guard shouldCapture(name) else { return }
        launch(route: route, dynamicType: dynamicType)
        waitForText(expectedText)
        saveScreenshot(name, suffix: outputSuffix)
    }

    /// Captures the top-level personal Shelf with seeded ownership and reading
    /// indicators, separate from the club Imports screenshot.
    @MainActor
    private func captureShelf() {
        let name = "02_shelf"
        guard shouldCapture(name) else { return }
        launch(route: "library")
        waitForText("Personal Shelf")
        saveScreenshot(name)
    }

    @MainActor
    private func captureAddBook() {
        let name = "10_add_book"
        guard shouldCapture(name) else { return }
        launch(route: "books")
        waitForText("Currently Reading")

        let addBook = app.buttons["Add Book"]
        if addBook.waitForExistence(timeout: 3) {
            addBook.tap()
        }
        waitForText("Add a Book")
        saveScreenshot(name)
    }

    @MainActor
    private func launch(route: String, dynamicType: String? = nil) {
        app = XCUIApplication()
        var args = [
            "-SeedSampleData",
            "-screenshotRoute", route,
            "-AppleLanguages", "(\(locale))",
            "-AppleLocale", locale
        ]
        if let dynamicType {
            args += ["-screenshotDynamicType", dynamicType]
        }
        app.launchArguments = args
        app.launch()
        sleep(1)
    }

    @MainActor
    private func waitForText(_ text: String) {
        let label = app.staticTexts[text]
        _ = label.waitForExistence(timeout: 5)
        sleep(1)
    }

    private func shouldCapture(_ name: String) -> Bool {
        targetScreen == nil || targetScreen == name
    }

    @MainActor
    private func saveScreenshot(_ name: String, suffix: String = "") {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(locale)_\(deviceType)\(suffix)_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = "\(outputDir)/\(locale)/\(deviceType)\(suffix)"
        let url = URL(fileURLWithPath: "\(dir)/\(name).png")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: url)
    }
}

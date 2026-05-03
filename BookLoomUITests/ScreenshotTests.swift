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

    @MainActor
    private func captureStandardScreens() {
        captureRoute("01_clubs", route: "clubs", waitForText: "Riverside Reading Circle")
        captureRoute("02_club_home", route: "clubHome", waitForText: "Currently Reading")
        captureRoute("03_current_read", route: "currentRead", waitForText: "Discussion")
        captureRoute("04_vote", route: "poll", waitForText: "June Pick Shortlist")
        captureRoute("05_meeting", route: "meeting", waitForText: "Small Fires Discussion")
        captureBookIdeas()
        captureAddBook()
    }

    @MainActor
    private func captureRoute(_ name: String, route: String, waitForText expectedText: String) {
        guard shouldCapture(name) else { return }
        launch(route: route)
        waitForText(expectedText)
        saveScreenshot(name)
    }

    @MainActor
    private func captureBookIdeas() {
        let name = "06_book_ideas"
        guard shouldCapture(name) else { return }
        launch(route: "clubHome")
        waitForText("Proposed")

        let lastProposal = app.staticTexts["Tomorrow, and Tomorrow, and Tomorrow"]
        var attempts = 0
        while !lastProposal.isHittable && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        sleep(1)
        saveScreenshot(name)
    }

    @MainActor
    private func captureAddBook() {
        let name = "07_add_book"
        guard shouldCapture(name) else { return }
        launch(route: "clubHome")
        waitForText("Currently Reading")

        let addBook = app.buttons["Add Book"]
        if addBook.waitForExistence(timeout: 3) {
            addBook.tap()
        }
        waitForText("Add a Proposal")
        saveScreenshot(name)
    }

    @MainActor
    private func launch(route: String) {
        app = XCUIApplication()
        app.launchArguments = [
            "-SeedSampleData",
            "-screenshotRoute", route,
            "-AppleLanguages", "(\(locale))",
            "-AppleLocale", locale
        ]
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
    private func saveScreenshot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(locale)_\(deviceType)_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = "\(outputDir)/\(locale)/\(deviceType)"
        let url = URL(fileURLWithPath: "\(dir)/\(name).png")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: url)
    }
}

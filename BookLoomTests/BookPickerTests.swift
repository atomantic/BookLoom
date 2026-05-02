import XCTest
@testable import BookLoom

final class BookPickerTests: XCTestCase {
    func test_pickNext_returnsNil_whenEmpty() {
        XCTAssertNil(BookPicker.pickNext(from: []))
    }

    func test_pickNext_returnsNil_whenNoneProposed() {
        let s = BookSubmission(title: "x", status: .completed)
        XCTAssertNil(BookPicker.pickNext(from: [s]))
    }

    func test_pickNext_returnsAProposed() {
        let proposed = BookSubmission(title: "a", status: .proposed)
        let completed = BookSubmission(title: "b", status: .completed)
        let pick = BookPicker.pickNext(from: [proposed, completed])
        XCTAssertEqual(pick?.title, "a")
    }
}

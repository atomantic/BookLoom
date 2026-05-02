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

    func test_reducedProposalPool_keepsOneProposalPerSubmitter() {
        let alexOne = BookSubmission(title: "Alex 1", submittedBy: "Alex", submittedByMemberID: "alex")
        let alexTwo = BookSubmission(title: "Alex 2", submittedBy: "Alex", submittedByMemberID: "alex")
        let sam = BookSubmission(title: "Sam", submittedBy: "Sam", submittedByMemberID: "sam")
        let completed = BookSubmission(title: "Done", submittedBy: "Sam", submittedByMemberID: "sam", status: .completed)
        var generator = ZeroRandomNumberGenerator()

        let pool = BookPicker.reducedProposalPool(
            from: [alexOne, alexTwo, sam, completed],
            using: &generator
        )

        XCTAssertEqual(pool.count, 2)
        XCTAssertEqual(pool.filter { $0.submittedByMemberID == "alex" }.count, 1)
        XCTAssertEqual(pool.filter { $0.submittedByMemberID == "sam" }.count, 1)
        XCTAssertFalse(pool.contains { $0.status == .completed })
    }

    func test_pickNext_choosesFromReducedSubmitterPool() {
        let alexOne = BookSubmission(title: "Alex 1", submittedBy: "Alex", submittedByMemberID: "alex")
        let alexTwo = BookSubmission(title: "Alex 2", submittedBy: "Alex", submittedByMemberID: "alex")
        var generator = ZeroRandomNumberGenerator()

        let pick = BookPicker.pickNext(from: [alexOne, alexTwo], using: &generator)

        guard let pick else {
            XCTFail("Expected a proposed book pick")
            return
        }
        XCTAssertTrue(pick === alexOne || pick === alexTwo)
    }
}

private struct ZeroRandomNumberGenerator: RandomNumberGenerator {
    mutating func next() -> UInt64 { 0 }
}

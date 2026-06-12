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

        // ZeroRandomNumberGenerator always yields 0, so every `randomElement`
        // selects index 0. Both submissions share the proposer key "id:alex",
        // so reducedProposalPool returns [alexOne] (first of the group), and
        // pickNext's final randomElement again returns alexOne. Pinning the
        // exact identity catches a regression that reorders the group reduction
        // or the final pick.
        XCTAssertTrue(pick === alexOne, "Deterministic ZeroRNG must pick the first submission in the group")
    }
}

private struct ZeroRandomNumberGenerator: RandomNumberGenerator {
    mutating func next() -> UInt64 { 0 }
}

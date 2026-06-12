import SwiftData
import XCTest
@testable import BookLoom

/// Guards the SwiftData schema. A missing inverse relationship makes
/// `ModelContainer` init throw for both persistent and in-memory configs, with
/// an error that doesn't name the broken relationship. This test fails loudly
/// in CI the moment a new `@Model` is added without wiring up its relationships.
final class ModelSchemaTests: XCTestCase {
    /// Every `@Model` type in BookLoom/Models. Adding a new model here is the
    /// single place this test needs updating.
    private static let models: [any PersistentModel.Type] = [
        BookClub.self,
        BookSubmission.self,
        LibraryBook.self,
        Rating.self,
        BookNote.self,
        ClubMeeting.self,
        MeetingRSVP.self,
        SelectionPoll.self,
        BookVote.self,
        DiscussionPrompt.self
    ]

    func testModelContainerSchemaIsValid() throws {
        _ = try ModelContainer(
            for: Schema(Self.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

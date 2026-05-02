import Foundation
import SwiftData

@Model
final class BookClub {
    var name: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \BookSubmission.bookClub)
    var submissions: [BookSubmission]? = nil

    init(name: String = "", createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}

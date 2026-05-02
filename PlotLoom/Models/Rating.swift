import Foundation
import SwiftData

@Model
final class Rating {
    var memberName: String = ""
    var stars: Int = 0
    var createdAt: Date = Date.now

    var submission: BookSubmission? = nil

    init(memberName: String = "", stars: Int = 0, createdAt: Date = .now) {
        self.memberName = memberName
        self.stars = stars
        self.createdAt = createdAt
    }
}

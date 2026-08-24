import Foundation
import SwiftData

@Model
final class Rating {
    var memberID: String = ""
    var memberName: String = ""
    var stars: Int = 0
    var createdAt: Date = Date.now

    var submission: BookSubmission? = nil

    init(memberID: String = "", memberName: String = "", stars: Int = 0, createdAt: Date = .now) {
        self.memberID = memberID
        self.memberName = memberName
        self.stars = stars
        self.createdAt = createdAt
    }

    func matches(memberID: String, memberName: String) -> Bool {
        MemberIdentityMatch.matches(
            storedMemberID: self.memberID,
            storedMemberName: self.memberName,
            memberID: memberID,
            memberName: memberName
        )
    }
}

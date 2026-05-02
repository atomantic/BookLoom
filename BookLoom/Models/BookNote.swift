import Foundation
import SwiftData

@Model
final class BookNote {
    var memberID: String = ""
    var memberName: String = ""
    var text: String = ""
    var createdAt: Date = Date.now

    var submission: BookSubmission? = nil

    init(memberID: String = "", memberName: String = "", text: String = "", createdAt: Date = .now) {
        self.memberID = memberID
        self.memberName = memberName
        self.text = text
        self.createdAt = createdAt
    }
}

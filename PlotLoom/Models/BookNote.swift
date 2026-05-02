import Foundation
import SwiftData

@Model
final class BookNote {
    var memberName: String = ""
    var text: String = ""
    var createdAt: Date = Date.now

    var submission: BookSubmission? = nil

    init(memberName: String = "", text: String = "", createdAt: Date = .now) {
        self.memberName = memberName
        self.text = text
        self.createdAt = createdAt
    }
}

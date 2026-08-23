import Foundation

enum MemberIdentityMatch {
    static func matches(
        storedMemberID: String,
        storedMemberName: String,
        memberID: String,
        memberName: String
    ) -> Bool {
        if !memberID.isEmpty, storedMemberID == memberID {
            return true
        }
        return storedMemberID.isEmpty && storedMemberName == memberName
    }
}

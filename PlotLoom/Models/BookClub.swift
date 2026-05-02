import Foundation
import SwiftData

@Model
final class BookClub {
    var name: String = ""
    var createdAt: Date = Date.now

    /// Stable per-club CloudKit zone name. Used as the anchor for the CKShare
    /// when the owner invites collaborators. Generated at init; do not mutate
    /// after a share has been created.
    var cloudZoneName: String = ""

    /// CloudKit user record name of the club's owner. `nil` means the local
    /// device's user is the owner (the inviter). Set when accepting an
    /// incoming share from another Apple ID.
    var ownerUserRecordName: String? = nil

    /// True once a CKShare has been created and saved for this club.
    var shareIsActive: Bool = false

    /// Cached count of share participants (including the owner). Updated when
    /// the sharing service refreshes the share record.
    var shareParticipantCount: Int = 1

    @Relationship(deleteRule: .cascade, inverse: \BookSubmission.bookClub)
    var submissions: [BookSubmission]? = nil

    var isOwner: Bool { ownerUserRecordName == nil }

    init(name: String = "", createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.cloudZoneName = "BookClub-\(UUID().uuidString)"
    }

    func addSubmission(_ submission: BookSubmission) {
        var updatedSubmissions = submissions ?? []
        if !updatedSubmissions.contains(where: { $0 === submission }) {
            updatedSubmissions.append(submission)
        }
        submissions = updatedSubmissions
        submission.bookClub = self
    }
}

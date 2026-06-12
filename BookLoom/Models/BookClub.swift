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

    /// Timestamp of the newest shared snapshot this device has imported or
    /// published. Used to avoid re-applying the same CloudKit payload on every
    /// view refresh.
    var lastSharedSnapshotAt: Date? = nil

    /// JSON-encoded `[memberID: name]` of every participant we've seen in a
    /// member-share snapshot. Lets the Members view surface joined participants
    /// before they have any club activity.
    var knownMemberRosterJSON: String = "{}"

    /// `MemberIdentity.memberID` of the device that created this club. Cannot
    /// be revoked as an admin by anyone. Set on creation and propagated via
    /// the owner's `ClubMeta` snapshot. Empty for legacy clubs created before
    /// this field existed; backfilled when the local creator opens the club.
    var creatorMemberID: String = ""

    /// JSON-encoded `[memberID]` of members granted admin privileges in
    /// addition to the creator. Synced through the owner's `ClubMeta`.
    var adminMemberIDsJSON: String = "[]"

    /// JSON-encoded `[memberID]` of members the owner has removed from the
    /// club. The owner's snapshot deletion drops their CloudKit record; this
    /// list is propagated through the owner's `ClubMeta` so every device skips
    /// re-applying any future re-published snapshot from a removed member.
    var removedMemberIDsJSON: String = "[]"

    var inviteURLString: String = ""

    /// Tie-break clock for `name`: the latest of the owner's `ClubMeta` rename
    /// timestamp and any admin's `nameProposal.updatedAt`.
    var nameUpdatedAt: Date = Date.distantPast

    @Relationship(deleteRule: .cascade, inverse: \BookSubmission.bookClub)
    var submissions: [BookSubmission]? = nil

    @Relationship(deleteRule: .cascade, inverse: \ClubMeeting.bookClub)
    var meetings: [ClubMeeting]? = nil

    @Relationship(deleteRule: .cascade, inverse: \SelectionPoll.bookClub)
    var selectionPolls: [SelectionPoll]? = nil

    /// True when this device is the club's owner — i.e. we created it locally
    /// and did not accept an incoming share from another Apple ID. Note this is
    /// also true for a brand-new local club whose CKShare has never been created
    /// (`shareIsActive == false`); both cases are "owned by this device," so
    /// ownership checks are correct, but it does NOT imply a live shared zone
    /// exists in CloudKit. For sync paths that require a created share, gate on
    /// `isShareOwner` instead so a never-shared local club can't take an
    /// owner-side CloudKit branch. See swift-gotchas catalogue #3.
    var isOwner: Bool { ownerUserRecordName == nil }

    /// True only when this device owns the club AND a CKShare has been created
    /// for it. Distinguishes "fully shared, I am owner" from "local only, share
    /// never created" — the two states `isOwner` alone collapses together.
    /// Use this before any owner-side CloudKit operation that assumes the
    /// shared zone already exists.
    var isShareOwner: Bool { isOwner && shareIsActive }

    /// True for a club this device created that has not yet been shared (no
    /// CKShare, so no shared zone in CloudKit). Owner-side sync must be skipped
    /// for these until a share is created.
    var isLocalOnly: Bool { isOwner && !shareIsActive }

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

    func addMeeting(_ meeting: ClubMeeting) {
        var updatedMeetings = meetings ?? []
        if !updatedMeetings.contains(where: { $0 === meeting }) {
            updatedMeetings.append(meeting)
        }
        meetings = updatedMeetings
        meeting.bookClub = self
    }

    func addSelectionPoll(_ poll: SelectionPoll) {
        var updatedPolls = selectionPolls ?? []
        if !updatedPolls.contains(where: { $0 === poll }) {
            updatedPolls.append(poll)
        }
        selectionPolls = updatedPolls
        poll.bookClub = self
    }

    var knownMemberRoster: [String: String] {
        get {
            guard let data = knownMemberRosterJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else { return }
            knownMemberRosterJSON = json
        }
    }

    var adminMemberIDs: Set<String> {
        get { decodeIDSet(adminMemberIDsJSON) }
        set { adminMemberIDsJSON = encodeIDSet(newValue) }
    }

    func isAdmin(memberID: String) -> Bool {
        guard !memberID.isEmpty else { return false }
        if memberID == creatorMemberID { return true }
        return adminMemberIDs.contains(memberID)
    }

    func isCreator(memberID: String) -> Bool {
        guard !memberID.isEmpty else { return false }
        return memberID == creatorMemberID
    }

    func setAdmin(_ isAdmin: Bool, memberID: String) {
        guard !memberID.isEmpty, memberID != creatorMemberID else { return }
        var current = adminMemberIDs
        if isAdmin {
            current.insert(memberID)
        } else {
            current.remove(memberID)
        }
        adminMemberIDs = current
    }

    var removedMemberIDs: Set<String> {
        get { decodeIDSet(removedMemberIDsJSON) }
        set { removedMemberIDsJSON = encodeIDSet(newValue) }
    }

    /// Owner-only operation. Marks `memberID` as removed, demotes them out of
    /// the admin set, and drops them from the local roster so the UI clears.
    /// The creator can never be removed.
    func removeMember(memberID: String) {
        guard !memberID.isEmpty, memberID != creatorMemberID else { return }
        var removed = removedMemberIDs
        removed.insert(memberID)
        removedMemberIDs = removed

        var admins = adminMemberIDs
        admins.remove(memberID)
        adminMemberIDs = admins

        var roster = knownMemberRoster
        roster.removeValue(forKey: memberID)
        knownMemberRoster = roster
    }
}

private func decodeIDSet(_ json: String) -> Set<String> {
    guard let data = json.data(using: .utf8),
          let decoded = try? JSONDecoder().decode([String].self, from: data) else {
        return []
    }
    return Set(decoded.filter { !$0.isEmpty })
}

private func encodeIDSet(_ ids: Set<String>) -> String {
    let array = ids.filter { !$0.isEmpty }.sorted()
    guard let data = try? JSONEncoder().encode(array),
          let json = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return json
}

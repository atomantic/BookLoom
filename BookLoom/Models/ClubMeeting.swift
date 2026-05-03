import Foundation
import SwiftData

enum MeetingRSVPStatus: String, CaseIterable, Identifiable {
    case attending
    case maybe
    case declined

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .attending: "Going"
        case .maybe: "Maybe"
        case .declined: "Can't Go"
        }
    }
}

enum MeetingReminderOffset: Int, CaseIterable, Identifiable {
    case atTime = 0
    case fifteenMinutes = 15
    case oneHour = 60
    case oneDay = 1440

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .atTime: "At time"
        case .fifteenMinutes: "15 min"
        case .oneHour: "1 hour"
        case .oneDay: "1 day"
        }
    }
}

@Model
final class ClubMeeting {
    /// Stable cross-account identifier. Generated at insert; preserved across
    /// CKShare snapshot merges so two devices reconcile to one row.
    var meetingID: String = UUID().uuidString
    var title: String = ""
    var scheduledAt: Date = Date.now
    var hostName: String = ""
    var hostMemberID: String = ""
    var location: String = ""
    var meetingURL: String = ""
    var reminderOffsetsRaw: String = "1440,60"
    var agenda: String = ""
    var createdAt: Date = Date.now
    var completedAt: Date? = nil

    var bookClub: BookClub? = nil
    var bookSubmission: BookSubmission? = nil

    @Relationship(deleteRule: .cascade, inverse: \MeetingRSVP.meeting)
    var rsvps: [MeetingRSVP]? = nil

    init(
        title: String = "",
        scheduledAt: Date = .now,
        hostName: String = "",
        hostMemberID: String = "",
        location: String = "",
        meetingURL: String = "",
        reminderOffsets: [Int] = [MeetingReminderOffset.oneDay.rawValue, MeetingReminderOffset.oneHour.rawValue],
        agenda: String = "",
        createdAt: Date = .now
    ) {
        self.title = title
        self.scheduledAt = scheduledAt
        self.hostName = hostName
        self.hostMemberID = hostMemberID
        self.location = location
        self.meetingURL = meetingURL
        self.reminderOffsetsRaw = Self.encodeReminderOffsets(reminderOffsets)
        self.agenda = agenda
        self.createdAt = createdAt
    }

    var reminderOffsets: [Int] {
        get { Self.decodeReminderOffsets(reminderOffsetsRaw) }
        set { reminderOffsetsRaw = Self.encodeReminderOffsets(newValue) }
    }

    var isCompleted: Bool { completedAt != nil }

    var displayTitle: String {
        title.trimmedOrNil ?? bookSubmission?.displayTitle ?? "Book Club Meeting"
    }

    @discardableResult
    func upsertRSVP(memberID: String, memberName: String, status: MeetingRSVPStatus, bringingNote: String = "") -> MeetingRSVP {
        let normalizedID = memberID.trimmedOrNil ?? memberName.trimmed
        if let existing = (rsvps ?? []).first(where: { $0.matches(memberID: normalizedID, memberName: memberName) }) {
            existing.memberID = normalizedID
            existing.memberName = memberName
            existing.status = status
            existing.bringingNote = bringingNote.trimmed
            existing.updatedAt = .now
            return existing
        }

        let rsvp = MeetingRSVP(
            memberID: normalizedID,
            memberName: memberName,
            status: status,
            bringingNote: bringingNote.trimmed
        )
        var updated = rsvps ?? []
        updated.append(rsvp)
        rsvps = updated
        rsvp.meeting = self
        return rsvp
    }

    func rsvp(for memberID: String, memberName: String) -> MeetingRSVP? {
        let normalizedID = memberID.trimmedOrNil ?? memberName.trimmed
        return (rsvps ?? []).first { $0.matches(memberID: normalizedID, memberName: memberName) }
    }

    private static func encodeReminderOffsets(_ offsets: [Int]) -> String {
        offsets
            .filter { $0 >= 0 }
            .sorted(by: >)
            .map(String.init)
            .joined(separator: ",")
    }

    private static func decodeReminderOffsets(_ rawValue: String) -> [Int] {
        rawValue
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 >= 0 }
            .sorted(by: >)
    }
}

@Model
final class MeetingRSVP {
    var memberID: String = ""
    var memberName: String = ""
    var statusRaw: String = MeetingRSVPStatus.attending.rawValue
    var bringingNote: String = ""
    var updatedAt: Date = Date.now

    var meeting: ClubMeeting? = nil

    init(
        memberID: String = "",
        memberName: String = "",
        status: MeetingRSVPStatus = .attending,
        bringingNote: String = "",
        updatedAt: Date = .now
    ) {
        self.memberID = memberID
        self.memberName = memberName
        self.statusRaw = status.rawValue
        self.bringingNote = bringingNote
        self.updatedAt = updatedAt
    }

    var status: MeetingRSVPStatus {
        get { MeetingRSVPStatus(rawValue: statusRaw) ?? .attending }
        set { statusRaw = newValue.rawValue }
    }

    func matches(memberID: String, memberName: String) -> Bool {
        if !memberID.isEmpty, self.memberID == memberID {
            return true
        }
        return self.memberID.isEmpty && self.memberName == memberName
    }
}

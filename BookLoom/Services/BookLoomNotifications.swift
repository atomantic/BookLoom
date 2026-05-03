import Foundation
import UserNotifications

enum BookLoomNotificationPreferences {
    static let proposalKey = BookLoomNotificationEvent.Kind.proposal.defaultsKey
    static let selectionKey = BookLoomNotificationEvent.Kind.selection.defaultsKey
    static let discussionKey = BookLoomNotificationEvent.Kind.discussion.defaultsKey

    static func isEnabled(_ kind: BookLoomNotificationEvent.Kind) -> Bool {
        UserDefaults.standard.bool(forKey: kind.defaultsKey)
    }

    static var anyEnabled: Bool {
        BookLoomNotificationEvent.Kind.allCases.contains { isEnabled($0) }
    }
}

struct BookLoomNotificationEvent {
    enum Kind: CaseIterable {
        case proposal
        case selection
        case discussion

        var defaultsKey: String {
            switch self {
            case .proposal: return "net.shadowpuppet.BookLoom.notifications.proposals"
            case .selection: return "net.shadowpuppet.BookLoom.notifications.selection"
            case .discussion: return "net.shadowpuppet.BookLoom.notifications.discussion"
            }
        }
    }

    let kind: Kind
    let title: String
    let body: String

    /// Diff a pre-merge view of the club against the post-merge canonical
    /// payloads to detect surfaceable changes. Notifications fire only for
    /// remote changes — additions authored by `localMemberID` are skipped so
    /// you never get a push for your own action.
    @MainActor
    static func events(
        clubName: String,
        previousSubmissions: [BookSubmission],
        canonicalSubmissions: [MemberShareSnapshot.SubmissionPayload],
        canonicalStatusOverrides: [MemberShareSnapshot.StatusOverride],
        canonicalRatings: [MemberShareSnapshot.RatingPayload],
        canonicalNotes: [MemberShareSnapshot.NotePayload],
        localMemberID: String,
        sinceCapturedAt: Date?
    ) -> [BookLoomNotificationEvent] {
        guard BookLoomNotificationPreferences.anyEnabled else { return [] }

        var events: [BookLoomNotificationEvent] = []
        let oldSubmissionsByID = Dictionary(uniqueKeysWithValues: previousSubmissions.map { ($0.selectionID, $0) })
        let oldCurrentID = previousSubmissions.first(where: { $0.status == .current })?.selectionID

        for submission in canonicalSubmissions where BookSubmissionStatus(rawValue: submission.initialStatusRaw) == .proposed {
            guard oldSubmissionsByID[submission.selectionID] == nil else { continue }
            guard submission.submittedByMemberID != localMemberID else { continue }
            let title = submission.title.trimmedOrNil ?? "New book proposal"
            events.append(
                BookLoomNotificationEvent(
                    kind: .proposal,
                    title: "New proposal in \(clubName)",
                    body: "\(title) was added to the book list."
                )
            )
        }

        let latestOverridesByID = Dictionary(grouping: canonicalStatusOverrides, by: \.submissionSelectionID)
            .compactMapValues { $0.max(by: { $0.occurredAt < $1.occurredAt }) }
        if let newCurrentID = latestOverridesByID
            .filter({ _, override in override.statusRaw == BookSubmissionStatus.current.rawValue })
            .max(by: { $0.value.occurredAt < $1.value.occurredAt })?
            .key,
           newCurrentID != oldCurrentID,
           let newCurrent = canonicalSubmissions.first(where: { $0.selectionID == newCurrentID }) {
            let title = newCurrent.title.trimmedOrNil ?? "the next book"
            events.append(
                BookLoomNotificationEvent(
                    kind: .selection,
                    title: "\(clubName) picked a book",
                    body: "\(title) is now currently reading."
                )
            )
        }

        let baselineDate = sinceCapturedAt ?? .distantPast
        let recentRatingsBySubmission = Dictionary(grouping: canonicalRatings.filter { $0.memberID != localMemberID && $0.createdAt > baselineDate }, by: \.submissionSelectionID)
        let recentNotesBySubmission = Dictionary(grouping: canonicalNotes.filter { $0.memberID != localMemberID && $0.createdAt > baselineDate }, by: \.submissionSelectionID)
        let active = Set(recentRatingsBySubmission.keys).union(recentNotesBySubmission.keys)
        for submissionID in active {
            let submission = canonicalSubmissions.first { $0.selectionID == submissionID }
            let title = submission?.title.trimmedOrNil ?? "a book"
            events.append(
                BookLoomNotificationEvent(
                    kind: .discussion,
                    title: "New activity in \(clubName)",
                    body: "\(title) has new ratings or notes."
                )
            )
        }

        return events
    }
}

enum BookLoomUserNotifications {
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    static func schedule(_ events: [BookLoomNotificationEvent]) async {
        let eligible = events.filter { BookLoomNotificationPreferences.isEnabled($0.kind) }
        guard !eligible.isEmpty else { return }
        guard await notificationsCanBeDelivered() else { return }

        for event in eligible {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "bookloom-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private static func notificationsCanBeDelivered() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }
}

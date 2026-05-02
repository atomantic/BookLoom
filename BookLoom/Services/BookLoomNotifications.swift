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

    @MainActor
    static func events(before club: BookClub, applying snapshot: SharedClubSnapshot) -> [BookLoomNotificationEvent] {
        guard BookLoomNotificationPreferences.anyEnabled else { return [] }

        var events: [BookLoomNotificationEvent] = []
        let clubName = snapshot.club.name.trimmedOrNil ?? club.name

        let oldSubmissions = Dictionary(uniqueKeysWithValues: (club.submissions ?? []).map { ($0.selectionID, $0) })
        let oldCurrentID = (club.submissions ?? []).first(where: { $0.status == .current })?.selectionID
        let newCurrent = snapshot.submissions.first { BookSubmissionStatus(rawValue: $0.statusRaw) == .current }

        for submission in snapshot.submissions where BookSubmissionStatus(rawValue: submission.statusRaw) == .proposed {
            guard oldSubmissions[submission.selectionID] == nil else { continue }
            let title = submission.title.trimmedOrNil ?? "New book proposal"
            events.append(
                BookLoomNotificationEvent(
                    kind: .proposal,
                    title: "New proposal in \(clubName)",
                    body: "\(title) was added to the book list."
                )
            )
        }

        if let newCurrent, newCurrent.selectionID != oldCurrentID {
            let title = newCurrent.title.trimmedOrNil ?? "the next book"
            events.append(
                BookLoomNotificationEvent(
                    kind: .selection,
                    title: "\(clubName) picked a book",
                    body: "\(title) is now currently reading."
                )
            )
        }

        for submission in snapshot.submissions {
            guard let oldSubmission = oldSubmissions[submission.selectionID] else { continue }
            let oldRatingCount = oldSubmission.ratings?.count ?? 0
            let oldNoteCount = oldSubmission.notes?.count ?? 0
            // Compare per-collection: a simultaneous add+remove across ratings/notes
            // would cancel out if we summed them.
            guard submission.ratings.count > oldRatingCount || submission.notes.count > oldNoteCount else { continue }

            let title = submission.title.trimmedOrNil ?? "a book"
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

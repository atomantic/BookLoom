import Foundation
import SwiftData
import UserNotifications

struct SelectionPollCandidateResult: Identifiable, Equatable {
    let id: String
    let score: Int
    let firstPlaceVotes: Int
    let rankedVotes: Int
}

struct SelectionPollTally: Equatable {
    let results: [SelectionPollCandidateResult]

    var leader: SelectionPollCandidateResult? { results.first }

    var winningResults: [SelectionPollCandidateResult] {
        guard let leader else { return [] }
        return results.filter { $0.score == leader.score }
    }

    var hasTie: Bool {
        winningResults.count > 1
    }
}

enum SelectionPollScorer {
    static func tally(votes: [BookVote], candidateIDs: [String]) -> SelectionPollTally {
        let allowedIDs = Set(candidateIDs)
        var scores = Dictionary(uniqueKeysWithValues: candidateIDs.map { ($0, 0) })
        var firstPlaceVotes = Dictionary(uniqueKeysWithValues: candidateIDs.map { ($0, 0) })
        var rankedVotes = Dictionary(uniqueKeysWithValues: candidateIDs.map { ($0, 0) })

        for vote in votes {
            let rankedIDs = SelectionPoll.uniqueRankedIDs(vote.rankedSubmissionIDs, allowedIDs: allowedIDs)
            for (index, candidateID) in rankedIDs.enumerated() {
                scores[candidateID, default: 0] += max(SelectionPoll.maxRanks - index, 1)
                rankedVotes[candidateID, default: 0] += 1
                if index == 0 {
                    firstPlaceVotes[candidateID, default: 0] += 1
                }
            }
        }

        let results = candidateIDs.map {
            SelectionPollCandidateResult(
                id: $0,
                score: scores[$0, default: 0],
                firstPlaceVotes: firstPlaceVotes[$0, default: 0],
                rankedVotes: rankedVotes[$0, default: 0]
            )
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.firstPlaceVotes != $1.firstPlaceVotes { return $0.firstPlaceVotes > $1.firstPlaceVotes }
            let leftIndex = candidateIDs.firstIndex(of: $0.id) ?? 0
            let rightIndex = candidateIDs.firstIndex(of: $1.id) ?? 0
            return leftIndex < rightIndex
        }

        return SelectionPollTally(results: results)
    }
}

enum SelectionPollCoordinator {
    static func promoteWinner(
        _ winner: BookSubmission,
        in club: BookClub,
        pickedAt: Date = .now,
        actorMemberID: String = ""
    ) {
        if let current = club.sections.current, current !== winner {
            current.status = .completed
            current.completedAt = pickedAt
            club.recordStatusOverride(
                StatusOverrideEntry(
                    submissionSelectionID: current.selectionID,
                    statusRaw: BookSubmissionStatus.completed.rawValue,
                    pickedAt: current.pickedAt,
                    completedAt: pickedAt,
                    occurredAt: pickedAt,
                    actorMemberID: actorMemberID
                )
            )
        }
        winner.status = .current
        winner.pickedAt = pickedAt
        winner.completedAt = nil
        club.recordStatusOverride(
            StatusOverrideEntry(
                submissionSelectionID: winner.selectionID,
                statusRaw: BookSubmissionStatus.current.rawValue,
                pickedAt: pickedAt,
                completedAt: nil,
                occurredAt: pickedAt,
                actorMemberID: actorMemberID
            )
        )
    }
}

enum BookSubmissionStatusEditor {
    static func markComplete(
        _ submission: BookSubmission,
        in club: BookClub,
        actorMemberID: String = "",
        now: Date = .now
    ) {
        submission.status = .completed
        submission.completedAt = now
        club.recordStatusOverride(
            StatusOverrideEntry(
                submissionSelectionID: submission.selectionID,
                statusRaw: BookSubmissionStatus.completed.rawValue,
                pickedAt: submission.pickedAt,
                completedAt: now,
                occurredAt: now,
                actorMemberID: actorMemberID
            )
        )
    }

    static func moveToProposals(
        _ submission: BookSubmission,
        in club: BookClub,
        actorMemberID: String = "",
        now: Date = .now
    ) {
        submission.status = .proposed
        submission.pickedAt = nil
        submission.completedAt = nil
        club.recordStatusOverride(
            StatusOverrideEntry(
                submissionSelectionID: submission.selectionID,
                statusRaw: BookSubmissionStatus.proposed.rawValue,
                pickedAt: nil,
                completedAt: nil,
                occurredAt: now,
                actorMemberID: actorMemberID
            )
        )
    }
}

enum BookSubmissionDetailsEditor {
    static func recordDetailsOverride(
        _ submission: BookSubmission,
        in club: BookClub,
        actorMemberID: String = "",
        updatedAt: Date = .now
    ) {
        club.recordSubmissionDetailsOverride(
            SubmissionDetailsOverrideEntry(
                submissionSelectionID: submission.selectionID,
                title: submission.title,
                author: submission.author,
                isbn: submission.isbn,
                bookDescription: submission.bookDescription,
                publishedYear: submission.publishedYear,
                coverURL: submission.coverURL,
                externalProvider: submission.externalProvider,
                externalID: submission.externalID,
                updatedAt: updatedAt,
                actorMemberID: actorMemberID
            )
        )
    }

    static func recordDeletion(
        _ submission: BookSubmission,
        in club: BookClub,
        actorMemberID: String = "",
        deletedAt: Date = .now
    ) {
        club.recordSubmissionDeletion(
            SubmissionDeletionEntry(
                submissionSelectionID: submission.selectionID,
                deletedAt: deletedAt,
                actorMemberID: actorMemberID
            )
        )
    }
}

enum DiscussionPromptLibrary {
    static let starterQuestions: [String] = [
        "What scene or idea stayed with you after finishing?",
        "Which character, argument, or choice changed how you read the book?",
        "Where did the book slow down or lose the group?",
        "What would you ask the author if they joined this meeting?",
        "Who in the group would you recommend this to next?"
    ]

    static func ensureStarterPrompts(for submission: BookSubmission, context: ModelContext) {
        let existingStarterCount = (submission.discussionPrompts ?? [])
            .filter { !$0.isArchived && $0.source == .starter }
            .count
        guard existingStarterCount == 0 else { return }

        var prompts = submission.discussionPrompts ?? []
        for (index, question) in starterQuestions.enumerated() {
            let prompt = DiscussionPrompt(question: question, orderIndex: index, source: .starter)
            prompt.submission = submission
            context.insert(prompt)
            prompts.append(prompt)
        }
        submission.discussionPrompts = prompts
    }
}

struct ClubMemberDigest: Identifiable, Equatable {
    /// Synthetic key used when a contributor was seen by name only and has no
    /// real `MemberIdentity.memberID`. Such digests cannot be tracked across
    /// devices, so admin/removal actions on them are intentionally disabled.
    static let nameOnlyPrefix = "name:"

    let id: String
    let memberIDs: Set<String>
    let name: String
    let activityCount: Int

    var isNameOnly: Bool { memberIDs.isEmpty }
}

enum ClubMemberCollector {
    static func collect(from club: BookClub) -> [ClubMemberDigest] {
        var members: [String: (representativeID: String, memberIDs: Set<String>, name: String, activityCount: Int)] = [:]
        let removedPersonKeys = Set(club.removedMemberIDs.map(club.canonicalMemberKey))

        func insert(memberID: String, memberName: String, activity: Int = 1) {
            let trimmedName = memberName.trimmedOrNil ?? "Unknown member"
            let resolvedMemberID = memberID.trimmedOrNil
            let key = resolvedMemberID.map(club.canonicalMemberKey)
                ?? "\(ClubMemberDigest.nameOnlyPrefix)\(trimmedName.lowercased())"
            guard !removedPersonKeys.contains(key) else { return }
            let existing = members[key]
            var memberIDs = existing?.memberIDs ?? []
            if let resolvedMemberID {
                memberIDs.insert(resolvedMemberID)
            }
            let representativeID: String
            if let resolvedMemberID, resolvedMemberID == club.creatorMemberID {
                representativeID = resolvedMemberID
            } else {
                representativeID = existing?.representativeID
                    ?? resolvedMemberID
                    ?? key
            }
            members[key] = (
                representativeID: representativeID,
                memberIDs: memberIDs,
                name: existing?.name.trimmedOrNil ?? trimmedName,
                activityCount: (existing?.activityCount ?? 0) + activity
            )
        }

        for submission in club.allSubmissions {
            insert(memberID: submission.submittedByMemberID, memberName: submission.submittedBy)
            for rating in submission.ratings ?? [] {
                insert(memberID: rating.memberID, memberName: rating.memberName)
            }
            for note in submission.notes ?? [] {
                insert(memberID: note.memberID, memberName: note.memberName)
            }
        }

        for meeting in club.allMeetings {
            insert(memberID: meeting.hostMemberID, memberName: meeting.hostName)
            for rsvp in meeting.rsvps ?? [] {
                insert(memberID: rsvp.memberID, memberName: rsvp.memberName)
            }
        }

        for poll in club.allSelectionPolls {
            for vote in poll.votes ?? [] {
                insert(memberID: vote.memberID, memberName: vote.memberName)
            }
        }

        for (memberID, name) in club.knownMemberRoster {
            insert(memberID: memberID, memberName: name, activity: 0)
        }

        return members
            .map {
                ClubMemberDigest(
                    id: $0.value.representativeID,
                    memberIDs: $0.value.memberIDs,
                    name: $0.value.name,
                    activityCount: $0.value.activityCount
                )
            }
            .sorted {
                if $0.activityCount != $1.activityCount { return $0.activityCount > $1.activityCount }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

enum MeetingReminderPlanner {
    static func reminderDates(scheduledAt: Date, offsetsMinutes: [Int], now: Date = .now) -> [Date] {
        offsetsMinutes
            .filter { $0 >= 0 }
            .map { scheduledAt.addingTimeInterval(TimeInterval(-$0 * 60)) }
            .filter { $0 > now && $0 <= scheduledAt }
            .sorted()
    }
}

struct MeetingReminderSchedule: Sendable {
    let identifiers: [String]
    let scheduledAt: Date
    let offsetsMinutes: [Int]
    let title: String
    let bookTitle: String?
}

enum MeetingReminderScheduler {
    static func schedule(for meeting: ClubMeeting) -> MeetingReminderSchedule {
        MeetingReminderSchedule(
            identifiers: identifiers(for: meeting),
            scheduledAt: meeting.scheduledAt,
            offsetsMinutes: meeting.reminderOffsets,
            title: meeting.displayTitle,
            bookTitle: meeting.bookSubmission?.displayTitle.trimmedOrNil
        )
    }

    static func scheduleReminders(_ schedule: MeetingReminderSchedule, replacing staleIdentifiers: [String] = []) async {
        let center = UNUserNotificationCenter.current()
        let activeIdentifiers = schedule.identifiers
        center.removePendingNotificationRequests(withIdentifiers: Array(Set(staleIdentifiers + activeIdentifiers)))

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }

            let reminderDates = MeetingReminderPlanner.reminderDates(
                scheduledAt: schedule.scheduledAt,
                offsetsMinutes: schedule.offsetsMinutes
            )

            for (index, reminderDate) in reminderDates.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = schedule.title
                content.body = reminderBody(for: schedule)
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: activeIdentifiers[safe: index] ?? "bookloom.meeting.\(index)",
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
            }
        } catch {
            // Notification permissions are user-controlled; scheduling failure should not block saving a meeting.
        }
    }

    static func identifiers(for meeting: ClubMeeting) -> [String] {
        meeting.reminderOffsets.enumerated().map { index, offset in
            "bookloom.meeting.\(meeting.persistentModelID).\(offset).\(index)"
        }
    }

    private static func reminderBody(for schedule: MeetingReminderSchedule) -> String {
        if let title = schedule.bookTitle {
            return "Your book club is meeting about \(title)."
        }
        return "Your book club meeting is coming up."
    }
}

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
    let name: String
    let activityCount: Int

    var isNameOnly: Bool { id.hasPrefix(Self.nameOnlyPrefix) }
}

enum ClubMemberCollector {
    static func collect(from club: BookClub) -> [ClubMemberDigest] {
        var members: [String: (name: String, activityCount: Int)] = [:]

        func insert(memberID: String, memberName: String, activity: Int = 1) {
            let trimmedName = memberName.trimmedOrNil ?? "Unknown member"
            let key = memberID.trimmedOrNil ?? "\(ClubMemberDigest.nameOnlyPrefix)\(trimmedName.lowercased())"
            let existing = members[key]
            members[key] = (
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
            .map { ClubMemberDigest(id: $0.key, name: $0.value.name, activityCount: $0.value.activityCount) }
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

enum MeetingReminderScheduler {
    static func scheduleReminders(for meeting: ClubMeeting) async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }

            center.removePendingNotificationRequests(withIdentifiers: identifiers(for: meeting))
            let reminderDates = MeetingReminderPlanner.reminderDates(
                scheduledAt: meeting.scheduledAt,
                offsetsMinutes: meeting.reminderOffsets
            )

            for (index, reminderDate) in reminderDates.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = meeting.displayTitle
                content.body = reminderBody(for: meeting)
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: identifiers(for: meeting)[safe: index] ?? "\(meeting.persistentModelID)-\(index)",
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

    private static func reminderBody(for meeting: ClubMeeting) -> String {
        if let title = meeting.bookSubmission?.displayTitle.trimmedOrNil {
            return "Your book club is meeting about \(title)."
        }
        return "Your book club meeting is coming up."
    }
}


import Foundation
import SwiftData

enum SelectionPollStatus: String, CaseIterable, Identifiable {
    case open
    case closed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .open: "Open"
        case .closed: "Closed"
        }
    }
}

@Model
final class SelectionPoll {
    static let maxRanks = 3

    var title: String = ""
    var createdAt: Date = Date.now
    var closesAt: Date? = nil
    var statusRaw: String = SelectionPollStatus.open.rawValue
    var isAnonymousResults: Bool = true
    var candidateIDsRaw: String = ""
    var winnerSubmissionID: String = ""

    var bookClub: BookClub? = nil

    @Relationship(deleteRule: .cascade, inverse: \BookVote.poll)
    var votes: [BookVote]? = nil

    init(
        title: String = "",
        candidates: [BookSubmission] = [],
        createdAt: Date = .now,
        closesAt: Date? = nil,
        isAnonymousResults: Bool = true
    ) {
        self.title = title
        self.createdAt = createdAt
        self.closesAt = closesAt
        self.isAnonymousResults = isAnonymousResults
        self.candidateIDsRaw = Self.encodeCandidateIDs(candidates.map(\.selectionID))
    }

    var status: SelectionPollStatus {
        get { SelectionPollStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var candidateIDs: [String] {
        get { Self.decodeIDs(candidateIDsRaw) }
        set { candidateIDsRaw = Self.encodeCandidateIDs(newValue) }
    }

    var displayTitle: String {
        title.trimmedOrNil ?? "Next Book Vote"
    }

    var isOpen: Bool {
        guard status == .open else { return false }
        guard let closesAt else { return true }
        return closesAt > .now
    }

    @discardableResult
    func replaceVote(memberID: String, memberName: String, rankedSubmissionIDs: [String], updatedAt: Date = .now) -> BookVote {
        let normalizedID = memberID.trimmedOrNil ?? memberName.trimmed
        let sanitizedRanks = Self.uniqueRankedIDs(rankedSubmissionIDs, allowedIDs: Set(candidateIDs))

        if let existing = (votes ?? []).first(where: { $0.matches(memberID: normalizedID, memberName: memberName) }) {
            existing.memberID = normalizedID
            existing.memberName = memberName
            existing.rankedSubmissionIDs = sanitizedRanks
            existing.updatedAt = updatedAt
            return existing
        }

        let vote = BookVote(
            memberID: normalizedID,
            memberName: memberName,
            rankedSubmissionIDs: sanitizedRanks,
            updatedAt: updatedAt
        )
        var updatedVotes = votes ?? []
        updatedVotes.append(vote)
        votes = updatedVotes
        vote.poll = self
        return vote
    }

    func vote(for memberID: String, memberName: String) -> BookVote? {
        let normalizedID = memberID.trimmedOrNil ?? memberName.trimmed
        return (votes ?? []).first { $0.matches(memberID: normalizedID, memberName: memberName) }
    }

    static func uniqueRankedIDs(_ ids: [String], allowedIDs: Set<String>) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where allowedIDs.contains(id) && !seen.contains(id) {
            seen.insert(id)
            result.append(id)
            if result.count == maxRanks { break }
        }
        return result
    }

    static func encodeCandidateIDs(_ ids: [String]) -> String {
        ids.filter { !$0.isEmpty }.joined(separator: ",")
    }

    static func decodeIDs(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }
}

@Model
final class BookVote {
    var memberID: String = ""
    var memberName: String = ""
    var rankedSubmissionIDsRaw: String = ""
    var updatedAt: Date = Date.now

    var poll: SelectionPoll? = nil

    init(
        memberID: String = "",
        memberName: String = "",
        rankedSubmissionIDs: [String] = [],
        updatedAt: Date = .now
    ) {
        self.memberID = memberID
        self.memberName = memberName
        self.rankedSubmissionIDsRaw = SelectionPoll.encodeCandidateIDs(rankedSubmissionIDs)
        self.updatedAt = updatedAt
    }

    var rankedSubmissionIDs: [String] {
        get { SelectionPoll.decodeIDs(rankedSubmissionIDsRaw) }
        set { rankedSubmissionIDsRaw = SelectionPoll.encodeCandidateIDs(newValue) }
    }

    func matches(memberID: String, memberName: String) -> Bool {
        if !memberID.isEmpty, self.memberID == memberID {
            return true
        }
        return self.memberID.isEmpty && self.memberName == memberName
    }
}

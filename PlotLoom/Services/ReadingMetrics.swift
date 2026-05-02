import Foundation

struct BookClubSubmissionSections {
    let current: BookSubmission?
    let proposed: [BookSubmission]
    let completed: [BookSubmission]
    let skipped: [BookSubmission]

    init(submissions: [BookSubmission]) {
        var currents: [BookSubmission] = []
        var proposed: [BookSubmission] = []
        var completed: [BookSubmission] = []
        var skipped: [BookSubmission] = []

        for submission in submissions {
            switch submission.status {
            case .current: currents.append(submission)
            case .proposed: proposed.append(submission)
            case .completed: completed.append(submission)
            case .skipped: skipped.append(submission)
            }
        }

        self.current = currents
            .max { ($0.pickedAt ?? $0.submittedAt) < ($1.pickedAt ?? $1.submittedAt) }
        self.proposed = proposed.sorted { $0.submittedAt < $1.submittedAt }
        self.completed = completed.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        self.skipped = skipped.sorted { $0.submittedAt > $1.submittedAt }
    }
}

struct BookClubMetrics: Equatable {
    let currentCount: Int
    let proposedCount: Int
    let completedCount: Int
    let skippedCount: Int
    let ratingCount: Int
    let noteCount: Int
    let memberCount: Int

    var totalSubmissionCount: Int {
        currentCount + proposedCount + completedCount + skippedCount
    }

    init(submissions: [BookSubmission]) {
        var current = 0, proposed = 0, completed = 0, skipped = 0
        var ratings = 0, notes = 0
        var members = Set<String>()

        for submission in submissions {
            switch submission.status {
            case .current: current += 1
            case .proposed: proposed += 1
            case .completed: completed += 1
            case .skipped: skipped += 1
            }

            Self.insert(submission.submittedBy, into: &members)
            for rating in submission.ratings ?? [] {
                ratings += 1
                Self.insert(rating.memberName, into: &members)
            }
            for note in submission.notes ?? [] {
                notes += 1
                Self.insert(note.memberName, into: &members)
            }
        }

        currentCount = current
        proposedCount = proposed
        completedCount = completed
        skippedCount = skipped
        ratingCount = ratings
        noteCount = notes
        memberCount = members.count
    }

    private static func insert(_ value: String, into members: inout Set<String>) {
        guard let trimmed = value.trimmedOrNil else { return }
        members.insert(trimmed)
    }
}

struct RatingSummary: Equatable {
    let count: Int
    let average: Double?

    init(ratings: [Rating]) {
        count = ratings.count
        guard !ratings.isEmpty else {
            average = nil
            return
        }
        let total = ratings.reduce(0) { $0 + $1.stars }
        average = Double(total) / Double(ratings.count)
    }

    var displayValue: String {
        guard let average else { return "No ratings" }
        return String(format: "%.1f", average)
    }
}

extension BookClub {
    var allSubmissions: [BookSubmission] {
        submissions ?? []
    }

    var sections: BookClubSubmissionSections {
        BookClubSubmissionSections(submissions: allSubmissions)
    }

    var metrics: BookClubMetrics {
        BookClubMetrics(submissions: allSubmissions)
    }

    var displayedMemberCount: Int {
        max(shareParticipantCount, metrics.memberCount)
    }
}

extension BookSubmission {
    var displayTitle: String {
        title.trimmedOrNil ?? "Untitled"
    }

    var displayAuthor: String {
        author.trimmed
    }

    var coverImageURL: URL? {
        URL(string: coverURL.trimmed)
    }

    var displayDescription: String {
        bookDescription.trimmed
    }

    var displaySubmitter: String {
        submittedBy.trimmedOrNil ?? "Unknown member"
    }

    var ratingSummary: RatingSummary {
        RatingSummary(ratings: ratings ?? [])
    }
}

import Foundation
import SwiftData

enum AppLaunchOptions {
    static let seedSampleDataArgument = "-SeedSampleData"
    static let screenshotRouteArgument = "-screenshotRoute"

    static var isSampleDataEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(seedSampleDataArgument)
    }

    static var screenshotRoute: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: screenshotRouteArgument),
              index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }
}

enum ScreenshotSampleData {
    static let memberName = "Maya Chen"
    static let memberID = "sample-member-maya"

    static func populate(container: ModelContainer) {
        let context = ModelContext(container)
        populate(context: context)
    }

    static func populate(context: ModelContext) {
        let calendar = Calendar.current
        let club = BookClub(
            name: "Riverside Reading Circle",
            createdAt: calendar.date(byAdding: .month, value: -9, to: .now) ?? .now
        )
        club.shareIsActive = true
        club.shareParticipantCount = 6
        context.insert(club)

        let current = makeSubmission(
            title: "The Atlas of Small Fires",
            author: "Elena Park",
            isbn: "9780000001001",
            description: "A layered family mystery about climate memory, old maps, and the stories people keep to protect one another.",
            year: 2024,
            submitter: "Maya Chen",
            memberID: memberID,
            daysAgo: 34,
            status: .current
        )
        current.pickedAt = calendar.date(byAdding: .day, value: -12, to: .now)
        insert(current, into: club, context: context)

        let proposals = [
            makeSubmission(
                title: "Northbound After Midnight",
                author: "Jonas Reed",
                isbn: "9780000001002",
                description: "A night-train novel with locked-room suspense, complicated friendships, and one very unreliable itinerary.",
                year: 2025,
                submitter: "Priya Shah",
                memberID: "sample-member-priya",
                daysAgo: 18,
                status: .proposed
            ),
            makeSubmission(
                title: "The Salt Orchard",
                author: "Camila Torres",
                isbn: "9780000001003",
                description: "Three siblings return to a coastal farm and find the family business hiding a century of debts and bargains.",
                year: 2023,
                submitter: "Owen Brooks",
                memberID: "sample-member-owen",
                daysAgo: 14,
                status: .proposed
            ),
            makeSubmission(
                title: "A Practical Guide to Time Travel",
                author: "Nadia Bell",
                isbn: "9780000001004",
                description: "A playful speculative story about historians, paradoxes, and the ethics of editing one perfect afternoon.",
                year: 2022,
                submitter: "Lena Ortiz",
                memberID: "sample-member-lena",
                daysAgo: 9,
                status: .proposed
            ),
            makeSubmission(
                title: "The Moonlit Index",
                author: "Rowan Vale",
                isbn: "9780000001005",
                description: "A librarian discovers that the town archive changes every full moon, revealing the lives people tried to erase.",
                year: 2025,
                submitter: "Sam Rivera",
                memberID: "sample-member-sam",
                daysAgo: 3,
                status: .proposed
            )
        ]
        proposals.forEach { insert($0, into: club, context: context) }

        let completed = [
            makeSubmission(
                title: "The Paper Lantern Society",
                author: "June Mori",
                isbn: "9780000001006",
                description: "A warm intergenerational story about translation, grief, and a neighborhood bookshop that refuses to close.",
                year: 2021,
                submitter: "Lena Ortiz",
                memberID: "sample-member-lena",
                daysAgo: 92,
                status: .completed
            ),
            makeSubmission(
                title: "Where the River Keeps Its Names",
                author: "Miles Adair",
                isbn: "9780000001007",
                description: "A braided historical novel following one river town through floods, secrets, and second chances.",
                year: 2020,
                submitter: "Owen Brooks",
                memberID: "sample-member-owen",
                daysAgo: 142,
                status: .completed
            )
        ]
        completed[0].pickedAt = calendar.date(byAdding: .day, value: -76, to: .now)
        completed[0].completedAt = calendar.date(byAdding: .day, value: -39, to: .now)
        completed[1].pickedAt = calendar.date(byAdding: .day, value: -126, to: .now)
        completed[1].completedAt = calendar.date(byAdding: .day, value: -84, to: .now)
        completed.forEach { insert($0, into: club, context: context) }

        addRatingsAndNotes(to: current, context: context)
        addCompletedBookNotes(to: completed, context: context)
        addDiscussionPrompts(to: current, context: context)
        addMeetings(to: club, current: current, completed: completed, context: context)
        addPoll(to: club, proposals: proposals, context: context)

        try? context.save()
    }

    private static func makeSubmission(
        title: String,
        author: String,
        isbn: String,
        description: String,
        year: Int,
        submitter: String,
        memberID: String,
        daysAgo: Int,
        status: BookSubmissionStatus
    ) -> BookSubmission {
        let submittedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return BookSubmission(
            title: title,
            author: author,
            isbn: isbn,
            bookDescription: description,
            publishedYear: year,
            submittedBy: submitter,
            submittedByMemberID: memberID,
            submittedAt: submittedAt,
            status: status
        )
    }

    private static func insert(_ submission: BookSubmission, into club: BookClub, context: ModelContext) {
        context.insert(submission)
        club.addSubmission(submission)
    }

    private static func addRatingsAndNotes(to submission: BookSubmission, context: ModelContext) {
        addRating(5, memberID: memberID, memberName: memberName, to: submission, context: context)
        addRating(4, memberID: "sample-member-priya", memberName: "Priya Shah", to: submission, context: context)
        addRating(5, memberID: "sample-member-lena", memberName: "Lena Ortiz", to: submission, context: context)
        addRating(4, memberID: "sample-member-owen", memberName: "Owen Brooks", to: submission, context: context)

        addNote("Loved the alternating timelines. The map fragments make this feel made for discussion.", memberID: memberID, memberName: memberName, to: submission, context: context)
        addNote("Flag chapter 18 for the meeting. The fire tower scene changes how I read the narrator.", memberID: "sample-member-priya", memberName: "Priya Shah", to: submission, context: context)
        addNote("Bring up the ending. I am still not convinced the apology lands.", memberID: "sample-member-sam", memberName: "Sam Rivera", to: submission, context: context)
    }

    private static func addCompletedBookNotes(to submissions: [BookSubmission], context: ModelContext) {
        guard submissions.count >= 2 else { return }
        addRating(5, memberID: "sample-member-lena", memberName: "Lena Ortiz", to: submissions[0], context: context)
        addRating(4, memberID: memberID, memberName: memberName, to: submissions[0], context: context)
        addNote("Best turnout of the season. Keep this author on the future picks list.", memberID: "sample-member-lena", memberName: "Lena Ortiz", to: submissions[0], context: context)

        addRating(4, memberID: "sample-member-owen", memberName: "Owen Brooks", to: submissions[1], context: context)
        addRating(3, memberID: "sample-member-sam", memberName: "Sam Rivera", to: submissions[1], context: context)
        addNote("Slower middle, but the final river chapter made the whole choice worth it.", memberID: "sample-member-owen", memberName: "Owen Brooks", to: submissions[1], context: context)
    }

    private static func addRating(_ stars: Int, memberID: String, memberName: String, to submission: BookSubmission, context: ModelContext) {
        let rating = Rating(memberID: memberID, memberName: memberName, stars: stars)
        rating.submission = submission
        context.insert(rating)
    }

    private static func addNote(_ text: String, memberID: String, memberName: String, to submission: BookSubmission, context: ModelContext) {
        let note = BookNote(memberID: memberID, memberName: memberName, text: text)
        note.submission = submission
        context.insert(note)
    }

    private static func addDiscussionPrompts(to submission: BookSubmission, context: ModelContext) {
        let questions = [
            "Which character is most honest about what the town owes the next generation?",
            "How does the map motif change from evidence into inheritance?",
            "Would the final reveal have worked if the narrator had told the story chronologically?"
        ]
        for (index, question) in questions.enumerated() {
            let prompt = DiscussionPrompt(question: question, orderIndex: index, source: .starter)
            prompt.submission = submission
            context.insert(prompt)
        }
    }

    private static func addMeetings(
        to club: BookClub,
        current: BookSubmission,
        completed: [BookSubmission],
        context: ModelContext
    ) {
        let calendar = Calendar.current
        let upcoming = ClubMeeting(
            title: "Small Fires Discussion",
            scheduledAt: calendar.date(byAdding: .day, value: 6, to: .now) ?? .now,
            hostName: "Lena Ortiz",
            hostMemberID: "sample-member-lena",
            location: "Lena's kitchen + FaceTime",
            meetingURL: "https://facetime.apple.com/join/example",
            agenda: "Open with favorite passages, settle next month's shortlist, then save ten minutes for dessert assignments."
        )
        context.insert(upcoming)
        club.addMeeting(upcoming)
        upcoming.bookSubmission = current
        addRSVP(memberID: memberID, memberName: memberName, status: .attending, note: "Bringing almond cake", to: upcoming, context: context)
        addRSVP(memberID: "sample-member-priya", memberName: "Priya Shah", status: .attending, note: "Has discussion questions", to: upcoming, context: context)
        addRSVP(memberID: "sample-member-sam", memberName: "Sam Rivera", status: .maybe, note: "Joining remotely", to: upcoming, context: context)

        guard let lastRead = completed.first else { return }
        let past = ClubMeeting(
            title: "Paper Lantern Society Wrap-up",
            scheduledAt: calendar.date(byAdding: .day, value: -41, to: .now) ?? .now,
            hostName: "Maya Chen",
            hostMemberID: memberID,
            location: "Riverside Library Room B",
            agenda: "Rated the book, compared favorite translations, and picked the spring theme."
        )
        past.completedAt = calendar.date(byAdding: .day, value: -41, to: .now)
        context.insert(past)
        club.addMeeting(past)
        past.bookSubmission = lastRead
        addRSVP(memberID: memberID, memberName: memberName, status: .attending, note: "", to: past, context: context)
        addRSVP(memberID: "sample-member-lena", memberName: "Lena Ortiz", status: .attending, note: "Hosted", to: past, context: context)
    }

    private static func addRSVP(memberID: String, memberName: String, status: MeetingRSVPStatus, note: String, to meeting: ClubMeeting, context: ModelContext) {
        let rsvp = meeting.upsertRSVP(memberID: memberID, memberName: memberName, status: status, bringingNote: note)
        context.insert(rsvp)
    }

    private static func addPoll(to club: BookClub, proposals: [BookSubmission], context: ModelContext) {
        let poll = SelectionPoll(
            title: "June Pick Shortlist",
            candidates: proposals,
            createdAt: Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now,
            closesAt: Calendar.current.date(byAdding: .day, value: 3, to: .now),
            isAnonymousResults: true
        )
        context.insert(poll)
        club.addSelectionPoll(poll)

        let votes = [
            ("sample-member-maya", "Maya Chen", [0, 2, 1]),
            ("sample-member-priya", "Priya Shah", [1, 0, 3]),
            ("sample-member-lena", "Lena Ortiz", [2, 3, 0]),
            ("sample-member-owen", "Owen Brooks", [0, 1, 2])
        ]
        for vote in votes {
            let rankedIDs = vote.2.compactMap { index in
                proposals.indices.contains(index) ? proposals[index].selectionID : nil
            }
            let bookVote = poll.replaceVote(memberID: vote.0, memberName: vote.1, rankedSubmissionIDs: rankedIDs)
            context.insert(bookVote)
        }
    }
}

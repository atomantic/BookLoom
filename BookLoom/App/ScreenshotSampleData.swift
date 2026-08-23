import Foundation
import SwiftData

enum AppLaunchOptions {
    static let seedSampleDataArgument = "-SeedSampleData"
    static let screenshotRouteArgument = "-screenshotRoute"
    static let screenshotDynamicTypeArgument = "-screenshotDynamicType"

    static let isSampleDataEnabled: Bool = ProcessInfo.processInfo.arguments.contains(seedSampleDataArgument)

    static let screenshotRoute: ScreenshotRoute? = launchArgument(named: screenshotRouteArgument).map(ScreenshotRoute.init(rawValueOrBooks:))

    /// Optional Dynamic Type override used by accessibility screenshot variants.
    /// Accepted values match `DynamicTypeSize` raw cases:
    /// `xSmall`, `small`, `medium`, `large`, `xLarge`, `xxLarge`, `xxxLarge`,
    /// `accessibility1`…`accessibility5`.
    static let screenshotDynamicType: String? = launchArgument(named: screenshotDynamicTypeArgument)

    private static func launchArgument(named name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: name), index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension DynamicTypeSize {
    /// Resolve a `DynamicTypeSize` from the launch-arg string (e.g. "accessibility5").
    static func fromScreenshotArgument(_ raw: String?) -> DynamicTypeSize? {
        guard let raw else { return nil }
        switch raw {
        case "xSmall": return .xSmall
        case "small": return .small
        case "medium": return .medium
        case "large": return .large
        case "xLarge": return .xLarge
        case "xxLarge": return .xxLarge
        case "xxxLarge": return .xxxLarge
        case "accessibility1": return .accessibility1
        case "accessibility2": return .accessibility2
        case "accessibility3": return .accessibility3
        case "accessibility4": return .accessibility4
        case "accessibility5": return .accessibility5
        default: return nil
        }
    }
}
#endif

enum ScreenshotSampleData {
    static let memberName = "Maya Chen"
    static let memberID = "sample-member-maya"

    static func populate(container: ModelContainer) {
        let context = ModelContext(container)
        populate(context: context)
    }

    static func populate(context: ModelContext) {
        seedBundledCovers()
        if AppLaunchOptions.screenshotRoute?.clearsSampleImports == true {
            clearShelfImports()
        } else {
            seedShelfImports()
        }

        let calendar = Calendar.current
        let club = BookClub(
            name: "Riverside Reading Circle",
            createdAt: calendar.date(byAdding: .month, value: -9, to: .now) ?? .now
        )
        club.shareIsActive = true
        club.shareParticipantCount = 6
        club.creatorMemberID = memberID
        club.adminMemberIDs = ["sample-member-lena"]
        club.knownMemberRoster = [
            memberID: memberName,
            "sample-member-priya": "Priya Shah",
            "sample-member-owen": "Owen Brooks",
            "sample-member-lena": "Lena Ortiz",
            "sample-member-sam": "Sam Rivera",
            "sample-member-noah": "Noah Kim"
        ]
        context.insert(club)

        let current = makeSubmission(
            title: "Piranesi",
            author: "Susanna Clarke",
            isbn: "9781635575637",
            description: "A dreamlike novel about a man living in an impossible house of endless halls, statues, tides, and hidden memory.",
            year: 2020,
            coverID: 10226290,
            externalID: "/works/OL20893680W",
            submitter: "Maya Chen",
            memberID: memberID,
            daysAgo: 34,
            status: .current
        )
        current.pickedAt = calendar.date(byAdding: .day, value: -12, to: .now)
        insert(current, into: club, context: context)

        let proposals = [
            makeSubmission(
                title: "Dungeon Crawler Carl",
                author: "Matt Dinniman",
                isbn: "9798988744405",
                description: "A fast, chaotic LitRPG adventure about a man, his cat, and a deadly alien dungeon broadcast as entertainment.",
                year: 2020,
                coverID: 15143022,
                externalID: "/works/OL24593432W",
                submitter: "Priya Shah",
                memberID: "sample-member-priya",
                daysAgo: 18,
                status: .proposed
            ),
            makeSubmission(
                title: "Accelerando",
                author: "Charles Stross",
                isbn: "1841493899",
                description: "A dense, idea-driven science fiction novel following one family through accelerating technological change.",
                year: 2005,
                coverID: 284259,
                externalID: "/works/OL2465670W",
                submitter: "Owen Brooks",
                memberID: "sample-member-owen",
                daysAgo: 14,
                status: .proposed
            ),
            makeSubmission(
                title: "Project Hail Mary",
                author: "Andy Weir",
                isbn: "9780593135204",
                description: "A lone astronaut wakes with no memory and must solve an extinction-level crisis with an unexpected ally.",
                year: 2021,
                coverID: 11200092,
                externalID: "/works/OL21745884W",
                submitter: "Lena Ortiz",
                memberID: "sample-member-lena",
                daysAgo: 9,
                status: .proposed
            ),
            makeSubmission(
                title: "Tomorrow, and Tomorrow, and Tomorrow",
                author: "Gabrielle Zevin",
                isbn: "9780593321201",
                description: "Two friends and creative partners build games together while navigating ambition, grief, intimacy, and art.",
                year: 2022,
                coverID: 12859975,
                externalID: "/works/OL26004554W",
                submitter: "Sam Rivera",
                memberID: "sample-member-sam",
                daysAgo: 3,
                status: .proposed
            ),
            makeSubmission(
                title: "The Ministry of Time",
                author: "Kaliane Bradley",
                isbn: "9781668045145",
                description: "A civil servant assigned to a time-displaced Victorian explorer finds bureaucracy, history, and desire colliding.",
                year: 2024,
                coverID: 14836068,
                externalID: "/works/OL36524472W",
                submitter: "Noah Kim",
                memberID: "sample-member-noah",
                daysAgo: 2,
                status: .proposed
            ),
            makeSubmission(
                title: "Sea of Tranquility",
                author: "Emily St. John Mandel",
                isbn: "9780593321447",
                description: "A time-spanning novel about art, exile, pandemics, and the possibility that reality is less fixed than it seems.",
                year: 2022,
                coverID: 12695663,
                externalID: "/works/OL24416598W",
                submitter: "Maya Chen",
                memberID: memberID,
                daysAgo: 1,
                status: .proposed
            )
        ]
        proposals.forEach { insert($0, into: club, context: context) }

        let completed = [
            makeSubmission(
                title: "The Thursday Murder Club",
                author: "Richard Osman",
                isbn: "9780241988268",
                description: "Four residents of a retirement village turn their cold-case hobby toward a fresh murder investigation.",
                year: 2020,
                coverID: 10201431,
                externalID: "/works/OL20878311W",
                submitter: "Lena Ortiz",
                memberID: "sample-member-lena",
                daysAgo: 92,
                status: .completed
            ),
            makeSubmission(
                title: "Klara and the Sun",
                author: "Kazuo Ishiguro",
                isbn: "9780571364886",
                description: "An Artificial Friend observes human longing, illness, and devotion from the edge of a changing family.",
                year: 2021,
                coverID: 10648686,
                externalID: "/works/OL20883297W",
                submitter: "Owen Brooks",
                memberID: "sample-member-owen",
                daysAgo: 142,
                status: .completed
            ),
            makeSubmission(
                title: "A Psalm for the Wild-Built",
                author: "Becky Chambers",
                isbn: "9781250236210",
                description: "A gentle solarpunk novella about a tea monk, a robot, purpose, rest, and the questions that survive comfort.",
                year: 2021,
                coverID: 11908445,
                externalID: "/works/OL22124808W",
                submitter: "Priya Shah",
                memberID: "sample-member-priya",
                daysAgo: 201,
                status: .completed
            ),
            makeSubmission(
                title: "The Long Way to a Small, Angry Planet",
                author: "Becky Chambers",
                isbn: "9780062444134",
                description: "A warm, character-driven space opera about the crew of a tunneling ship and the families people choose.",
                year: 2014,
                coverID: 8228691,
                externalID: "/works/OL17301444W",
                submitter: "Noah Kim",
                memberID: "sample-member-noah",
                daysAgo: 251,
                status: .completed
            )
        ]
        completed[0].pickedAt = calendar.date(byAdding: .day, value: -76, to: .now)
        completed[0].completedAt = calendar.date(byAdding: .day, value: -39, to: .now)
        completed[1].pickedAt = calendar.date(byAdding: .day, value: -126, to: .now)
        completed[1].completedAt = calendar.date(byAdding: .day, value: -84, to: .now)
        completed[2].pickedAt = calendar.date(byAdding: .day, value: -184, to: .now)
        completed[2].completedAt = calendar.date(byAdding: .day, value: -153, to: .now)
        completed[3].pickedAt = calendar.date(byAdding: .day, value: -230, to: .now)
        completed[3].completedAt = calendar.date(byAdding: .day, value: -198, to: .now)
        completed.forEach { insert($0, into: club, context: context) }
        seedLibraryBooks(context: context)

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
        coverID: Int,
        externalID: String,
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
            coverURL: BookMetadataProvider.openLibraryCoverURL(coverID: coverID)?.absoluteString ?? "",
            externalProvider: BookMetadataProvider.openLibrary.rawValue,
            externalID: externalID,
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

    private static func seedLibraryBooks(context: ModelContext) {
        let books = [
            makeLibraryBook(
                title: "Piranesi",
                author: "Susanna Clarke",
                isbn: "9781635575637",
                description: "A keeper copy for marginalia during Riverside Reading Circle discussions.",
                year: 2020,
                coverID: 10226290,
                addedDaysAgo: 122,
                shelfLocation: "Living Room - Favorites",
                format: .hardcover,
                isSigned: true,
                priceCents: 2800,
                ratingStars: 5,
                didRead: true
            ),
            makeLibraryBook(
                title: "Dungeon Crawler Carl",
                author: "Matt Dinniman",
                isbn: "9798988744405",
                description: "Loaned after Priya's pitch for the next chaotic group read.",
                year: 2020,
                coverID: 15143022,
                addedDaysAgo: 35,
                shelfLocation: "Office - TBR",
                format: .paperback,
                isSigned: false,
                priceCents: 1899,
                loanedTo: "Owen Brooks",
                ratingStars: 4,
                didRead: true,
                didListen: true
            ),
            makeLibraryBook(
                title: "Project Hail Mary",
                author: "Andy Weir",
                isbn: "9780593135204",
                description: "Backup copy for gifting when the shortlist lands with new members.",
                year: 2021,
                coverID: 11200092,
                addedDaysAgo: 62,
                shelfLocation: "Hallway - Sci-Fi",
                format: .hardcover,
                isSigned: false,
                priceCents: 2495,
                intendedRecipient: "Sam Rivera",
                giftOccasion: "Birthday",
                ratingStars: 5,
                didRead: true,
                didListen: true
            ),
            makeLibraryBook(
                title: "Circe",
                author: "Madeline Miller",
                isbn: "9780316556347",
                description: "Personal copy parked on the desktop Shelf after a Goodreads share.",
                year: 2018,
                coverID: 8739376,
                addedDaysAgo: 18,
                shelfLocation: "Bedroom - Myth",
                format: .paperback,
                isSigned: false,
                priceCents: 1599,
                ratingStars: 4,
                didRead: true
            ),
            makeLibraryBook(
                title: "The House in the Cerulean Sea",
                author: "TJ Klune",
                isbn: "9781250217288",
                description: "Comfort reread copy kept for friends who need something kind after a long week.",
                year: 2020,
                coverID: 9312772,
                addedDaysAgo: 44,
                shelfLocation: "Guest Room - Loanable",
                format: .paperback,
                condition: .good,
                isSigned: false,
                priceCents: 1699,
                loanedTo: "Priya Shah",
                ratingStars: 5,
                didRead: true,
                privateNotes: "Loaned with the request that it come back before summer travel."
            ),
            makeLibraryBook(
                title: "A Psalm for the Wild-Built",
                author: "Becky Chambers",
                isbn: "9781250236210",
                description: "Small hardcover that keeps migrating between the nightstand and the tea shelf.",
                year: 2021,
                coverID: 11908445,
                addedDaysAgo: 155,
                shelfLocation: "Bedroom - Nightstand",
                format: .hardcover,
                condition: .veryGood,
                isSigned: false,
                priceCents: 2199,
                ratingStars: 5,
                didRead: true,
                didListen: true,
                privateNotes: "Favorite quote marked with the green tab."
            ),
            makeLibraryBook(
                title: "Babel",
                author: "R. F. Kuang",
                isbn: "9780063021426",
                description: "Dense annotated copy for language, empire, and translation notes.",
                year: 2022,
                coverID: 12953708,
                addedDaysAgo: 88,
                shelfLocation: "Office - Annotated",
                format: .hardcover,
                condition: .veryGood,
                isSigned: true,
                priceCents: 2799,
                ratingStars: 4,
                didRead: true,
                privateNotes: "Signed page is tucked behind the receipt from the launch event."
            ),
            makeLibraryBook(
                title: "The Left Hand of Darkness",
                author: "Ursula K. Le Guin",
                isbn: "9780441478125",
                description: "Older paperback kept for rereads and snowy-weather recommendations.",
                year: 1969,
                coverID: 8231856,
                addedDaysAgo: 510,
                shelfLocation: "Hallway - Classics",
                format: .paperback,
                condition: .readingCopy,
                isSigned: false,
                priceCents: 899,
                ratingStars: 5,
                didRead: true,
                privateNotes: "Spine is fragile; do not loan this copy."
            ),
            makeLibraryBook(
                title: "Rapture of the Nerds",
                author: "Cory Doctorow and Charles Stross",
                isbn: "9780765329103",
                description: "Fresh copy waiting for the club vote, with a backup audiobook queued.",
                year: 2012,
                coverID: 7250370,
                addedDaysAgo: 11,
                shelfLocation: "Office - TBR",
                format: .hardcover,
                condition: .new,
                isSigned: false,
                priceCents: 2499,
                intendedRecipient: "Maya Chen",
                giftOccasion: "Keep if not selected",
                didRead: true,
                didListen: true,
                privateNotes: "Compare the singularity jokes with Accelerando if this wins."
            ),
            makeLibraryBook(
                title: "A Memory Called Empire",
                author: "Arkady Martine",
                isbn: "9781250186430",
                description: "Finished as a library checkout, noted here for read history without needing a copy.",
                year: 2019,
                coverID: 8564783,
                addedDaysAgo: 74,
                shelfLocation: "",
                format: .ebook,
                condition: .good,
                isSigned: false,
                priceCents: 0,
                ratingStars: 4,
                didRead: true,
                isOwned: false,
                privateNotes: "Borrowed digitally; good enough to recommend, not a keeper copy."
            ),
            makeLibraryBook(
                title: "Accelerando",
                author: "Charles Stross",
                isbn: "9780441014156",
                description: "Hoping to grab a paperback at the next indie sale.",
                year: 2005,
                coverID: 284259,
                addedDaysAgo: 6,
                shelfLocation: "",
                format: .paperback,
                condition: .new,
                isSigned: false,
                priceCents: 0,
                isOwned: false,
                isWishlist: true,
                privateNotes: "Pair with Rapture of the Nerds for the cyberpunk theme."
            ),
            makeLibraryBook(
                title: "Murderbot",
                author: "Martha Wells",
                isbn: "9781250214713",
                description: "Want a signed copy if it ever shows up at a launch event.",
                year: 2017,
                coverID: 9157148,
                addedDaysAgo: 3,
                shelfLocation: "",
                format: .paperback,
                condition: .new,
                isSigned: false,
                priceCents: 0,
                isOwned: false,
                isWishlist: true
            )
        ]

        for book in books {
            if book.countsAsOwned {
                book.purchaseSource = "Local bookshop"
                book.purchaseDate = book.addedAt
            }
            context.insert(book)
        }
    }

    private static func makeLibraryBook(
        title: String,
        author: String,
        isbn: String,
        description: String,
        year: Int,
        coverID: Int,
        addedDaysAgo: Int,
        shelfLocation: String,
        format: LibraryBookFormat,
        condition: LibraryBookCondition = .good,
        isSigned: Bool,
        priceCents: Int,
        loanedTo: String = "",
        intendedRecipient: String = "",
        giftOccasion: String = "",
        ratingStars: Int = 0,
        didRead: Bool = false,
        didListen: Bool = false,
        isOwned: Bool = true,
        isWishlist: Bool = false,
        privateNotes: String = ""
    ) -> LibraryBook {
        let addedAt = Calendar.current.date(byAdding: .day, value: -addedDaysAgo, to: .now) ?? .now
        let book = LibraryBook(
            title: title,
            author: author,
            isbn: isbn,
            bookDescription: description,
            publishedYear: year,
            coverURL: BookMetadataProvider.openLibraryCoverURL(coverID: coverID)?.absoluteString ?? "",
            externalProvider: BookMetadataProvider.openLibrary.rawValue,
            externalID: "/covers/\(coverID)",
            addedAt: addedAt
        )
        book.format = format
        book.condition = condition
        book.shelfLocation = shelfLocation
        book.isSigned = isSigned
        book.purchasePriceCents = priceCents > 0 ? priceCents : nil
        book.personalRatingStars = min(max(ratingStars, 0), 5)
        book.didRead = didRead || didListen
        book.didListenToAudiobook = didListen
        book.isOwned = isOwned && !isWishlist
        book.isWishlist = isWishlist
        if !loanedTo.isEmpty {
            book.isOwned = true
            book.isWishlist = false
            book.isOnLoan = true
            book.loanedTo = loanedTo
            book.loanedAt = Calendar.current.date(byAdding: .day, value: -7, to: .now)
        }
        book.intendedRecipient = intendedRecipient
        book.giftOccasion = giftOccasion
        book.privateNotes = privateNotes
        return book
    }

    private static func addRatingsAndNotes(to submission: BookSubmission, context: ModelContext) {
        addRating(5, memberID: memberID, memberName: memberName, to: submission, context: context)
        addRating(4, memberID: "sample-member-priya", memberName: "Priya Shah", to: submission, context: context)
        addRating(5, memberID: "sample-member-lena", memberName: "Lena Ortiz", to: submission, context: context)
        addRating(4, memberID: "sample-member-owen", memberName: "Owen Brooks", to: submission, context: context)
        addRating(5, memberID: "sample-member-noah", memberName: "Noah Kim", to: submission, context: context)

        addNote("Loved the alternating timelines. The map fragments make this feel made for discussion.", memberID: memberID, memberName: memberName, to: submission, context: context)
        addNote("Flag chapter 18 for the meeting. The fire tower scene changes how I read the narrator.", memberID: "sample-member-priya", memberName: "Priya Shah", to: submission, context: context)
        addNote("Bring up the ending. I am still not convinced the apology lands.", memberID: "sample-member-sam", memberName: "Sam Rivera", to: submission, context: context)
        addNote("Pair this with the city-history article Lena shared before the meeting.", memberID: "sample-member-noah", memberName: "Noah Kim", to: submission, context: context)
    }

    private static func addCompletedBookNotes(to submissions: [BookSubmission], context: ModelContext) {
        guard submissions.count >= 2 else { return }
        addRating(5, memberID: "sample-member-lena", memberName: "Lena Ortiz", to: submissions[0], context: context)
        addRating(4, memberID: memberID, memberName: memberName, to: submissions[0], context: context)
        addNote("Best turnout of the season. Keep this author on the future picks list.", memberID: "sample-member-lena", memberName: "Lena Ortiz", to: submissions[0], context: context)

        addRating(4, memberID: "sample-member-owen", memberName: "Owen Brooks", to: submissions[1], context: context)
        addRating(3, memberID: "sample-member-sam", memberName: "Sam Rivera", to: submissions[1], context: context)
        addNote("Slower middle, but the final river chapter made the whole choice worth it.", memberID: "sample-member-owen", memberName: "Owen Brooks", to: submissions[1], context: context)

        if submissions.indices.contains(2) {
            addRating(5, memberID: "sample-member-priya", memberName: "Priya Shah", to: submissions[2], context: context)
            addRating(4, memberID: memberID, memberName: memberName, to: submissions[2], context: context)
            addNote("Short enough for a weeknight read, but it carried the best discussion about burnout.", memberID: "sample-member-priya", memberName: "Priya Shah", to: submissions[2], context: context)
        }

        if submissions.indices.contains(3) {
            addRating(5, memberID: "sample-member-noah", memberName: "Noah Kim", to: submissions[3], context: context)
            addRating(4, memberID: "sample-member-lena", memberName: "Lena Ortiz", to: submissions[3], context: context)
            addNote("Use this as the benchmark for cozy sci-fi when we choose the fall theme.", memberID: "sample-member-noah", memberName: "Noah Kim", to: submissions[3], context: context)
        }
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
        addRSVP(memberID: "sample-member-noah", memberName: "Noah Kim", status: .attending, note: "Can host next month", to: upcoming, context: context)

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
        addRSVP(memberID: "sample-member-noah", memberName: "Noah Kim", status: .declined, note: "Sent notes ahead", to: past, context: context)
    }

    private static func addRSVP(memberID: String, memberName: String, status: MeetingRSVPStatus, note: String, to meeting: ClubMeeting, context: ModelContext) {
        let rsvp = meeting.upsertRSVP(memberID: memberID, memberName: memberName, status: status, bringingNote: note)
        context.insert(rsvp)
    }


    private static let bundledCoverNames: [Int: String] = [
        10226290: "piranesi",
        15143022: "dungeon_crawler_carl",
        284259: "accelerando",
        11200092: "project_hail_mary",
        12859975: "tomorrow",
        10201431: "thursday_murder_club",
        10648686: "klara_and_the_sun",
        8739376: "circe",
        9312772: "cerulean_sea",
        7250370: "rapture_of_the_nerds",
        9157148: "murderbot"
    ]

    private static func seedBundledCovers() {
        let mappings: [(url: URL, data: Data)] = bundledCoverNames.compactMap { coverID, resourceName in
            guard let url = BookMetadataProvider.openLibraryCoverURL(coverID: coverID),
                  let path = Bundle.main.path(forResource: resourceName, ofType: "jpg"),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                return nil
            }
            return (url, data)
        }
        BookCoverCache.seedSync(mappings)
    }

    /// Pre-populate the screenshot-only import queue with two resolved
    /// Goodreads shares so the Club → Imports segment has visible content during
    /// capture. Single batched write — replaces any prior queue, no merge with
    /// stale screenshot reruns.
    private static func seedShelfImports() {
        let candidates: [(url: URL, candidate: BookMetadataCandidate, daysAgo: Int)] = [
            (
                URL(string: "https://www.goodreads.com/book/show/35959740-circe")!,
                BookMetadataCandidate(
                    provider: .goodreads,
                    externalID: "35959740",
                    title: "Circe",
                    authors: ["Madeline Miller"],
                    publishedYear: 2018,
                    isbn: "9780316556347",
                    coverURL: BookMetadataProvider.openLibraryCoverURL(coverID: 8739376),
                    description: "Banished to a deserted island, the witch-goddess Circe forges her own power on the edge of the Olympian world.",
                    sourceURL: URL(string: "https://www.goodreads.com/book/show/35959740-circe")
                ),
                2
            ),
            (
                URL(string: "https://www.goodreads.com/book/show/45047384-the-house-in-the-cerulean-sea")!,
                BookMetadataCandidate(
                    provider: .goodreads,
                    externalID: "45047384",
                    title: "The House in the Cerulean Sea",
                    authors: ["TJ Klune"],
                    publishedYear: 2020,
                    isbn: "9781250217288",
                    coverURL: BookMetadataProvider.openLibraryCoverURL(coverID: 9312772),
                    description: "A caseworker for magical youth is sent to inspect a remote orphanage and discovers a found-family worth fighting for.",
                    sourceURL: URL(string: "https://www.goodreads.com/book/show/45047384-the-house-in-the-cerulean-sea")
                ),
                1
            )
        ]

        let calendar = Calendar.current
        let entries: [SharedImportInbox.PendingImport] = candidates.map { input in
            let enqueuedAt = calendar.date(byAdding: .day, value: -input.daysAgo, to: .now) ?? .now
            var entry = SharedImportInbox.PendingImport(url: input.url, enqueuedAt: enqueuedAt)
            entry.apply(input.candidate, fetchedAt: enqueuedAt)
            return entry
        }
        SharedImportInbox.replaceAll(entries, defaults: .standard, fileURL: nil)
    }

    private static func clearShelfImports() {
        SharedImportInbox.clear(defaults: .standard, fileURL: nil)
        SharedImportInbox.clear(defaults: SharedImportInbox.defaults, fileURL: nil)
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
            ("sample-member-maya", "Maya Chen", [0, 2, 5, 1]),
            ("sample-member-priya", "Priya Shah", [1, 0, 3, 4]),
            ("sample-member-lena", "Lena Ortiz", [2, 3, 0, 5]),
            ("sample-member-owen", "Owen Brooks", [0, 1, 2, 4]),
            ("sample-member-noah", "Noah Kim", [4, 5, 1, 0])
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

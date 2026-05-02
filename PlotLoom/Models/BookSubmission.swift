import Foundation
import SwiftData

enum BookSubmissionStatus: String, CaseIterable, Identifiable {
    case proposed
    case current
    case completed
    case skipped

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .proposed: "Proposed"
        case .current: "Currently Reading"
        case .completed: "Completed"
        case .skipped: "Skipped"
        }
    }
}

@Model
final class BookSubmission {
    var title: String = ""
    var author: String = ""
    var isbn: String = ""
    var submittedBy: String = ""
    var submittedAt: Date = Date.now
    var statusRaw: String = BookSubmissionStatus.proposed.rawValue
    var pickedAt: Date? = nil
    var completedAt: Date? = nil
    var bookDescription: String = ""
    var publishedYear: Int? = nil
    var coverURL: String = ""
    var externalProvider: String = ""
    var externalID: String = ""

    @Attribute(.externalStorage)
    var coverData: Data? = nil

    var bookClub: BookClub? = nil

    @Relationship(deleteRule: .cascade, inverse: \Rating.submission)
    var ratings: [Rating]? = nil

    @Relationship(deleteRule: .cascade, inverse: \BookNote.submission)
    var notes: [BookNote]? = nil

    var status: BookSubmissionStatus {
        get { BookSubmissionStatus(rawValue: statusRaw) ?? .proposed }
        set { statusRaw = newValue.rawValue }
    }

    init(
        title: String = "",
        author: String = "",
        isbn: String = "",
        bookDescription: String = "",
        publishedYear: Int? = nil,
        coverURL: String = "",
        externalProvider: String = "",
        externalID: String = "",
        submittedBy: String = "",
        submittedAt: Date = .now,
        status: BookSubmissionStatus = .proposed
    ) {
        self.title = title
        self.author = author
        self.isbn = isbn
        self.bookDescription = bookDescription
        self.publishedYear = publishedYear
        self.coverURL = coverURL
        self.externalProvider = externalProvider
        self.externalID = externalID
        self.submittedBy = submittedBy
        self.submittedAt = submittedAt
        self.statusRaw = status.rawValue
    }
}

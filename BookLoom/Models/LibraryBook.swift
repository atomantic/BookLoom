import Foundation
import SwiftData

enum LibraryBookFormat: String, CaseIterable, Identifiable {
    case hardcover
    case paperback
    case ebook
    case audiobook
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hardcover: return "Hardcover"
        case .paperback: return "Paperback"
        case .ebook: return "E-book"
        case .audiobook: return "Audiobook"
        case .other: return "Other"
        }
    }
}

enum LibraryBookCondition: String, CaseIterable, Identifiable {
    case new
    case veryGood
    case good
    case fair
    case readingCopy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .new: return "New"
        case .veryGood: return "Very Good"
        case .good: return "Good"
        case .fair: return "Fair"
        case .readingCopy: return "Reading Copy"
        }
    }
}

@Model
final class LibraryBook {
    var libraryID: String = UUID().uuidString
    var title: String = ""
    var author: String = ""
    var isbn: String = ""
    var bookDescription: String = ""
    var publishedYear: Int? = nil
    var coverURL: String = ""
    var externalProvider: String = ""
    var externalID: String = ""
    var sourceURLString: String = ""
    var addedAt: Date = Date.now
    var updatedAt: Date = Date.now

    var formatRaw: String = LibraryBookFormat.hardcover.rawValue
    var conditionRaw: String = LibraryBookCondition.good.rawValue
    var shelfLocation: String = ""
    var isSigned: Bool = false
    var purchasePriceCents: Int? = nil
    var purchaseCurrencyCode: String = "USD"
    var purchaseSource: String = ""
    var purchaseDate: Date? = nil
    var isOnLoan: Bool = false
    var loanedTo: String = ""
    var loanedAt: Date? = nil
    var loanDueDate: Date? = nil
    var didRead: Bool = false
    var didListenToAudiobook: Bool = false
    var intendedRecipient: String = ""
    var giftOccasion: String = ""
    var giftByDate: Date? = nil
    var privateNotes: String = ""

    var format: LibraryBookFormat {
        get { LibraryBookFormat(rawValue: formatRaw) ?? .other }
        set { formatRaw = newValue.rawValue }
    }

    var condition: LibraryBookCondition {
        get { LibraryBookCondition(rawValue: conditionRaw) ?? .good }
        set { conditionRaw = newValue.rawValue }
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
        sourceURLString: String = "",
        addedAt: Date = .now
    ) {
        self.title = title
        self.author = author
        self.isbn = isbn
        self.bookDescription = bookDescription
        self.publishedYear = publishedYear
        self.coverURL = coverURL
        self.externalProvider = externalProvider
        self.externalID = externalID
        self.sourceURLString = sourceURLString
        self.addedAt = addedAt
        self.updatedAt = addedAt
        self.purchaseCurrencyCode = Locale.current.currency?.identifier ?? "USD"
    }
}

extension LibraryBook {
    var displayTitle: String {
        title.trimmedOrNil ?? "Untitled"
    }

    var displayAuthor: String {
        author.trimmed
    }

    var coverImageURL: URL? {
        URL(string: coverURL.trimmed)
    }

    var hasGiftPlan: Bool {
        !intendedRecipient.trimmed.isEmpty
    }

    var ownershipBadges: [String] {
        var badges: [String] = []
        if didRead { badges.append("Read") }
        if didListenToAudiobook { badges.append("Listened") }
        if isSigned { badges.append("Signed") }
        if isOnLoan { badges.append("On loan") }
        if hasGiftPlan { badges.append("Gift planned") }
        if let purchasePriceCents, purchasePriceCents > 0 {
            badges.append(Self.currencyFormatter(currencyCode: purchaseCurrencyCode).string(from: NSNumber(value: Double(purchasePriceCents) / 100)) ?? "\(purchasePriceCents / 100)")
        }
        return badges
    }

    static func fromPendingImport(_ item: SharedImportInbox.PendingImport, now: Date = .now) -> LibraryBook {
        LibraryBook(
            title: item.displayTitle ?? "",
            author: item.displayAuthor ?? "",
            isbn: item.isbn?.trimmedOrNil ?? "",
            bookDescription: item.bookDescription?.trimmedOrNil ?? "",
            publishedYear: item.publishedYear,
            coverURL: item.coverURLString?.trimmedOrNil ?? "",
            externalProvider: item.externalProvider?.trimmedOrNil ?? "",
            externalID: item.externalID?.trimmedOrNil ?? item.url.lastPathComponent,
            sourceURLString: item.url.absoluteString,
            addedAt: now
        )
    }

    static func fromSubmission(_ submission: BookSubmission, now: Date = .now) -> LibraryBook {
        LibraryBook(
            title: submission.title,
            author: submission.author,
            isbn: submission.isbn,
            bookDescription: submission.bookDescription,
            publishedYear: submission.publishedYear,
            coverURL: submission.coverURL,
            externalProvider: submission.externalProvider,
            externalID: submission.externalID,
            addedAt: now
        )
    }

    func matchesPendingImport(_ item: SharedImportInbox.PendingImport) -> Bool {
        if sourceURLString == item.url.absoluteString { return true }
        guard let provider = item.externalProvider?.trimmedOrNil,
              let externalID = item.externalID?.trimmedOrNil else {
            return false
        }
        return externalProvider == provider && self.externalID == externalID
    }

    func matchesSubmission(_ submission: BookSubmission) -> Bool {
        guard !externalProvider.isEmpty,
              !externalID.isEmpty else {
            return false
        }
        return externalProvider == submission.externalProvider && externalID == submission.externalID
    }

    static func currencyFormatter(currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode.trimmedOrNil ?? "USD"
        return formatter
    }
}

import Foundation
import SwiftData

struct LibraryMutationError: LocalizedError, Identifiable {
    let id = UUID()
    let operation: String
    let underlying: Error

    var errorDescription: String? {
        "Couldn't \(operation). \(underlying.localizedDescription)"
    }
}

/// Owns the persistence boundary for Shelf mutations shared by the iOS and
/// macOS library surfaces. A failed save rolls the ModelContext back so views
/// never leave optimistic inserts, deletes, or club changes on screen.
@MainActor
enum LibraryMutationService {
    static func savePendingImport(
        _ item: SharedImportInbox.PendingImport,
        context: ModelContext
    ) throws -> LibraryBook {
        let book = LibraryBook.fromPendingImport(item)
        context.insert(book)
        try commit("save this import to your Shelf", context: context)
        return book
    }

    static func delete(_ books: [LibraryBook], context: ModelContext) throws {
        books.forEach(context.delete)
        try commit(books.count == 1 ? "delete this book" : "delete these books", context: context)
    }

    static func addBook(
        from draft: AddBookDraft,
        action: AddBookComposerAction,
        activeClub: BookClub?,
        memberID: String,
        memberName: String,
        context: ModelContext
    ) throws -> LibraryBook {
        let book = draft.makeLibraryBook()
        context.insert(book)

        guard action != .libraryOnly, let activeClub else {
            try commit("save this book", context: context)
            return book
        }

        let status: BookSubmissionStatus = action == .clubCompleted ? .completed : .proposed
        let submission = draft.makeSubmission(memberID: memberID, memberName: memberName, status: status)
        activeClub.addSubmission(submission)
        context.insert(submission)
        try commitClub("save this book and update the club", club: activeClub, memberID: memberID, memberName: memberName, context: context)
        return book
    }

    static func addToClub(
        _ book: LibraryBook,
        club: BookClub,
        memberID: String,
        memberName: String,
        context: ModelContext
    ) throws {
        let submission = BookSubmission(
            title: book.title,
            author: book.author,
            isbn: book.isbn,
            bookDescription: book.bookDescription,
            publishedYear: book.publishedYear,
            coverURL: book.coverURL,
            externalProvider: book.externalProvider,
            externalID: book.externalID,
            submittedBy: memberName,
            submittedByMemberID: memberID
        )
        club.addSubmission(submission)
        context.insert(submission)
        try commitClub("add this book to the club", club: club, memberID: memberID, memberName: memberName, context: context)
    }

    static func savePersonalLibraryChanges(context: ModelContext) throws {
        try commit("save your Shelf changes", context: context)
    }

    static func saveClubChanges(
        club: BookClub,
        memberID: String,
        memberName: String,
        context: ModelContext
    ) throws {
        try commitClub("save the club changes", club: club, memberID: memberID, memberName: memberName, context: context)
    }

    private static func commit(_ operation: String, context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw LibraryMutationError(operation: operation, underlying: error)
        }
    }

    private static func commitClub(
        _ operation: String,
        club: BookClub,
        memberID: String,
        memberName: String,
        context: ModelContext
    ) throws {
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: memberID,
                localMemberName: memberName
            )
        } catch {
            context.rollback()
            throw LibraryMutationError(operation: operation, underlying: error)
        }
    }
}

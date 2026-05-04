import Foundation

/// Glue between `SharedImportInbox.PendingImport` (App-Group queue, no main-app
/// dependencies) and `BookMetadataCandidate` (main-app metadata service). Lives
/// in the main app target so the share extension doesn't need to compile it.
extension SharedImportInbox.PendingImport {
    /// Write a fetched candidate into this entry. Caller owns persistence
    /// (typically via `SharedImportInbox.update(_:mutation:)`).
    mutating func apply(_ candidate: BookMetadataCandidate, fetchedAt: Date = .now) {
        title = candidate.title
        author = candidate.authorLine
        coverURLString = candidate.coverURL?.absoluteString
        bookDescription = candidate.description
        publishedYear = candidate.publishedYear
        isbn = candidate.isbn
        externalProvider = candidate.provider.rawValue
        externalID = candidate.externalID
        metadataFetchedAt = fetchedAt
    }

    /// Reconstruct the candidate that prefetch resolved. Returns nil when the
    /// entry hasn't been resolved yet, signalling that callers should fetch
    /// live instead of using stale or missing data.
    var resolvedCandidate: BookMetadataCandidate? {
        guard hasResolvedMetadata, let title = displayTitle else { return nil }
        let provider = externalProvider.flatMap(BookMetadataProvider.init(rawValue:)) ?? .goodreads
        let resolvedID = externalID ?? url.lastPathComponent
        let authors: [String] = displayAuthor
            .map { $0.split(separator: ",", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) } }
            ?? []
        return BookMetadataCandidate(
            provider: provider,
            externalID: resolvedID,
            title: title,
            authors: authors,
            publishedYear: publishedYear,
            isbn: isbn,
            coverURL: coverURL,
            description: bookDescription,
            sourceURL: url
        )
    }
}

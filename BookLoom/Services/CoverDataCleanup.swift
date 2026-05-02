import SwiftData

@MainActor
enum CoverDataCleanup {
    @discardableResult
    static func clearPersistedCoverData(in club: BookClub) -> Bool {
        var didClearCoverData = false
        for submission in club.submissions ?? [] where submission.coverData != nil {
            submission.coverData = nil
            didClearCoverData = true
        }
        return didClearCoverData
    }

    static func clearPersistedCoverData(in context: ModelContext) {
        do {
            let submissions = try context.fetch(FetchDescriptor<BookSubmission>())
            var didClearCoverData = false
            for submission in submissions where submission.coverData != nil {
                submission.coverData = nil
                didClearCoverData = true
            }
            if didClearCoverData {
                try context.save()
            }
        } catch {
            assertionFailure("Failed to clear persisted cover data: \(error.localizedDescription)")
        }
    }
}

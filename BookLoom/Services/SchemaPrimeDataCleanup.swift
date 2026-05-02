import Foundation
import os
import SwiftData

/// Single source of truth for the strings the DEBUG schema-prime path writes
/// into CloudKit. `CloudKitSchemaPrimer` writes them; `SchemaPrimeDataCleanup`
/// recognizes them. Both must agree forever, so the constants live here (in
/// non-DEBUG code) and are referenced from both sides.
enum SchemaPrimeIdentity {
    static let clubName = "Schema Prime"
    static let cloudZonePrefix = "BookClub-SchemaPrime-"
    static let memberID = "schema-prime"
    static let memberName = "BookLoom"
    static let proposalDescription = "Development-only record used to register CloudKit schema."
    static let meetingTitle = "Schema Prime Meeting"
    static let pollTitle = "Schema Prime Vote"
}

@MainActor
enum SchemaPrimeDataCleanup {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "SchemaPrimeDataCleanup")

    static func isSchemaPrime(_ club: BookClub) -> Bool {
        guard club.name.trimmed == SchemaPrimeIdentity.clubName else { return false }

        if club.cloudZoneName.hasPrefix(SchemaPrimeIdentity.cloudZonePrefix) {
            return true
        }

        if club.submissions?.contains(where: isSchemaPrimeSubmission) == true {
            return true
        }

        if club.meetings?.contains(where: { $0.title.trimmed == SchemaPrimeIdentity.meetingTitle }) == true {
            return true
        }

        if club.selectionPolls?.contains(where: { $0.title.trimmed == SchemaPrimeIdentity.pollTitle }) == true {
            return true
        }

        return false
    }

    @discardableResult
    static func removeSchemaPrimeData(from context: ModelContext, clubs: [BookClub]? = nil) -> Int {
        let candidateClubs: [BookClub]
        if let clubs {
            candidateClubs = clubs
        } else {
            // Predicate-filtered fetch so SQL drops the 99.9% of rows that
            // aren't named "Schema Prime" — the post-fetch `isSchemaPrime`
            // check then disambiguates the dev-seeded ones from any
            // legitimately user-created club that happens to share the name.
            let primeName = SchemaPrimeIdentity.clubName
            let descriptor = FetchDescriptor<BookClub>(predicate: #Predicate { $0.name == primeName })
            do {
                candidateClubs = try context.fetch(descriptor)
            } catch {
                logger.error("Failed to fetch clubs for schema-prime cleanup: \(error.localizedDescription, privacy: .public)")
                return 0
            }
        }

        let staleClubs = candidateClubs.filter(isSchemaPrime)
        guard !staleClubs.isEmpty else { return 0 }

        staleClubs.forEach(context.delete)

        do {
            try context.save()
            logger.info("Removed \(staleClubs.count, privacy: .public) schema-prime club record(s)")
            return staleClubs.count
        } catch {
            logger.error("Failed to remove schema-prime club records: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    private static func isSchemaPrimeSubmission(_ submission: BookSubmission) -> Bool {
        let titleMatches = submission.title.trimmed == SchemaPrimeIdentity.clubName
        let descriptionMatches = submission.bookDescription.trimmed == SchemaPrimeIdentity.proposalDescription
        let memberMatches = submission.submittedByMemberID.trimmed == SchemaPrimeIdentity.memberID

        return titleMatches && (descriptionMatches || memberMatches)
    }
}

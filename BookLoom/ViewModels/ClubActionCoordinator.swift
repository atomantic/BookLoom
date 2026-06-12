import Foundation
import SwiftData

/// Owns the CloudKit sync orchestration and SwiftData mutations that the Club
/// tab used to perform inline in view methods (see #18). Extracting these keeps
/// `BooksTabContent` declarative and makes the save/publish/insert logic
/// unit-testable without standing up a full SwiftUI view.
///
/// The coordinator deliberately does NOT own the navigation path. Poll creation
/// returns the poll for the view to append, so navigation semantics stay in the
/// view layer where the `NavigationPath` binding lives.
@MainActor
@Observable
final class ClubActionCoordinator {
    private let context: ModelContext
    private let memberIdentity: MemberIdentity

    init(context: ModelContext, memberIdentity: MemberIdentity) {
        self.context = context
        self.memberIdentity = memberIdentity
    }

    private var localMemberID: String { memberIdentity.memberID }
    private var localMemberName: String { memberIdentity.name }

    // MARK: - Sync

    /// Publish local changes and merge remote snapshots for the active club.
    func synchronizeIfNeeded(_ club: BookClub) async {
        await SharedClubSync.synchronizeIfNeeded(
            club,
            context: context,
            localMemberID: localMemberID,
            localMemberName: localMemberName
        )
    }

    // MARK: - Submission status mutations

    func pickRandomNext(in club: BookClub, from proposed: [BookSubmission]) {
        guard let pick = BookPicker.pickNext(from: proposed) else { return }
        assignCurrent(pick, in: club)
    }

    func assignCurrent(_ submission: BookSubmission, in club: BookClub) {
        SelectionPollCoordinator.promoteWinner(submission, in: club, actorMemberID: localMemberID)
        DiscussionPromptLibrary.ensureStarterPrompts(for: submission, context: context)
        saveClubChanges(club)
    }

    func markComplete(_ submission: BookSubmission, in club: BookClub) {
        BookSubmissionStatusEditor.markComplete(submission, in: club, actorMemberID: localMemberID)
        saveClubChanges(club)
    }

    func moveCurrentToProposals(_ submission: BookSubmission, in club: BookClub) {
        BookSubmissionStatusEditor.moveToProposals(submission, in: club, actorMemberID: localMemberID)
        saveClubChanges(club)
    }

    // MARK: - Polls

    /// Returns the open poll if one exists, otherwise creates and inserts a new
    /// poll over the proposed candidates and returns it. Returns `nil` when
    /// there aren't enough proposals to vote on. The caller is responsible for
    /// any navigation.
    func openOrCreatePoll(in club: BookClub, activePoll: SelectionPoll?, proposed: [BookSubmission]) -> SelectionPoll? {
        if let activePoll {
            return activePoll
        }

        guard proposed.count >= 2 else { return nil }
        let poll = SelectionPoll(
            title: "Next Book Vote",
            candidates: proposed,
            isAnonymousResults: true
        )
        poll.createdByMemberID = localMemberID
        context.insert(poll)
        club.addSelectionPoll(poll)
        saveClubChanges(club)
        return poll
    }

    // MARK: - Deletion

    func delete(_ items: [BookSubmission], at offsets: IndexSet, in club: BookClub) {
        for index in offsets {
            delete(items[index], in: club, shouldSave: false)
        }
        saveClubChanges(club)
    }

    func delete(_ submission: BookSubmission, in club: BookClub, shouldSave: Bool = true) {
        BookSubmissionDetailsEditor.recordDeletion(
            submission,
            in: club,
            actorMemberID: localMemberID
        )
        context.delete(submission)
        if shouldSave {
            saveClubChanges(club)
        }
    }

    /// Moves a club proposal into the shared import inbox. Returns `true` when
    /// the move succeeded so the view can switch tabs.
    func moveSubmissionToImports(_ submission: BookSubmission, inbox: GoodreadsImportInbox, in club: BookClub) -> Bool {
        guard inbox.moveSubmissionToShelf(submission, context: context) else { return false }
        saveClubChanges(club)
        return true
    }

    // MARK: - Personal library

    func saveToPersonalLibrary(_ submission: BookSubmission) {
        if let existing = existingLibraryBook(matching: submission) {
            existing.didRead = true
            existing.updatedAt = .now
            savePersonalLibraryChanges()
            return
        }

        let book = LibraryBook.fromSubmission(submission)
        book.didRead = true
        context.insert(book)
        savePersonalLibraryChanges()
    }

    /// True when the submission already has a Shelf copy, so the view can skip
    /// offering to keep it again.
    func hasPersonalLibraryCopy(of submission: BookSubmission) -> Bool {
        existingLibraryBook(matching: submission) != nil
    }

    /// Targeted lookup for the Shelf copy of a submission instead of querying
    /// the whole `LibraryBook` table just to run a `contains` scan. A match
    /// requires the submission to carry external identifiers (see
    /// `LibraryBook.matchesSubmission`), so bail early when it has none.
    private func existingLibraryBook(matching submission: BookSubmission) -> LibraryBook? {
        let provider = submission.externalProvider
        let externalID = submission.externalID
        guard !provider.isEmpty, !externalID.isEmpty else { return nil }

        let descriptor = FetchDescriptor<LibraryBook>(
            predicate: #Predicate { $0.externalProvider == provider && $0.externalID == externalID }
        )
        return try? context.fetch(descriptor).first
    }

    private func savePersonalLibraryChanges() {
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save personal library changes: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    private func saveClubChanges(_ club: BookClub) {
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: localMemberID,
                localMemberName: localMemberName
            )
        } catch {
            assertionFailure("Failed to save club changes: \(error.localizedDescription)")
        }
    }
}

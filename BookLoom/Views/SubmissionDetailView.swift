import SwiftUI
import SwiftData

struct SubmissionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(GoodreadsImportInbox.self) private var goodreadsInbox

    @Bindable var submission: BookSubmission
    @Query(sort: \LibraryBook.updatedAt, order: .reverse) private var libraryBooks: [LibraryBook]

    @State private var draftNote: String = ""
    @State private var draftPrompt: String = ""
    @State private var showingDiscussionMode: Bool = false
    @State private var showingSetCurrentConfirmation: Bool = false
    @State private var showingMarkReadConfirmation: Bool = false
    @State private var showingMoveToProposalsConfirmation: Bool = false
    @State private var showingMoveToShelfConfirmation: Bool = false

    var body: some View {
        let summary = submission.ratingSummary
        let noteCount = (submission.notes ?? []).count
        let allRatings = (submission.ratings ?? []).sorted { $0.createdAt < $1.createdAt }
        let allNotes = (submission.notes ?? []).sorted { $0.createdAt > $1.createdAt }
        let prompts = submission.activeDiscussionPrompts
        let willReplaceCurrent = submission.bookClub?.sections.current.map { $0 !== submission } ?? false

        List {
            Section {
                SubmissionHero(submission: submission)
                    .bookLoomListRow(top: 6, bottom: 8)
            }

            Section {
                StatusActionsCard(
                    submission: submission,
                    canMoveToShelf: GoodreadsImportInbox.canMoveToShelf(submission),
                    onSetCurrent: { showingSetCurrentConfirmation = true },
                    onMarkRead: { showingMarkReadConfirmation = true },
                    onMoveToProposals: { showingMoveToProposalsConfirmation = true },
                    onMoveToShelf: { showingMoveToShelfConfirmation = true }
                )
            } header: {
                SectionTitle(title: "Status")
            }
            .bookLoomListRow()

            if hasDisplayableDetails {
                Section {
                    BookDetailsCard(submission: submission)
                } header: {
                    SectionTitle(title: "Details")
                }
                .bookLoomListRow()
            }

            Section {
                RatingsCard(stars: bindingForOwnRating(), summary: summary, ratings: allRatings)
            } header: {
                SectionTitle(title: "Ratings", detail: "\(summary.count)")
            }
            .bookLoomListRow()

            Section {
                NotesCard(draftNote: $draftNote, notes: allNotes, onSaveNote: saveNote)
            } header: {
                SectionTitle(title: "Notes", detail: "\(noteCount)")
            }
            .bookLoomListRow()

            Section {
                DiscussionPromptCard(
                    submission: submission,
                    draftPrompt: $draftPrompt,
                    onStartDiscussion: { showingDiscussionMode = true }
                )
            } header: {
                SectionTitle(title: "Discussion", detail: "\(prompts.count)")
            }
            .bookLoomListRow()
        }
        .bookLoomListStyle()
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationTitle(submission.displayTitle)
        .bookLoomNavigationBar()
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    saveToPersonalLibrary()
                } label: {
                    Label(isSavedToPersonalLibrary ? "On Shelf" : "Save to Shelf", systemImage: "books.vertical.fill")
                }
                .disabled(isSavedToPersonalLibrary)
            }
        }
        #endif
        .sheet(isPresented: $showingDiscussionMode) {
            DiscussionModeView(submissionTitle: submission.displayTitle, prompts: prompts)
        }
        .confirmationDialog(
            willReplaceCurrent ? "Replace the current book?" : "Set as the current book?",
            isPresented: $showingSetCurrentConfirmation,
            titleVisibility: .visible
        ) {
            Button("Set as Current Read") { setAsCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(willReplaceCurrent
                 ? "This marks the existing current book as completed and promotes this one in its place."
                 : "This sets the book as the club's current read.")
        }
        .confirmationDialog(
            markReadConfirmationTitle,
            isPresented: $showingMarkReadConfirmation,
            titleVisibility: .visible
        ) {
            Button(markReadConfirmationActionTitle) { markComplete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(markReadConfirmationMessage)
        }
        .confirmationDialog(
            "Move this book back to proposals?",
            isPresented: $showingMoveToProposalsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Proposals") { moveToProposals() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This returns the book to the proposal list without recording a read.")
        }
        .confirmationDialog(
            "Move this book to Imports?",
            isPresented: $showingMoveToShelfConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Imports") { moveToShelf() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the book from the club and parks it in Imports so you can choose Shelf and club destinations later.")
        }
    }

    private var hasDisplayableDetails: Bool {
        !submission.isbn.isEmpty || submission.publishedYear != nil || !submission.displayDescription.isEmpty
    }

    private var isSavedToPersonalLibrary: Bool {
        libraryBooks.contains { $0.matchesSubmission(submission) }
    }

    private var markReadConfirmationTitle: String {
        switch submission.status {
        case .current:
            return "Mark the current book as read?"
        case .proposed, .skipped:
            return "Mark this book as already read?"
        case .completed:
            return "This book is already marked read."
        }
    }

    private var markReadConfirmationActionTitle: String {
        submission.status == .current ? "Mark Read" : "Mark Already Read"
    }

    private var markReadConfirmationMessage: String {
        switch submission.status {
        case .current:
            return "This moves the book into reading history and clears the current slot."
        case .proposed, .skipped:
            return "This moves the book into the group's read history without setting it as current."
        case .completed:
            return "The book is already in the group's read history."
        }
    }

    private func setAsCurrent() {
        guard let club = submission.bookClub else { return }
        SelectionPollCoordinator.promoteWinner(submission, in: club, actorMemberID: memberIdentity.memberID)
        DiscussionPromptLibrary.ensureStarterPrompts(for: submission, context: context)
        saveSubmissionChanges()
    }

    private func markComplete() {
        guard let club = submission.bookClub else { return }
        BookSubmissionStatusEditor.markComplete(submission, in: club, actorMemberID: memberIdentity.memberID)
        saveSubmissionChanges()
    }

    private func moveToProposals() {
        guard let club = submission.bookClub else { return }
        BookSubmissionStatusEditor.moveToProposals(submission, in: club, actorMemberID: memberIdentity.memberID)
        saveSubmissionChanges()
    }

    private func moveToShelf() {
        guard let club = submission.bookClub else { return }
        guard goodreadsInbox.moveSubmissionToShelf(submission, context: context) else { return }
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
        } catch {
            assertionFailure("Failed to save after moving submission to Shelf: \(error.localizedDescription)")
        }
        dismiss()
    }

    private func saveToPersonalLibrary() {
        guard !isSavedToPersonalLibrary else { return }
        let book = LibraryBook.fromSubmission(submission)
        context.insert(book)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save personal library book: \(error.localizedDescription)")
        }
    }

    private func bindingForOwnRating() -> Binding<Int> {
        Binding(
            get: { ownRating()?.stars ?? 0 },
            set: { newValue in
                if let existing = ownRating() {
                    existing.stars = newValue
                } else {
                    let rating = Rating(memberID: memberIdentity.memberID, memberName: memberIdentity.name, stars: newValue)
                    rating.submission = submission
                    context.insert(rating)
                }
                saveSubmissionChanges()
            }
        )
    }

    private func ownRating() -> Rating? {
        (submission.ratings ?? []).first { $0.matches(memberID: memberIdentity.memberID, memberName: memberIdentity.name) }
    }

    private func saveNote() {
        guard let trimmed = draftNote.trimmedOrNil else { return }
        let note = BookNote(memberID: memberIdentity.memberID, memberName: memberIdentity.name, text: trimmed)
        note.submission = submission
        context.insert(note)
        draftNote = ""
        saveSubmissionChanges()
    }

    private func saveSubmissionChanges() {
        do {
            try context.save()
            if let club = submission.bookClub {
                SharedClubSync.publishIfNeeded(
                    club,
                    context: context,
                    localMemberID: memberIdentity.memberID,
                    localMemberName: memberIdentity.name
                )
            }
        } catch {
            assertionFailure("Failed to save submission changes: \(error.localizedDescription)")
        }
    }
}

private struct BookDetailsCard: View {
    let submission: BookSubmission

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !submission.isbn.isEmpty {
                InfoLine(label: "ISBN", value: submission.isbn)
            }
            if let publishedYear = submission.publishedYear {
                InfoLine(label: "Published", value: "\(publishedYear)")
            }

            if !submission.displayDescription.isEmpty {
                Divider()
                Text(submission.displayDescription)
                    .font(.callout)
                    .foregroundStyle(BookLoomStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .bookLoomCard(padding: 12)
    }
}

private struct RatingsCard: View {
    @Binding var stars: Int

    let summary: RatingSummary
    let ratings: [Rating]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                StarRatingPicker(stars: $stars)
                Spacer(minLength: 12)
                if summary.average != nil {
                    Label(summary.displayValue, systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BookLoomStyle.gold)
                }
            }

            if ratings.isEmpty {
                Text("No group ratings yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                VStack(spacing: 8) {
                    ForEach(ratings) { rating in
                        HStack {
                            Text(rating.memberName)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(String(repeating: "★", count: rating.stars))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BookLoomStyle.gold)
                                .accessibilityLabel("\(rating.stars) stars")
                        }
                    }
                }
            }
        }
        .bookLoomCard(padding: 12)
    }
}

private struct NotesCard: View {
    @Binding var draftNote: String

    let notes: [BookNote]
    let onSaveNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Your thoughts...", text: $draftNote, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                Button(action: onSaveNote) {
                    Label("Save", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftNote.trimmed.isEmpty)
            }

            if notes.isEmpty {
                Text("Capture favorite passages, objections, or meeting topics.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(note.memberName, systemImage: "person.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(note.text)
                                .font(.callout)
                                .foregroundStyle(BookLoomStyle.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .bookLoomCard(padding: 12)
    }
}

private struct SubmissionHero: View {
    @Bindable var submission: BookSubmission

    var body: some View {
        HStack(spacing: 14) {
            BookCoverTile(
                title: submission.displayTitle,
                author: submission.displayAuthor,
                coverURL: submission.coverImageURL,
                width: 78,
                height: 108
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(submission.displayTitle)
                    .font(.title3.bold())
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(3)
                if !submission.displayAuthor.isEmpty {
                    Text(submission.displayAuthor)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 12)
    }
}

private struct StatusActionsCard: View {
    let submission: BookSubmission
    let canMoveToShelf: Bool
    let onSetCurrent: () -> Void
    let onMarkRead: () -> Void
    let onMoveToProposals: () -> Void
    let onMoveToShelf: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                StatusPill(status: submission.status)
                Spacer(minLength: 12)
                Text("Submitted by \(submission.displaySubmitter)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                switch submission.status {
                case .proposed:
                    actionButton("Set as Current Read", systemImage: "book.fill", prominent: true, action: onSetCurrent)
                    actionButton("Mark Already Read", systemImage: "checkmark.seal.fill", prominent: false, action: onMarkRead)
                    if canMoveToShelf {
                        actionButton("Move to Imports", systemImage: "tray.and.arrow.down.fill", prominent: false, action: onMoveToShelf)
                    }
                case .current:
                    actionButton("Mark Read", systemImage: "checkmark.seal.fill", prominent: true, action: onMarkRead)
                    actionButton("Move Back to Proposals", systemImage: "tray.full.fill", prominent: false, action: onMoveToProposals)
                case .completed:
                    actionButton("Move Back to Proposals", systemImage: "tray.full.fill", prominent: true, action: onMoveToProposals)
                    if canMoveToShelf {
                        actionButton("Move to Imports", systemImage: "tray.and.arrow.down.fill", prominent: false, action: onMoveToShelf)
                    }
                case .skipped:
                    actionButton("Restore to Proposals", systemImage: "tray.full.fill", prominent: true, action: onMoveToProposals)
                    actionButton("Mark Already Read", systemImage: "checkmark.seal.fill", prominent: false, action: onMarkRead)
                    if canMoveToShelf {
                        actionButton("Move to Imports", systemImage: "tray.and.arrow.down.fill", prominent: false, action: onMoveToShelf)
                    }
                }
            }
        }
        .bookLoomCard(padding: 12)
    }

    @ViewBuilder
    private func actionButton(_ title: String, systemImage: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        if prominent {
            button
                .buttonStyle(.borderedProminent)
                .bookLoomActionWidth(minWidth: 210)
        } else {
            button
                .buttonStyle(.bordered)
                .bookLoomActionWidth(minWidth: 210)
        }
    }
}

private struct InfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(BookLoomStyle.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

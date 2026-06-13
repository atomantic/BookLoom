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
    @State private var showingMetadataSearch: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    @State private var showingCoverZoom: Bool = false

    var body: some View {
        let summary = submission.ratingSummary
        let noteCount = (submission.notes ?? []).count
        let allRatings = (submission.ratings ?? []).sorted { $0.createdAt < $1.createdAt }
        let allNotes = (submission.notes ?? []).sorted { $0.createdAt > $1.createdAt }
        let prompts = submission.activeDiscussionPrompts
        let willReplaceCurrent = submission.bookClub?.sections.current.map { $0 !== submission } ?? false

        List {
            Section {
                SubmissionHeroActionsCard(
                    submission: submission,
                    canMoveToShelf: GoodreadsImportInbox.canMoveToShelf(submission),
                    onSetCurrent: { showingSetCurrentConfirmation = true },
                    onMarkRead: { showingMarkReadConfirmation = true },
                    onMoveToProposals: { showingMoveToProposalsConfirmation = true },
                    onMoveToShelf: { showingMoveToShelfConfirmation = true },
                    onViewCover: { showingCoverZoom = true },
                    onDelete: { showingDeleteConfirmation = true },
                    onCoverChange: applyCoverChange
                )
                .bookLoomListRow(top: 6, bottom: 10)
            }

            Section {
                SubmissionBookEditCard(
                    submission: submission,
                    onFindDetails: { showingMetadataSearch = true },
                    onSave: saveBookDetails
                )
            } header: {
                SectionTitle(title: "Book")
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
        .sheet(isPresented: $showingMetadataSearch) {
            BookMetadataSearchView(title: submission.title, author: submission.author, isbn: submission.isbn) { candidate in
                apply(candidate)
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingCoverZoom) {
            coverZoomView
        }
        #else
        .sheet(isPresented: $showingCoverZoom) {
            coverZoomView
        }
        #endif
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
        .confirmationDialog(
            "Delete this proposal?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Proposal", role: .destructive) { deleteSubmission() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the proposal from the club for every member.")
        }
    }

    private var hasDisplayableDetails: Bool {
        !submission.isbn.isEmpty || submission.publishedYear != nil || !submission.displayDescription.isEmpty
    }

    private var isSavedToPersonalLibrary: Bool {
        libraryBooks.contains { $0.matchesSubmission(submission) }
    }

    private var coverZoomView: some View {
        BookCoverZoomView(
            title: submission.displayTitle,
            author: submission.displayAuthor,
            coverURL: submission.coverImageURL
        ) {
            showingCoverZoom = false
        }
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

    private func saveBookDetails() {
        guard let club = submission.bookClub else { return }
        submission.title = submission.title.trimmed
        submission.author = submission.author.trimmed
        submission.isbn = submission.isbn.trimmed
        BookSubmissionDetailsEditor.recordDetailsOverride(
            submission,
            in: club,
            actorMemberID: memberIdentity.memberID
        )
        saveSubmissionChanges()
    }

    private func apply(_ candidate: BookMetadataCandidate) {
        submission.applyMetadata(candidate)
        saveBookDetails()
    }

    private func applyCoverChange(_ newCoverURL: String) {
        guard let club = submission.bookClub else { return }
        submission.coverURL = newCoverURL
        BookSubmissionDetailsEditor.recordDetailsOverride(
            submission,
            in: club,
            actorMemberID: memberIdentity.memberID
        )
        saveSubmissionChanges()
    }

    private func deleteSubmission() {
        guard let club = submission.bookClub else { return }
        BookSubmissionDetailsEditor.recordDeletion(
            submission,
            in: club,
            actorMemberID: memberIdentity.memberID
        )
        context.delete(submission)
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
            dismiss()
        } catch {
            assertionFailure("Failed to delete submission: \(error.localizedDescription)")
        }
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
            try context.saveAndPublishIfNeeded(club: submission.bookClub, memberIdentity: memberIdentity)
        } catch {
            assertionFailure("Failed to save submission changes: \(error.localizedDescription)")
        }
    }
}

private struct SubmissionBookEditCard: View {
    @Bindable var submission: BookSubmission
    let onFindDetails: () -> Void
    let onSave: () -> Void

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BookLoomCompactTextField("Title", text: $submission.title)
            BookLoomCompactDivider()
            BookLoomCompactTextField("Author", text: $submission.author)
            BookLoomCompactDivider()
            BookLoomCompactTextField("ISBN", text: $submission.isbn, keyboard: .numbersAndPunctuation)

            if stackButtonsVertically {
                VStack(alignment: .leading, spacing: 8) {
                    metadataButton
                    saveButton
                }
            } else {
                HStack(spacing: 8) {
                    metadataButton
                    saveButton
                }
            }
        }
        .bookLoomCard(padding: 12)
    }

    private var stackButtonsVertically: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    private var metadataButtonTitle: String {
        "Search for Cover and Details"
    }

    private var metadataButton: some View {
        Button(action: onFindDetails) {
            Label(metadataButtonTitle, systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.indigo))
        .disabled(submission.title.trimmed.isEmpty && submission.isbn.trimmed.isEmpty)
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Label("Save Details", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BookLoomProminentButtonStyle())
        .disabled(submission.title.trimmed.isEmpty)
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
                .buttonStyle(BookLoomProminentButtonStyle())
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

private struct SubmissionHeroActionsCard: View {
    @Bindable var submission: BookSubmission
    let canMoveToShelf: Bool
    let onSetCurrent: () -> Void
    let onMarkRead: () -> Void
    let onMoveToProposals: () -> Void
    let onMoveToShelf: () -> Void
    let onViewCover: () -> Void
    let onDelete: () -> Void
    let onCoverChange: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            contentLayout {
                Button(action: onViewCover) {
                    BookCoverTile(
                        title: submission.displayTitle,
                        author: submission.displayAuthor,
                        coverURL: submission.coverImageURL,
                        width: 72,
                        height: 98
                    )
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("View larger cover for \(submission.displayTitle)")
                .accessibilityHint("Opens an enlarged book cover")

                VStack(alignment: .leading, spacing: 7) {
                    StatusPill(status: submission.status)

                    Text(submission.displayTitle)
                        .font(.headline.bold())
                        .foregroundStyle(BookLoomStyle.ink)
                        .lineLimit(dynamicTypeSize.prefersExpandedControlLayout ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !submission.displayAuthor.isEmpty {
                        Text(submission.displayAuthor)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.prefersExpandedControlLayout ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    metadataLayout {
                        Label(submission.ratingSummary.displayValue, systemImage: "star.fill")
                        Label("\((submission.notes ?? []).count) notes", systemImage: "note.text")
                        Label(submission.displaySubmitter, systemImage: "person.fill")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.prefersExpandedControlLayout ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if !dynamicTypeSize.prefersExpandedControlLayout {
                    Spacer(minLength: 0)
                }
            }

            ManualCoverPicker(
                identifier: submission.selectionID,
                currentCoverURL: submission.coverURL,
                onCoverChange: onCoverChange
            )

            LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                switch submission.status {
                case .proposed:
                    actionButton("Set Current", accessibilityTitle: "Set as Current Read", systemImage: "book.fill", tint: BookLoomStyle.sage, prominent: true, action: onSetCurrent)
                    actionButton("Mark Read", accessibilityTitle: "Mark Already Read", systemImage: "checkmark.seal.fill", tint: BookLoomStyle.plum, prominent: false, action: onMarkRead)
                    if canMoveToShelf {
                        actionButton("Move to Imports", systemImage: "tray.and.arrow.down.fill", tint: BookLoomStyle.plum, prominent: false, action: onMoveToShelf)
                    }
                    actionButton("Delete", accessibilityTitle: "Delete Proposal", systemImage: "trash.fill", tint: BookLoomStyle.coral, prominent: false, role: .destructive, action: onDelete)
                case .current:
                    actionButton("Mark Read", systemImage: "checkmark.seal.fill", tint: BookLoomStyle.sage, prominent: true, action: onMarkRead)
                    actionButton("Move Back", accessibilityTitle: "Move Back to Proposals", systemImage: "tray.full.fill", tint: BookLoomStyle.plum, prominent: false, action: onMoveToProposals)
                case .completed:
                    actionButton("Move Back", accessibilityTitle: "Move Back to Proposals", systemImage: "tray.full.fill", tint: BookLoomStyle.plum, prominent: true, action: onMoveToProposals)
                    if canMoveToShelf {
                        actionButton("Move to Imports", systemImage: "tray.and.arrow.down.fill", tint: BookLoomStyle.plum, prominent: false, action: onMoveToShelf)
                    }
                case .skipped:
                    actionButton("Restore", accessibilityTitle: "Restore to Proposals", systemImage: "tray.full.fill", tint: BookLoomStyle.plum, prominent: true, action: onMoveToProposals)
                    actionButton("Mark Read", accessibilityTitle: "Mark Already Read", systemImage: "checkmark.seal.fill", tint: BookLoomStyle.sage, prominent: false, action: onMarkRead)
                    if canMoveToShelf {
                        actionButton("Move to Imports", systemImage: "tray.and.arrow.down.fill", tint: BookLoomStyle.plum, prominent: false, action: onMoveToShelf)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .bookLoomCard(padding: 12)
    }

    private func actionButton(
        _ title: String,
        accessibilityTitle: String? = nil,
        systemImage: String,
        tint: Color,
        prominent: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        BookLoomActionButton(
            title: title,
            accessibilityTitle: accessibilityTitle,
            systemImage: systemImage,
            tint: tint,
            prominent: prominent,
            role: role,
            action: action
        )
    }

    private var contentLayout: AnyLayout {
        dynamicTypeSize.adaptiveLayout(expanded: VStackLayout(alignment: .leading, spacing: 12), compact: HStackLayout(spacing: 14))
    }

    private var metadataLayout: AnyLayout {
        dynamicTypeSize.adaptiveLayout(expanded: VStackLayout(alignment: .leading, spacing: 4), compact: HStackLayout(spacing: 12))
    }

    private var actionColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: dynamicTypeSize.prefersExpandedControlLayout ? 220 : 132),
                spacing: 8,
                alignment: .leading
            )
        ]
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

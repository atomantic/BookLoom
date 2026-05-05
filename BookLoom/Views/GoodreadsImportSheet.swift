import SwiftUI
import SwiftData

/// Sheet shown after the user shares a Goodreads link to BookLoom (via the
/// Share Extension or `bookloom://import?url=...`). Falls back to fetching
/// metadata on-demand when the prefetch pass hasn't resolved this entry yet
/// (typically a fresh share opened before `prefetchAll` could complete).
struct GoodreadsImportSheet: View {
    let pendingItem: SharedImportInbox.PendingImport
    let clubs: [BookClub]
    let initiallyActiveClub: BookClub?
    /// Called when the sheet is finishing. `didSave == false` means the user
    /// cancelled, and the URL stays in `SharedImportInbox` so they can return
    /// to it from Imports.
    var onDismiss: (GoodreadsImportCompletion) -> Void

    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @Query(sort: \LibraryBook.updatedAt, order: .reverse) private var libraryBooks: [LibraryBook]

    @State private var candidate: BookMetadataCandidate?
    @State private var fetchError: String?
    @State private var saveError: String?
    @State private var isFetching: Bool
    @State private var isSaving = false
    @State private var saveToShelf = true
    @State private var selectedClubIDs: Set<PersistentIdentifier> = []

    private let metadataService = BookMetadataService()

    init(
        pendingItem: SharedImportInbox.PendingImport,
        clubs: [BookClub],
        initiallyActiveClub: BookClub?,
        onDismiss: @escaping (GoodreadsImportCompletion) -> Void
    ) {
        self.pendingItem = pendingItem
        self.clubs = clubs
        self.initiallyActiveClub = initiallyActiveClub
        self.onDismiss = onDismiss
        let prefetched = pendingItem.resolvedCandidate
        _candidate = State(initialValue: prefetched)
        _isFetching = State(initialValue: prefetched == nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header

                    if let candidate {
                        BookCard(candidate: candidate)
                    } else if isFetching {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Fetching from Goodreads…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                    } else if let fetchError {
                        Label(fetchError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(BookLoomStyle.coral)
                            .padding(.vertical, 12)
                    }

                    destinationPicker

                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(BookLoomStyle.coral)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    actionButtons
                }
                .padding(16)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .bookLoomScreenBackground()
            .navigationTitle("Add from Goodreads")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss(GoodreadsImportCompletion(didSave: false, primaryClub: nil))
                    }
                }
            }
        }
        .task {
            seedSelectedDestinationsIfNeeded()
            await loadMetadataIfNeeded()
        }
    }

    private var goodreadsURL: URL { pendingItem.url }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.title2)
                .foregroundStyle(BookLoomStyle.plum)
            VStack(alignment: .leading, spacing: 2) {
                Text(isGoodreadsItem ? "Imported from Goodreads" : "Imported Book")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                if isLocalShelfItem {
                    Text(pendingItem.externalProvider ?? "BookLoom Shelf")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(goodreadsURL.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 12)
    }

    private var isGoodreadsItem: Bool {
        pendingItem.externalProvider == BookMetadataProvider.goodreads.rawValue
            || goodreadsURL.host?.localizedCaseInsensitiveContains("goodreads.com") == true
    }

    private var isLocalShelfItem: Bool {
        goodreadsURL.scheme == "bookloom"
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destinations")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BookLoomStyle.ink)

            Toggle(isOn: $saveToShelf) {
                Label("Save to my Shelf", systemImage: "books.vertical.fill")
            }

            if !clubs.isEmpty {
                Divider()
                Text("Add to clubs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(clubs, id: \.persistentModelID) { club in
                    Toggle(isOn: clubSelectionBinding(for: club)) {
                        Label(club.name, systemImage: "person.2.fill")
                    }
                }
            } else {
                Label("Create a club later if you also want this in a club.", systemImage: "person.3")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .bookLoomCard(padding: 12)
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await save(asRead: false) }
            } label: {
                Label(isSaving ? "Saving…" : primaryActionTitle, systemImage: "square.and.arrow.down.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .bookLoomActionWidth()
            .disabled(saveDisabled)

            if !selectedClubs.isEmpty {
                Button {
                    Task { await save(asRead: true) }
                } label: {
                    Label(isSaving ? "Saving…" : "Add as Completed", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .bookLoomActionWidth()
                .disabled(saveDisabled)
            }
        }
    }

    private var primaryActionTitle: String {
        if saveToShelf, selectedClubs.isEmpty {
            return "Save to Shelf"
        }
        if saveToShelf {
            return selectedClubs.count == 1 ? "Save to Shelf + Club" : "Save to Shelf + Clubs"
        }
        return selectedClubs.count == 1 ? "Add to Club" : "Add to Clubs"
    }

    private var saveDisabled: Bool {
        candidate == nil || (!saveToShelf && selectedClubs.isEmpty) || isSaving || isFetching
    }

    private var selectedClubs: [BookClub] {
        clubs.filter { selectedClubIDs.contains($0.persistentModelID) }
    }

    private func loadMetadataIfNeeded() async {
        guard candidate == nil else { return }
        isFetching = true
        fetchError = nil
        defer { isFetching = false }

        do {
            candidate = try await metadataService.importFromGoodreads(url: goodreadsURL)
        } catch {
            fetchError = error.localizedDescription
        }
    }

    private func save(asRead: Bool) async {
        guard let candidate else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let now = Date.now

        if saveToShelf {
            saveCandidateToShelf(candidate, didRead: asRead, now: now)
        }

        let destinationClubs = selectedClubs
        for club in destinationClubs {
            let submission = BookSubmission(
                title: candidate.title,
                author: candidate.authorLine,
                isbn: candidate.primaryISBN,
                bookDescription: candidate.description ?? "",
                publishedYear: candidate.publishedYear,
                coverURL: candidate.coverURL?.absoluteString ?? "",
                externalProvider: candidate.provider.rawValue,
                externalID: candidate.externalID,
                submittedBy: memberIdentity.name,
                submittedByMemberID: memberIdentity.memberID,
                submittedAt: now,
                status: asRead ? .completed : .proposed
            )
            if asRead {
                submission.completedAt = now
            }
            club.addSubmission(submission)
            context.insert(submission)
        }

        do {
            if destinationClubs.isEmpty {
                try context.save()
            } else {
                for club in destinationClubs {
                    try SharedClubSync.saveAndPublish(
                        context: context,
                        club: club,
                        localMemberID: memberIdentity.memberID,
                        localMemberName: memberIdentity.name
                    )
                }
            }
            onDismiss(GoodreadsImportCompletion(didSave: true, primaryClub: destinationClubs.first))
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func seedSelectedDestinationsIfNeeded() {
        guard selectedClubIDs.isEmpty else { return }
        if let initiallyActiveClub {
            selectedClubIDs.insert(initiallyActiveClub.persistentModelID)
        } else if !clubs.isEmpty {
            selectedClubIDs.insert(clubs[0].persistentModelID)
        }
    }

    private func clubSelectionBinding(for club: BookClub) -> Binding<Bool> {
        Binding(
            get: { selectedClubIDs.contains(club.persistentModelID) },
            set: { isSelected in
                if isSelected {
                    selectedClubIDs.insert(club.persistentModelID)
                } else {
                    selectedClubIDs.remove(club.persistentModelID)
                }
            }
        )
    }

    private func saveCandidateToShelf(_ candidate: BookMetadataCandidate, didRead: Bool, now: Date) {
        if let existing = libraryBooks.first(where: {
            $0.externalProvider == candidate.provider.rawValue && $0.externalID == candidate.externalID
        }) {
            existing.didRead = existing.didRead || didRead
            existing.updatedAt = now
            return
        }

        let book = LibraryBook(
            title: candidate.title,
            author: candidate.authorLine,
            isbn: candidate.primaryISBN,
            bookDescription: candidate.description ?? "",
            publishedYear: candidate.publishedYear,
            coverURL: candidate.coverURL?.absoluteString ?? "",
            externalProvider: candidate.provider.rawValue,
            externalID: candidate.externalID,
            sourceURLString: pendingItem.url.absoluteString,
            addedAt: now
        )
        book.didRead = didRead
        context.insert(book)
    }
}

struct GoodreadsImportCompletion {
    let didSave: Bool
    let primaryClub: BookClub?
}

private struct BookCard: View {
    let candidate: BookMetadataCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BookCoverTile(
                title: candidate.title,
                author: candidate.authorLine,
                coverURL: candidate.coverURL,
                width: 64,
                height: 88
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.headline)
                    .foregroundStyle(BookLoomStyle.ink)
                if !candidate.authorLine.isEmpty {
                    Text(candidate.authorLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let year = candidate.publishedYear {
                    Text("First published \(String(year))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let description = candidate.description?.trimmedOrNil {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 12)
    }
}

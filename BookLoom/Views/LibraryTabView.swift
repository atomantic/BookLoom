#if os(iOS)
import SwiftData
import SwiftUI

struct LibraryTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(ActiveClubStore.self) private var activeClubStore
    @Environment(GoodreadsImportInbox.self) private var goodreadsInbox
    @Query(sort: \BookClub.createdAt, order: .reverse) private var clubs: [BookClub]

    @State private var pagination: LibraryPaginationStore?
    @State private var searchText = ""
    @State private var filter: LibraryBookFilter = .all
    @State private var showingNewBook = false
    @State private var selectedBook: LibraryBook?
    @State private var pendingDeleteBook: LibraryBook?
    @State private var mutationError: LibraryMutationError?

    private var books: [LibraryBook] { pagination?.books ?? [] }
    private var canLoadMore: Bool { pagination?.canLoadMore ?? true }
    private var hasLoadedOnce: Bool { pagination?.hasLoadedOnce ?? false }

    var body: some View {
        List {
            Section {
                MobileLibrarySummary(
                    ownedCount: books.filter(\.countsAsOwned).count,
                    readCount: books.filter(\.isRead).count,
                    wishlistCount: books.filter(\.isWishlist).count,
                    loanedCount: books.filter(\.isOnLoan).count,
                    importCount: goodreadsInbox.pending.count
                )
                .bookLoomListRow(top: 6, bottom: 8)

                LibrarySearchField(
                    text: $searchText,
                    placeholder: "Search bookshelf",
                    clearAccessibilityLabel: "Clear shelf book search"
                )
                    .bookLoomListRow(top: 4, bottom: 6)

                AdaptiveSegmentedControl(
                    "Shelf filter",
                    selection: $filter,
                    options: LibraryBookFilter.allCases
                ) { filter in
                    Text(filter.title)
                }
                .bookLoomListRow(top: 4, bottom: 8)
            }

            if !goodreadsInbox.pending.isEmpty {
                Section {
                    ForEach(goodreadsInbox.pending) { item in
                        MobileShelfImportRow(
                            item: item,
                            onSaveToShelf: { savePendingImportToShelf(item) },
                            onAddToClub: { goodreadsInbox.present(item.url) },
                            onRemove: { goodreadsInbox.remove(item.url) }
                        )
                        .bookLoomListRow()
                    }
                } header: {
                    SectionTitle(title: "Imports", detail: "\(goodreadsInbox.pending.count)")
                }
            }

            Section {
                if hasLoadedOnce && visibleBooks.isEmpty {
                    InlineEmptyState(
                        systemImage: emptyStateSystemImage,
                        title: emptyStateTitle,
                        message: emptyMessage
                    )
                    .bookLoomListRow()
                } else {
                    ForEach(visibleBooks) { book in
                        Button {
                            selectedBook = book
                        } label: {
                            MobileLibraryBookRow(book: book)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens book details")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeleteBook = book
                            } label: {
                                Label("Delete from Shelf", systemImage: "trash")
                            }
                        }
                        .bookLoomListRow()
                        .onAppear {
                            loadMoreIfNeeded(after: book)
                        }
                    }

                    if canLoadMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .bookLoomListRow()
                            .onAppear { pagination?.loadMore() }
                    }
                }
            } header: {
                SectionTitle(title: shelfSectionTitle, detail: "\(visibleBooks.count)")
            }
        }
        .bookLoomListStyle()
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationTitle("Shelf")
        .bookLoomNavigationBar()
        .navigationDestination(isPresented: selectedBookIsPresented) {
            if let selectedBook {
                MobileLibraryBookDetailView(
                    book: selectedBook,
                    activeClub: activeClub,
                    onAddToClub: { addToClub(selectedBook) },
                    onDelete: { pendingDeleteBook = selectedBook },
                    onSave: saveContext
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewBook = true
                } label: {
                    Label("Add Book", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewBook) {
            AddBookComposerView(mode: addBookComposerMode) { draft, action in
                try saveNewBook(draft, action: action)
                resetAndLoad()
            }
        }
        .refreshable {
            refreshShelf()
            resetAndLoad()
        }
        .task {
            if pagination == nil {
                pagination = LibraryPaginationStore(context: context)
            }
            refreshShelf()
            resetAndLoad()
        }
        .onChange(of: searchText) { _, _ in resetAndLoad() }
        .onChange(of: filter) { _, _ in resetAndLoad() }
        .confirmationDialog(
            pendingDeleteBook.map { "Delete \($0.displayTitle)?" } ?? "Delete book?",
            isPresented: .presence(of: $pendingDeleteBook),
            titleVisibility: .visible
        ) {
            Button("Delete from Shelf", role: .destructive) {
                confirmDeleteBook()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteBook = nil
            }
        } message: {
            Text("This removes the book and its private shelf notes from this device and iCloud.")
        }
        .alert("Shelf Change Failed", isPresented: .presence(of: $mutationError)) {
            Button("OK") { mutationError = nil }
        } message: {
            Text(mutationError?.localizedDescription ?? "The Shelf change couldn't be saved.")
        }
    }

    private var selectedBookIsPresented: Binding<Bool> {
        Binding(
            get: { selectedBook != nil },
            set: { isPresented in
                if !isPresented {
                    selectedBook = nil
                }
            }
        )
    }

    private var visibleBooks: [LibraryBook] {
        let query = searchText.trimmed
        return books.filter { book in
            switch filter {
            case .all: break
            case .owned: guard book.countsAsOwned else { return false }
            case .wishlist: guard book.isWishlist else { return false }
            case .loaned: guard book.isOnLoan else { return false }
            }

            guard !query.isEmpty else { return true }
            return book.displayTitle.localizedCaseInsensitiveContains(query)
                || book.displayAuthor.localizedCaseInsensitiveContains(query)
                || book.isbn.localizedCaseInsensitiveContains(query)
                || book.shelfLocation.localizedCaseInsensitiveContains(query)
        }
    }

    private var activeClub: BookClub? {
        activeClubStore.resolveActiveClub(from: clubs.filter { !SchemaPrimeDataCleanup.isSchemaPrime($0) })
    }

    private var addBookComposerMode: AddBookComposerMode {
        activeClub.map { .club(name: $0.name) } ?? .library
    }

    private var emptyMessage: String {
        if !searchText.trimmed.isEmpty {
            return "Try another title, author, ISBN, or shelf."
        }
        switch filter {
        case .all: return "Scan or add books to track owned copies, wishlist titles, loans, and read history."
        case .owned: return "Add a book with I own this turned on to build your owned shelf."
        case .wishlist: return "Add a book and toggle I want to own this to track titles you want to acquire."
        case .loaned: return "Books you mark as loaned will show up here."
        }
    }

    private var shelfSectionTitle: String {
        switch filter {
        case .all: return "All Books"
        case .owned: return "Owned"
        case .wishlist: return "Wishlist"
        case .loaned: return "Loaned"
        }
    }

    private var emptyStateTitle: String {
        switch filter {
        case .all: return "No Books on Your Shelf"
        case .owned: return "No Owned Books"
        case .wishlist: return "No Books on Your Wishlist"
        case .loaned: return "No Books on Loan"
        }
    }

    private var emptyStateSystemImage: String {
        switch filter {
        case .all: return "books.vertical"
        case .owned: return "books.vertical.fill"
        case .wishlist: return "star"
        case .loaned: return "person.crop.circle.badge.clock"
        }
    }

    private func resetAndLoad() {
        pagination?.reset()
    }

    /// Loads the next page when `book` is the last book in the filtered list.
    /// The guard compares against `visibleBooks` (the searched/filtered subset),
    /// which is view state the pagination store does not own.
    private func loadMoreIfNeeded(after book: LibraryBook) {
        guard visibleBooks.last?.persistentModelID == book.persistentModelID else { return }
        pagination?.loadMore()
    }

    private func refreshShelf() {
        goodreadsInbox.refresh()
        goodreadsInbox.prefetchAll()
    }

    private func savePendingImportToShelf(_ item: SharedImportInbox.PendingImport) {
        if books.contains(where: { $0.matchesPendingImport(item) }) {
            goodreadsInbox.remove(item.url)
            return
        }
        do {
            _ = try LibraryMutationService.savePendingImport(item, context: context)
            goodreadsInbox.remove(item.url)
            resetAndLoad()
        } catch {
            presentMutationError(error)
        }
    }

    private func confirmDeleteBook() {
        guard let book = pendingDeleteBook else { return }
        pendingDeleteBook = nil
        deleteFromShelf(book)
    }

    private func deleteFromShelf(_ book: LibraryBook) {
        let deletedID = book.persistentModelID
        if selectedBook?.persistentModelID == deletedID {
            selectedBook = nil
        }
        do {
            try LibraryMutationService.delete([book], context: context)
            let shouldBackfill = pagination?.remove(id: deletedID) ?? false
            if shouldBackfill {
                pagination?.loadMore()
            }
        } catch {
            presentMutationError(error)
            resetAndLoad()
        }
    }

    private func addToClub(_ book: LibraryBook) -> ShelfClubAddOutcome {
        guard let activeClub else {
            return .failed("Choose an active club before adding shelf books to club proposals.")
        }
        guard !activeClub.containsLibraryBook(book) else {
            return .alreadyAdded(activeClub.name)
        }

        do {
            try LibraryMutationService.addToClub(
                book,
                club: activeClub,
                memberID: memberIdentity.memberID,
                memberName: memberIdentity.name,
                context: context
            )
            return .added(activeClub.name)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func saveNewBook(_ draft: AddBookDraft, action: AddBookComposerAction) throws {
        _ = try LibraryMutationService.addBook(
            from: draft,
            action: action,
            activeClub: activeClub,
            memberID: memberIdentity.memberID,
            memberName: memberIdentity.name,
            context: context
        )
    }

    private func saveContext() {
        do {
            try LibraryMutationService.savePersonalLibraryChanges(context: context)
        } catch {
            presentMutationError(error)
        }
    }

    private func presentMutationError(_ error: Error) {
        mutationError = error as? LibraryMutationError
            ?? LibraryMutationError(operation: "save your Shelf changes", underlying: error)
    }
}

private struct MobileLibrarySummary: View {
    let ownedCount: Int
    let readCount: Int
    let wishlistCount: Int
    let loanedCount: Int
    let importCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Personal Shelf", systemImage: "books.vertical.fill")
                .font(.headline.bold())
                .foregroundStyle(BookLoomStyle.ink)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                MetricTile(value: "\(readCount)", label: "read", systemImage: "checkmark.seal.fill", tint: BookLoomStyle.sage)
                MetricTile(value: "\(ownedCount)", label: "owned", systemImage: "books.vertical.fill", tint: BookLoomStyle.indigo)
                MetricTile(value: "\(wishlistCount)", label: "wishlist", systemImage: "star.fill", tint: BookLoomStyle.gold)
                MetricTile(value: "\(loanedCount)", label: "loaned", systemImage: "person.crop.circle.badge.clock", tint: BookLoomStyle.plum)
                if importCount > 0 {
                    MetricTile(value: "\(importCount)", label: "imports", systemImage: "tray.fill", tint: BookLoomStyle.plum)
                }
            }
        }
        .bookLoomCard(padding: 12)
    }
}

private struct MobileLibraryBookRow: View {
    @Bindable var book: LibraryBook

    var body: some View {
        StandardBookCardRow(
            title: book.displayTitle,
            author: book.displayAuthor,
            coverURL: book.coverImageURL,
            indicators: indicators,
            showsDisclosure: true,
            coverWidth: 58,
            coverHeight: 82
        )
    }

    private var indicators: [BookCardIndicator] {
        var items: [BookCardIndicator] = [
            BookCardIndicator(book.format.cardLabel, systemImage: book.format.cardSystemImage, tint: BookLoomStyle.indigo)
        ]

        if book.personalRatingStars > 0 {
            let stars = min(book.personalRatingStars, 5)
            items.insert(
                BookCardIndicator("\(stars) out of 5 stars", systemImage: "star.fill", visibleText: "\(stars)", tint: BookLoomStyle.gold),
                at: 0
            )
        }
        if book.isWishlist {
            items.append(BookCardIndicator("Wishlist", systemImage: "star.fill", tint: BookLoomStyle.gold))
        }
        if book.isRead {
            items.append(BookCardIndicator("Read", systemImage: "checkmark.seal.fill", tint: BookLoomStyle.sage))
        }
        if book.didListenToAudiobook {
            items.append(BookCardIndicator("Audio", systemImage: "headphones", tint: BookLoomStyle.plum))
        }
        if book.isSigned {
            items.append(BookCardIndicator("Signed", systemImage: "signature", tint: BookLoomStyle.coral))
        }
        if book.isOnLoan {
            items.append(BookCardIndicator("Loaned", systemImage: "person.crop.circle.badge.clock", tint: BookLoomStyle.gold))
        }
        return items
    }
}

private struct MobileShelfImportRow: View {
    let item: SharedImportInbox.PendingImport
    let onSaveToShelf: () -> Void
    let onAddToClub: () -> Void
    let onRemove: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BookCoverTile(
                    title: item.displayTitle ?? "Book",
                    author: item.displayAuthor ?? "",
                    coverURL: item.coverURL,
                    width: 46,
                    height: 64
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayTitle ?? item.url.host() ?? "Imported book")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BookLoomStyle.ink)
                        .lineLimit(2)
                    if let author = item.displayAuthor {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            actionLayout {
                Button(action: onSaveToShelf) {
                    Label("Save to Shelf", systemImage: "books.vertical.fill")
                        .symbolRenderingMode(.monochrome)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BookLoomProminentButtonStyle())
                .controlSize(.regular)

                Button(action: onAddToClub) {
                    Label("Add to Club", systemImage: "person.2.fill")
                        .symbolRenderingMode(.monochrome)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BookLoomSecondaryButtonStyle())
                .controlSize(.regular)

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .symbolRenderingMode(.monochrome)
                        .frame(minWidth: 32)
                }
                .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.coral))
                .controlSize(.regular)
                .accessibilityLabel("Discard import")
            }
        }
        .bookLoomCard(padding: 10)
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.adaptiveLayout(expanded: VStackLayout(spacing: 8), compact: HStackLayout(spacing: 8))
    }
}

#endif

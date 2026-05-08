#if os(iOS)
import SwiftData
import SwiftUI

private enum ShelfClubAddOutcome: Equatable {
    case added(String)
    case alreadyAdded(String)
    case failed(String)

    var title: String {
        switch self {
        case .added:
            "Added to Club"
        case .alreadyAdded:
            "Already in Club"
        case .failed:
            "Couldn't Add to Club"
        }
    }

    var message: String {
        switch self {
        case .added(let clubName):
            "This book is now in \(clubName)'s proposals."
        case .alreadyAdded(let clubName):
            "This book is already in \(clubName)'s proposals or reading history."
        case .failed(let message):
            message
        }
    }
}

struct LibraryTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(ActiveClubStore.self) private var activeClubStore
    @Environment(GoodreadsImportInbox.self) private var goodreadsInbox
    @Query(sort: \BookClub.createdAt, order: .reverse) private var clubs: [BookClub]

    @State private var books: [LibraryBook] = []
    @State private var searchText = ""
    @State private var filter: MobileLibraryFilter = .all
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var showingNewBook = false
    @State private var selectedBook: LibraryBook?
    @State private var pendingDeleteBook: LibraryBook?

    private let pageSize = 80

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
                    options: MobileLibraryFilter.allCases
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
                if visibleBooks.isEmpty {
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
                            .onAppear(perform: loadMore)
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
        books = []
        canLoadMore = true
        loadMore()
    }

    private func loadMoreIfNeeded(after book: LibraryBook) {
        guard visibleBooks.last?.persistentModelID == book.persistentModelID else { return }
        loadMore()
    }

    private func loadMore() {
        guard canLoadMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var descriptor = FetchDescriptor<LibraryBook>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = books.count

        do {
            let nextPage = try context.fetch(descriptor)
            books.append(contentsOf: nextPage)
            canLoadMore = nextPage.count == pageSize
        } catch {
            canLoadMore = false
            assertionFailure("Failed to load library books: \(error.localizedDescription)")
        }
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
        context.insert(LibraryBook.fromPendingImport(item))
        goodreadsInbox.remove(item.url)
        saveContext()
        resetAndLoad()
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
        books.removeAll { $0.persistentModelID == deletedID }
        context.delete(book)
        saveContext()
        if books.isEmpty, canLoadMore {
            loadMore()
        }
    }

    private func addToClub(_ book: LibraryBook) -> ShelfClubAddOutcome {
        guard let activeClub else {
            return .failed("Choose an active club before adding shelf books to club proposals.")
        }
        guard !activeClub.containsLibraryBook(book) else {
            return .alreadyAdded(activeClub.name)
        }

        let submission = BookSubmission(
            title: book.title,
            author: book.author,
            isbn: book.isbn,
            bookDescription: book.bookDescription,
            publishedYear: book.publishedYear,
            coverURL: book.coverURL,
            externalProvider: book.externalProvider,
            externalID: book.externalID,
            submittedBy: memberIdentity.name,
            submittedByMemberID: memberIdentity.memberID
        )
        activeClub.addSubmission(submission)
        context.insert(submission)
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: activeClub,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
            return .added(activeClub.name)
        } catch {
            context.delete(submission)
            return .failed(error.localizedDescription)
        }
    }

    private func saveNewBook(_ draft: AddBookDraft, action: AddBookComposerAction) throws {
        let book = draft.makeLibraryBook()
        context.insert(book)

        switch action {
        case .libraryOnly:
            try context.save()
        case .clubProposed, .clubCompleted:
            guard let activeClub else {
                try context.save()
                return
            }
            let status: BookSubmissionStatus = action == .clubCompleted ? .completed : .proposed
            let submission = draft.makeSubmission(
                memberID: memberIdentity.memberID,
                memberName: memberIdentity.name,
                status: status
            )
            activeClub.addSubmission(submission)
            context.insert(submission)
            try SharedClubSync.saveAndPublish(
                context: context,
                club: activeClub,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
        }
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save library changes: \(error.localizedDescription)")
        }
    }
}

private enum MobileLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case owned
    case wishlist
    case loaned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .owned: "Owned"
        case .wishlist: "Wishlist"
        case .loaned: "Loaned"
        }
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

private extension BookClub {
    func containsLibraryBook(_ book: LibraryBook) -> Bool {
        (submissions ?? []).contains { $0.matchesLibraryBook(book) }
    }
}

private extension BookSubmission {
    func matchesLibraryBook(_ book: LibraryBook) -> Bool {
        if book.matchesSubmission(self) {
            return true
        }

        let bookISBN = book.isbn.trimmed.lowercased()
        let submissionISBN = isbn.trimmed.lowercased()
        if !bookISBN.isEmpty, bookISBN == submissionISBN {
            return true
        }

        let bookTitle = book.title.trimmed.lowercased()
        let submissionTitle = title.trimmed.lowercased()
        guard !bookTitle.isEmpty, bookTitle == submissionTitle else {
            return false
        }

        let bookAuthor = book.author.trimmed.lowercased()
        let submissionAuthor = author.trimmed.lowercased()
        return bookAuthor.isEmpty || submissionAuthor.isEmpty || bookAuthor == submissionAuthor
    }
}

private extension LibraryBookFormat {
    var cardLabel: String {
        switch self {
        case .hardcover: "Hardback"
        case .paperback: "Paperback"
        case .ebook: "E-book"
        case .audiobook: "Audio"
        case .other: "Other"
        }
    }

    var cardSystemImage: String {
        switch self {
        case .hardcover: "book.closed.fill"
        case .paperback: "book.fill"
        case .ebook: "ipad"
        case .audiobook: "headphones"
        case .other: "bookmark.fill"
        }
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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BookLoomStyle.plum)

                Button(action: onAddToClub) {
                    Label("Add to Club", systemImage: "person.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(BookLoomStyle.plum)

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .frame(minWidth: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Discard import")
            }
            .font(.caption.weight(.semibold))
            .controlSize(.small)
        }
        .bookLoomCard(padding: 10)
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.prefersExpandedControlLayout
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }
}

private struct MobileLibraryBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var book: LibraryBook
    let activeClub: BookClub?
    let onAddToClub: () -> ShelfClubAddOutcome
    let onDelete: () -> Void
    let onSave: () -> Void
    @State private var priceText: String
    @State private var showingMetadataSearch = false
    @State private var clubAddOutcome: ShelfClubAddOutcome?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        book: LibraryBook,
        activeClub: BookClub?,
        onAddToClub: @escaping () -> ShelfClubAddOutcome,
        onDelete: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.book = book
        self.activeClub = activeClub
        self.onAddToClub = onAddToClub
        self.onDelete = onDelete
        self.onSave = onSave
        _priceText = State(initialValue: Self.priceText(for: book))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                if !book.bookDescription.trimmed.isEmpty {
                    descriptionCard
                }
                bookCard
                trackingCard
                purchaseCard
                giftCard
                notesCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .bookLoomScreenBackground()
        .navigationTitle("Book")
        .bookLoomNavigationBar()
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .sheet(isPresented: $showingMetadataSearch) {
            BookMetadataSearchView(title: book.title, author: book.author, isbn: book.isbn) { candidate in
                apply(candidate)
            }
        }
        .alert(clubAddOutcome?.title ?? "", isPresented: clubAddAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(clubAddOutcome?.message ?? "")
        }
    }

    private var heroCard: some View {
        heroLayout {
            BookCoverTile(
                title: book.displayTitle,
                author: book.displayAuthor,
                coverURL: book.coverImageURL,
                width: 92,
                height: 132
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(book.displayTitle)
                    .font(.title3.bold())
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !book.displayAuthor.isEmpty {
                    Text(book.displayAuthor)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    TintedCapsuleLabel(text: book.format.cardLabel, tint: BookLoomStyle.indigo, systemImage: book.format.cardSystemImage)
                    if book.personalRatingStars > 0 {
                        TintedCapsuleLabel(text: "\(min(book.personalRatingStars, 5))/5", tint: BookLoomStyle.gold, systemImage: "star.fill")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .bookLoomCard(padding: 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var descriptionCard: some View {
        MobileBookEditCard(title: "Description", systemImage: "text.book.closed.fill") {
            Text(book.bookDescription.trimmed)
                .font(.body)
                .foregroundStyle(BookLoomStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bookCard: some View {
        MobileBookEditCard(title: "Book", systemImage: "book.closed.fill") {
            BookLoomCompactTextField("Title", text: $book.title)
            BookLoomCompactDivider()
            BookLoomCompactTextField("Author", text: $book.author)
            BookLoomCompactDivider()
            BookLoomCompactTextField("ISBN", text: $book.isbn, keyboard: .numbersAndPunctuation)
            MobileBookMenuRow(
                title: "Format",
                value: book.format.displayName,
                systemImage: book.format.cardSystemImage
            ) {
                ForEach(LibraryBookFormat.allCases) { format in
                    Button(format.displayName) {
                        formatBinding.wrappedValue = format
                    }
                }
            }
            MobileBookMenuRow(
                title: "Condition",
                value: book.condition.displayName,
                systemImage: "sparkles"
            ) {
                ForEach(LibraryBookCondition.allCases) { condition in
                    Button(condition.displayName) {
                        conditionBinding.wrappedValue = condition
                    }
                }
            }
            BookLoomCompactTextField("Shelf or room", text: $book.shelfLocation)
            Button {
                showingMetadataSearch = true
            } label: {
                Label(metadataButtonTitle, systemImage: "magnifyingglass")
            }
            .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.indigo))
            .disabled(book.title.trimmed.isEmpty && book.isbn.trimmed.isEmpty)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete from Shelf", systemImage: "trash")
            }
            .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.coral))
        }
    }

    private var trackingCard: some View {
        MobileBookEditCard(title: "Personal Tracking", systemImage: "checkmark.seal.fill") {
            ratingLayout {
                MobileBookRowLabel(title: "Rating", systemImage: "star.fill")
                if !dynamicTypeSize.prefersExpandedControlLayout {
                    Spacer(minLength: 12)
                }
                StarRatingPicker(stars: ratingBinding)
            }
            .padding(.vertical, 3)

            propertyButtonGrid

            if book.isOnLoan && book.countsAsOwned {
                BookLoomCompactTextField("Loaned to", text: $book.loanedTo)
                Button {
                    markReturned()
                } label: {
                    Label("Mark Returned", systemImage: "arrow.uturn.left.circle.fill")
                }
                .buttonStyle(BookLoomSecondaryButtonStyle())
            }
        }
    }

    private var propertyButtonGrid: some View {
        LazyVGrid(columns: propertyButtonColumns, alignment: .leading, spacing: 8) {
            AddBookPropertyButton(
                title: "Owned",
                systemImage: "books.vertical.fill",
                tint: BookLoomStyle.indigo,
                isOn: ownedBinding
            )
            AddBookPropertyButton(
                title: "Wishlist",
                systemImage: "star.fill",
                tint: BookLoomStyle.gold,
                isOn: wishlistBinding
            )
            AddBookPropertyButton(
                title: "Read",
                systemImage: "checkmark.seal.fill",
                tint: BookLoomStyle.sage,
                isOn: $book.didRead
            )
            AddBookPropertyButton(
                title: "Audio",
                systemImage: "headphones",
                tint: BookLoomStyle.plum,
                isOn: audiobookBinding
            )
            AddBookPropertyButton(
                title: "Signed",
                systemImage: "signature",
                tint: BookLoomStyle.coral,
                isOn: $book.isSigned
            )
            AddBookPropertyButton(
                title: "Loaned Out",
                systemImage: "person.crop.circle.badge.clock",
                tint: BookLoomStyle.plum,
                isOn: loanBinding
            )
        }
        .padding(.vertical, 2)
    }

    private var propertyButtonColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: dynamicTypeSize.prefersExpandedControlLayout ? 180 : 116), spacing: 8, alignment: .leading)
        ]
    }

    private var purchaseCard: some View {
        MobileBookEditCard(title: "Purchase", systemImage: "creditcard.fill") {
            BookLoomCompactTextField("Paid", text: $priceText, placeholder: "$0.00", keyboard: .decimalPad)
            BookLoomCompactTextField("Purchased from", text: $book.purchaseSource)

            if hasPurchaseDetails {
                Button {
                    clearPrice()
                } label: {
                    Label("Clear Purchase Details", systemImage: "xmark.circle")
                }
                .buttonStyle(BookLoomSecondaryButtonStyle())
            }
        }
    }

    private var giftCard: some View {
        MobileBookEditCard(title: "Gift Plan", systemImage: "gift.fill") {
            BookLoomCompactTextField("Give to", text: $book.intendedRecipient)
            BookLoomCompactTextField("Occasion", text: $book.giftOccasion)

            if hasGiftDetails {
                Button {
                    clearGiftPlan()
                } label: {
                    Label("Clear Gift Plan", systemImage: "gift")
                }
                .buttonStyle(BookLoomSecondaryButtonStyle())
            }
        }
    }

    private var notesCard: some View {
        MobileBookEditCard(title: "Private Notes", systemImage: "note.text") {
            BookLoomCompactTextField(
                "Notes",
                text: $book.privateNotes,
                placeholder: "Edition notes, provenance, repairs, reminders...",
                isMultiline: true
            )
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                clubAddOutcome = onAddToClub()
            } label: {
                Label(clubAddButtonTitle, systemImage: clubAddButtonSystemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookLoomSecondaryButtonStyle())
            .disabled(activeClub == nil || isInActiveClub)

            Button {
                applyPrice()
                book.updatedAt = .now
                onSave()
                dismiss()
            } label: {
                Label("Save Changes", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookLoomProminentButtonStyle())
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }

    private var hasPurchaseDetails: Bool {
        !priceText.trimmed.isEmpty || book.purchasePriceCents != nil || !book.purchaseSource.trimmed.isEmpty
    }

    private var hasGiftDetails: Bool {
        book.hasGiftPlan || !book.intendedRecipient.trimmed.isEmpty || !book.giftOccasion.trimmed.isEmpty
    }

    private var metadataButtonTitle: String {
        "Search for Cover and Details"
    }

    private var isInActiveClub: Bool {
        activeClub?.containsLibraryBook(book) ?? false
    }

    private var clubAddButtonTitle: String {
        guard let activeClub else { return "Add to Club" }
        return isInActiveClub ? "In \(activeClub.name)" : "Add to \(activeClub.name)"
    }

    private var clubAddButtonSystemImage: String {
        isInActiveClub ? "checkmark.seal.fill" : "person.2.fill"
    }

    private var clubAddAlertPresented: Binding<Bool> {
        Binding(
            get: { clubAddOutcome != nil },
            set: { isPresented in
                if !isPresented {
                    clubAddOutcome = nil
                }
            }
        )
    }

    private var heroLayout: AnyLayout {
        dynamicTypeSize.prefersExpandedControlLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    private var ratingLayout: AnyLayout {
        dynamicTypeSize.prefersExpandedControlLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center))
    }

    private var formatBinding: Binding<LibraryBookFormat> {
        Binding(
            get: { book.format },
            set: {
                book.format = $0
                book.updatedAt = .now
            }
        )
    }

    private var conditionBinding: Binding<LibraryBookCondition> {
        Binding(
            get: { book.condition },
            set: {
                book.condition = $0
                book.updatedAt = .now
            }
        )
    }

    private var ratingBinding: Binding<Int> {
        Binding(
            get: { min(max(book.personalRatingStars, 0), 5) },
            set: {
                book.setPersonalRatingStars($0)
            }
        )
    }

    private var ownedBinding: Binding<Bool> {
        Binding(
            get: { book.countsAsOwned },
            set: { book.setOwned($0) }
        )
    }

    private var wishlistBinding: Binding<Bool> {
        Binding(
            get: { book.isWishlist },
            set: { book.setWishlist($0) }
        )
    }

    private var audiobookBinding: Binding<Bool> {
        Binding(
            get: { book.didListenToAudiobook },
            set: { book.setAudiobookListened($0) }
        )
    }

    private var loanBinding: Binding<Bool> {
        Binding(
            get: { book.isOnLoan && book.countsAsOwned },
            set: {
                book.isOnLoan = $0
                if $0 {
                    book.setOwned(true)
                    if book.loanedAt == nil {
                        book.loanedAt = .now
                    }
                } else {
                    book.loanedTo = ""
                    book.loanedAt = nil
                    book.loanDueDate = nil
                }
                book.updatedAt = .now
            }
        )
    }

    private func apply(_ candidate: BookMetadataCandidate) {
        book.applyMetadata(candidate)
        onSave()
    }

    private func applyPrice() {
        let trimmed = priceText.trimmed
        guard !trimmed.isEmpty else {
            book.purchasePriceCents = nil
            return
        }
        let normalized = trimmed
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized) else { return }
        book.purchasePriceCents = Int((value * 100).rounded())
    }

    private func clearPrice() {
        priceText = ""
        book.purchasePriceCents = nil
        book.purchaseSource = ""
        book.updatedAt = .now
        onSave()
    }

    private func markReturned() {
        book.isOnLoan = false
        book.loanedTo = ""
        book.loanedAt = nil
        book.loanDueDate = nil
        book.updatedAt = .now
        onSave()
    }

    private func clearGiftPlan() {
        book.intendedRecipient = ""
        book.giftOccasion = ""
        book.giftByDate = nil
        book.updatedAt = .now
        onSave()
    }

    private static func priceText(for book: LibraryBook) -> String {
        guard let cents = book.purchasePriceCents else { return "" }
        return String(format: "%.2f", Double(cents) / 100)
    }
}

private struct MobileBookEditCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(BookLoomStyle.ink)

            VStack(spacing: 10) {
                content
            }
        }
        .bookLoomCard(padding: 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MobileBookRowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BookLoomStyle.ink)
            .labelStyle(.titleAndIcon)
    }
}

private struct MobileBookMenuRow<Content: View>: View {
    let title: String
    let value: String
    let systemImage: String
    let content: Content

    init(title: String, value: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 12) {
                MobileBookRowLabel(title: title, systemImage: systemImage)
                Spacer(minLength: 12)
                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.plum)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BookLoomStyle.plum)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

#endif

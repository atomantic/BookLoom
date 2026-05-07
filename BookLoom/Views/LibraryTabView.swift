#if os(iOS)
import SwiftData
import SwiftUI

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

                Picker("Shelf filter", selection: $filter) {
                    ForEach(MobileLibraryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
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

    private func addToClub(_ book: LibraryBook) {
        guard let activeClub else { return }
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
        } catch {
            assertionFailure("Failed to add library book to club: \(error.localizedDescription)")
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

            HStack(spacing: 8) {
                Button(action: onSaveToShelf) {
                    Label("Save to Shelf", systemImage: "books.vertical.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(BookLoomStyle.plum)

                Button(action: onAddToClub) {
                    Label("Add to Club", systemImage: "person.2.fill")
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
}

private struct MobileLibraryBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var book: LibraryBook
    let activeClub: BookClub?
    let onAddToClub: () -> Void
    let onSave: () -> Void
    @State private var priceText: String
    @State private var showingMetadataSearch = false

    init(book: LibraryBook, activeClub: BookClub?, onAddToClub: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.book = book
        self.activeClub = activeClub
        self.onAddToClub = onAddToClub
        self.onSave = onSave
        _priceText = State(initialValue: Self.priceText(for: book))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
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
    }

    private var heroCard: some View {
        HStack(spacing: 16) {
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

    private var bookCard: some View {
        MobileBookEditCard(title: "Book", systemImage: "book.closed.fill") {
            MobileBookTextField("Title", text: $book.title)
            MobileBookTextField("Author", text: $book.author)
            MobileBookTextField("ISBN", text: $book.isbn, keyboardType: .numbersAndPunctuation)
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
            MobileBookTextField("Shelf or room", text: $book.shelfLocation)
            Button {
                showingMetadataSearch = true
            } label: {
                Label(metadataButtonTitle, systemImage: "magnifyingglass")
            }
            .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.indigo))
            .disabled(book.title.trimmed.isEmpty && book.isbn.trimmed.isEmpty)
        }
    }

    private var trackingCard: some View {
        MobileBookEditCard(title: "Personal Tracking", systemImage: "checkmark.seal.fill") {
            HStack(alignment: .center) {
                MobileBookRowLabel(title: "Rating", systemImage: "star.fill")
                Spacer(minLength: 12)
                StarRatingPicker(stars: ratingBinding)
            }
            .padding(.vertical, 3)

            propertyButtonGrid

            if book.isOnLoan && book.countsAsOwned {
                MobileBookTextField("Loaned to", text: $book.loanedTo)
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
            GridItem(.adaptive(minimum: 116), spacing: 8, alignment: .leading)
        ]
    }

    private var purchaseCard: some View {
        MobileBookEditCard(title: "Purchase", systemImage: "creditcard.fill") {
            MobileBookTextField("Paid", text: $priceText, placeholder: "$0.00", keyboardType: .decimalPad)
            MobileBookTextField("Purchased from", text: $book.purchaseSource)

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
            MobileBookTextField("Give to", text: $book.intendedRecipient)
            MobileBookTextField("Occasion", text: $book.giftOccasion)

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
            MobileBookTextField(
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
                onAddToClub()
            } label: {
                Label(activeClub.map { "Add to \($0.name)" } ?? "Add to Club", systemImage: "person.2.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookLoomSecondaryButtonStyle())
            .disabled(activeClub == nil)

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
        book.coverImageURL == nil && book.externalProvider.trimmed.isEmpty ? "Find Cover & Details" : "Change Cover & Details"
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

private struct MobileBookTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String?
    var keyboardType: UIKeyboardType = .default
    var isMultiline = false

    init(
        _ title: String,
        text: Binding<String>,
        placeholder: String? = nil,
        keyboardType: UIKeyboardType = .default,
        isMultiline: Bool = false
    ) {
        self.title = title
        _text = text
        self.placeholder = placeholder
        self.keyboardType = keyboardType
        self.isMultiline = isMultiline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("", text: $text, prompt: Text(placeholder ?? title), axis: isMultiline ? .vertical : .horizontal)
                .font(.body)
                .foregroundStyle(BookLoomStyle.ink)
                .keyboardType(keyboardType)
                .autocorrectionDisabled(title == "ISBN")
                .textInputAutocapitalization(title == "ISBN" ? .characters : .sentences)
                .lineLimit(isMultiline ? 4...8 : 1...1)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }
        }
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

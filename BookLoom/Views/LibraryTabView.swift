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

    private let pageSize = 80

    var body: some View {
        List {
            Section {
                MobileLibrarySummary(
                    totalCount: books.count,
                    readCount: books.filter(\.didRead).count,
                    listenedCount: books.filter(\.didListenToAudiobook).count,
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
                        systemImage: "books.vertical",
                        title: "No Books on Your Shelf",
                        message: emptyMessage
                    )
                    .bookLoomListRow()
                } else {
                    ForEach(visibleBooks) { book in
                        NavigationLink {
                            MobileLibraryBookDetailView(
                                book: book,
                                activeClub: activeClub,
                                onAddToClub: { addToClub(book) },
                                onSave: saveContext
                            )
                        } label: {
                            MobileLibraryBookRow(book: book)
                        }
                        .buttonStyle(.plain)
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
                SectionTitle(title: "Shelf", detail: "\(visibleBooks.count)")
            }
        }
        .bookLoomListStyle()
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationTitle("Shelf")
        .bookLoomNavigationBar()
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
            MobileNewShelfBookView { book in
                context.insert(book)
                saveContext()
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

    private var visibleBooks: [LibraryBook] {
        let query = searchText.trimmed
        return books.filter { book in
            switch filter {
            case .all: break
            case .read: guard book.didRead else { return false }
            case .listened: guard book.didListenToAudiobook else { return false }
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

    private var emptyMessage: String {
        searchText.trimmed.isEmpty ? "Scan or add books to build your personal shelf." : "Try another title, author, ISBN, or shelf."
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
    case read
    case listened
    case loaned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .read: "Read"
        case .listened: "Listened"
        case .loaned: "Loaned"
        }
    }
}

private struct MobileLibrarySummary: View {
    let totalCount: Int
    let readCount: Int
    let listenedCount: Int
    let importCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Personal Shelf", systemImage: "books.vertical.fill")
                .font(.headline.bold())
                .foregroundStyle(BookLoomStyle.ink)

            HStack(spacing: 10) {
                MetricTile(value: "\(totalCount)", label: "books", systemImage: "books.vertical.fill", tint: BookLoomStyle.indigo)
                MetricTile(value: "\(readCount)", label: "read", systemImage: "checkmark.seal.fill", tint: BookLoomStyle.sage)
                MetricTile(value: "\(listenedCount)", label: "listened", systemImage: "headphones", tint: BookLoomStyle.plum)
                if importCount > 0 {
                    MetricTile(value: "\(importCount)", label: "imports", systemImage: "tray.fill", tint: BookLoomStyle.gold)
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
            items.insert(
                BookCardIndicator("\(min(book.personalRatingStars, 5))/5", systemImage: "star.fill", tint: BookLoomStyle.gold),
                at: 0
            )
        }
        if book.didRead {
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

                Button(action: onAddToClub) {
                    Label("Add to Club", systemImage: "person.2.fill")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .frame(minWidth: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Discard import")
            }
            .font(.caption.weight(.semibold))
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

    init(book: LibraryBook, activeClub: BookClub?, onAddToClub: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.book = book
        self.activeClub = activeClub
        self.onAddToClub = onAddToClub
        self.onSave = onSave
        _priceText = State(initialValue: Self.priceText(for: book))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        BookCoverTile(
                            title: book.displayTitle,
                            author: book.displayAuthor,
                            coverURL: book.coverImageURL,
                            width: 76,
                            height: 108
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            Text(book.displayTitle)
                                .font(.headline.bold())
                                .foregroundStyle(BookLoomStyle.ink)
                            if !book.displayAuthor.isEmpty {
                                Text(book.displayAuthor)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .bookLoomCard(padding: 12)
            }
            .bookLoomListRow()

            Section {
                TextField("Title", text: $book.title)
                TextField("Author", text: $book.author)
                TextField("ISBN", text: $book.isbn)
                Picker("Format", selection: formatBinding) {
                    ForEach(LibraryBookFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                Picker("Condition", selection: conditionBinding) {
                    ForEach(LibraryBookCondition.allCases) { condition in
                        Text(condition.displayName).tag(condition)
                    }
                }
                TextField("Shelf or room", text: $book.shelfLocation)
            } header: {
                SectionTitle(title: "Book")
            }
            .bookLoomListRow()

            Section {
                Picker("Rating", selection: ratingBinding) {
                    Text("Not rated").tag(0)
                    ForEach(1...5, id: \.self) { stars in
                        Text("\(stars) star\(stars == 1 ? "" : "s")").tag(stars)
                    }
                }
                Toggle("I read this", isOn: $book.didRead)
                Toggle("I listened to the audiobook", isOn: $book.didListenToAudiobook)
                Toggle("Signed copy", isOn: $book.isSigned)
                Toggle("On loan", isOn: $book.isOnLoan)
                if book.isOnLoan {
                    TextField("Loaned to", text: $book.loanedTo)
                    Button {
                        markReturned()
                    } label: {
                        Label("Mark Returned", systemImage: "arrow.uturn.left.circle.fill")
                    }
                }
            } header: {
                SectionTitle(title: "Personal Tracking")
            }
            .bookLoomListRow()

            Section {
                TextField("Paid", text: $priceText, prompt: Text("$0.00"))
                    .keyboardType(.decimalPad)
                TextField("Purchased from", text: $book.purchaseSource)
                Button {
                    clearPrice()
                } label: {
                    Label("Clear Price", systemImage: "xmark.circle")
                }
                .disabled(priceText.trimmed.isEmpty && book.purchasePriceCents == nil)
            } header: {
                SectionTitle(title: "Purchase")
            }
            .bookLoomListRow()

            Section {
                TextField("Give to", text: $book.intendedRecipient)
                TextField("Occasion", text: $book.giftOccasion)
                Button {
                    clearGiftPlan()
                } label: {
                    Label("Clear Gift Plan", systemImage: "gift")
                }
                .disabled(!book.hasGiftPlan && book.giftOccasion.trimmed.isEmpty)
            } header: {
                SectionTitle(title: "Gift Plan")
            }
            .bookLoomListRow()

            Section {
                TextField("Edition notes, provenance, repairs, reminders...", text: $book.privateNotes, axis: .vertical)
                    .lineLimit(4...8)
            } header: {
                SectionTitle(title: "Private Notes")
            }
            .bookLoomListRow()

            Section {
                Button {
                    onAddToClub()
                } label: {
                    Label(activeClub.map { "Add to \($0.name)" } ?? "Add to Club", systemImage: "person.2.fill")
                }
                .disabled(activeClub == nil)

                Button {
                    applyPrice()
                    book.updatedAt = .now
                    onSave()
                    dismiss()
                } label: {
                    Label("Save Changes", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
            .bookLoomListRow()
        }
        .bookLoomListStyle()
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationTitle("Book")
        .bookLoomNavigationBar()
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
                book.personalRatingStars = min(max($0, 0), 5)
                book.updatedAt = .now
            }
        )
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

private struct MobileNewShelfBookView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (LibraryBook) -> Void

    @State private var title = ""
    @State private var author = ""
    @State private var isbn = ""
    @State private var selectedMetadata: BookMetadataCandidate?
    @State private var didRead = false
    @State private var didListen = false
    @State private var format: LibraryBookFormat = .hardcover
    @State private var condition: LibraryBookCondition = .good
    @State private var shelfLocation = ""
    @State private var isSigned = false
    @State private var personalRatingStars = 0
    @State private var priceText = ""
    @State private var purchaseSource = ""

    var body: some View {
        NavigationStack {
            Form {
                if let selectedMetadata {
                    Section {
                        BookMetadataVerificationPreview(
                            title: title,
                            author: author,
                            candidate: selectedMetadata
                        )
                    } header: {
                        Text("Review")
                    } footer: {
                        Text("Verify the cover and details before saving this book to your Shelf.")
                    }
                } else {
                    Section {
                        ISBNMetadataLookupControls(
                            title: $title,
                            author: $author,
                            isbn: $isbn,
                            selectedMetadata: $selectedMetadata,
                            layout: .scanButtonOnly(title: "Scan ISBN")
                        )
                    } header: {
                        Text("Scan")
                    } footer: {
                        Text("Use the ISBN barcode or the printed ISBN inside the book.")
                    }

                    Section("Import") {
                        GoodreadsMetadataImportControls(
                            title: $title,
                            author: $author,
                            isbn: $isbn,
                            selectedMetadata: $selectedMetadata,
                            importButtonTitle: "Import from Goodreads",
                            importButtonSystemImage: "link",
                            buttonStyle: .bordered
                        )
                    }
                }

                Section("Book") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Author", text: $author)
                        .textInputAutocapitalization(.words)
                    TextField("ISBN", text: $isbn)
                        .textInputAutocapitalization(.characters)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()

                    BookMetadataSearchControls(
                        title: $title,
                        author: $author,
                        isbn: $isbn,
                        selectedMetadata: $selectedMetadata,
                        buttonStyle: .bordered,
                        showsSummary: false
                    )
                }
                Section("Personal Tracking") {
                    Picker("Rating", selection: $personalRatingStars) {
                        Text("Not rated").tag(0)
                        ForEach(1...5, id: \.self) { stars in
                            Text("\(stars) star\(stars == 1 ? "" : "s")").tag(stars)
                        }
                    }
                    Toggle("I read this", isOn: $didRead)
                    Toggle("I listened to the audiobook", isOn: $didListen)
                    Toggle("Signed copy", isOn: $isSigned)
                }
                Section("Copy Details") {
                    Picker("Format", selection: $format) {
                        ForEach(LibraryBookFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    Picker("Condition", selection: $condition) {
                        ForEach(LibraryBookCondition.allCases) { condition in
                            Text(condition.displayName).tag(condition)
                        }
                    }
                    TextField("Shelf or room", text: $shelfLocation)
                }
                Section("Purchase") {
                    TextField("Paid", text: $priceText, prompt: Text("$0.00"))
                        .keyboardType(.decimalPad)
                    TextField("Purchased from", text: $purchaseSource)
                }
            }
            .navigationTitle("New Shelf Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let book = LibraryBook(
                            title: title.trimmed,
                            author: author.trimmed,
                            isbn: selectedMetadata?.primaryISBN.trimmedOrNil ?? isbn.trimmed,
                            bookDescription: selectedMetadata?.description ?? "",
                            publishedYear: selectedMetadata?.publishedYear,
                            coverURL: selectedMetadata?.coverURL?.absoluteString ?? "",
                            externalProvider: selectedMetadata?.provider.rawValue ?? "",
                            externalID: selectedMetadata?.externalID ?? "",
                            sourceURLString: selectedMetadata?.sourceURL?.absoluteString ?? ""
                        )
                        book.didRead = didRead
                        book.didListenToAudiobook = didListen
                        book.personalRatingStars = personalRatingStars
                        book.format = format
                        book.condition = condition
                        book.shelfLocation = shelfLocation.trimmed
                        book.isSigned = isSigned
                        book.purchaseSource = purchaseSource.trimmed
                        book.purchasePriceCents = priceCents
                        onSave(book)
                        dismiss()
                    }
                    .disabled(title.trimmed.isEmpty)
                }
            }
        }
    }

    private var priceCents: Int? {
        let trimmed = priceText.trimmed
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized) else { return nil }
        return Int((value * 100).rounded())
    }
}
#endif

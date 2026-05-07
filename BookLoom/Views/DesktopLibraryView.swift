#if os(macOS)
import SwiftUI
import SwiftData

struct DesktopLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(ActiveClubStore.self) private var activeClubStore
    @Environment(GoodreadsImportInbox.self) private var goodreadsInbox
    @Query(sort: \LibraryBook.updatedAt, order: .reverse) private var libraryBooks: [LibraryBook]
    @Query(sort: \BookClub.createdAt, order: .reverse) private var clubs: [BookClub]

    @State private var selectedBookID: PersistentIdentifier?
    @State private var searchText = ""
    @State private var filter: LibraryFilter = .all
    @State private var presentedSidebar: DesktopLibrarySidebar?
    @State private var pendingDeleteBook: LibraryBook?

    var body: some View {
        HStack(spacing: 0) {
            librarySidebar
                .frame(minWidth: 330, idealWidth: 390, maxWidth: 460)
                .background(BookLoomStyle.ink.opacity(0.035))

            Divider()

            Group {
                if let selectedBook {
                    LibraryBookDetailView(
                        book: selectedBook,
                        onDelete: { pendingDeleteBook = selectedBook }
                    )
                        .id(selectedBook.persistentModelID)
                } else {
                    LibraryBookEmptyState(onAddBook: { presentedSidebar = .addBook })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .bookLoomScreenBackground()
        .navigationTitle("Shelf")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentedSidebar = .addBook
                } label: {
                    Label("Add Book", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    refreshShelf()
                } label: {
                    Label("Refresh Shelf", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    if let selectedBook {
                        pendingDeleteBook = selectedBook
                    }
                } label: {
                    Label("Delete Book", systemImage: "trash")
                }
                .disabled(selectedBook == nil)
            }
        }
        .bookLoomTrailingSidebar(
            item: $presentedSidebar,
            width: 860,
            onDismiss: { presentedSidebar = nil }
        ) { sidebar in
            switch sidebar {
            case .addBook:
                AddBookComposerView(
                    mode: addBookComposerMode,
                    onCancel: { presentedSidebar = nil }
                ) { draft, action in
                    let book = try saveNewBook(draft, action: action)
                    selectedBookID = book.persistentModelID
                }
            }
        }
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
        .onAppear {
            refreshShelf()
            if selectedBookID == nil {
                selectedBookID = filteredBooks.first?.persistentModelID
            }
        }
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            LibrarySummaryHeader(
                allCount: libraryBooks.count,
                ownedCount: libraryBooks.filter(\.countsAsOwned).count,
                readCount: libraryBooks.filter(\.isRead).count,
                wishlistCount: libraryBooks.filter(\.isWishlist).count,
                signedCount: libraryBooks.filter(\.isSigned).count,
                loanedCount: libraryBooks.filter(\.isOnLoan).count,
                giftCount: libraryBooks.filter(\.hasGiftPlan).count,
                shelfCount: goodreadsInbox.pending.count
            )
            .padding(.horizontal, 14)
            .padding(.top, 14)

            DesktopLibrarySearchField(text: $searchText)
                .padding(.horizontal, 14)

            Picker("Shelf filter", selection: $filter) {
                ForEach(LibraryFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)

            if !goodreadsInbox.pending.isEmpty {
                PendingShelfSection(
                    pending: goodreadsInbox.pending,
                    onAddToLibrary: savePendingImportToLibrary,
                    onAddToClub: { goodreadsInbox.present($0.url) },
                    onRemove: { goodreadsInbox.remove($0.url) }
                )
                .padding(.horizontal, 14)
            }

            List(selection: $selectedBookID) {
                ForEach(filteredBooks) { book in
                    LibraryBookSidebarRow(book: book)
                        .tag(book.persistentModelID)
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDeleteBook = book
                            } label: {
                                Label("Delete from Shelf", systemImage: "trash")
                            }
                        }
                }
                .onDelete(perform: deleteBooks)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private var selectedBook: LibraryBook? {
        if let selectedBookID,
           let match = libraryBooks.first(where: { $0.persistentModelID == selectedBookID }) {
            return match
        }
        return filteredBooks.first
    }

    private var activeClub: BookClub? {
        activeClubStore.resolveActiveClub(from: clubs.filter { !SchemaPrimeDataCleanup.isSchemaPrime($0) })
    }

    private var addBookComposerMode: AddBookComposerMode {
        activeClub.map { .club(name: $0.name) } ?? .library
    }

    private var filteredBooks: [LibraryBook] {
        let filtered = libraryBooks.filter { book in
            switch filter {
            case .all: return true
            case .owned: return book.countsAsOwned
            case .wishlist: return book.isWishlist
            case .loaned: return book.isOnLoan
            }
        }
        let query = searchText.trimmed
        guard !query.isEmpty else { return filtered }
        return filtered.filter { book in
            book.displayTitle.localizedCaseInsensitiveContains(query)
                || book.displayAuthor.localizedCaseInsensitiveContains(query)
                || book.isbn.localizedCaseInsensitiveContains(query)
                || book.shelfLocation.localizedCaseInsensitiveContains(query)
                || book.loanedTo.localizedCaseInsensitiveContains(query)
                || book.intendedRecipient.localizedCaseInsensitiveContains(query)
        }
    }

    private func refreshShelf() {
        goodreadsInbox.refresh()
        goodreadsInbox.prefetchAll()
    }

    private func savePendingImportToLibrary(_ item: SharedImportInbox.PendingImport) {
        if let existing = libraryBooks.first(where: { $0.matchesPendingImport(item) }) {
            selectedBookID = existing.persistentModelID
            goodreadsInbox.remove(item.url)
            return
        }

        let book = LibraryBook.fromPendingImport(item)
        context.insert(book)
        goodreadsInbox.remove(item.url)
        saveContext()
        selectedBookID = book.persistentModelID
    }

    private func deleteBooks(_ offsets: IndexSet) {
        let visibleBooks = filteredBooks
        performDelete(offsets.map { visibleBooks[$0] })
    }

    private func confirmDeleteBook() {
        guard let book = pendingDeleteBook else { return }
        pendingDeleteBook = nil
        performDelete([book])
    }

    private func performDelete(_ books: [LibraryBook]) {
        let idsToDelete = Set(books.map { $0.persistentModelID })
        let nextSelection = filteredBooks
            .first { !idsToDelete.contains($0.persistentModelID) }?
            .persistentModelID
        books.forEach(context.delete)
        saveContext()
        selectedBookID = nextSelection
    }

    private func saveNewBook(_ draft: AddBookDraft, action: AddBookComposerAction) throws -> LibraryBook {
        let book = draft.makeLibraryBook()
        context.insert(book)

        switch action {
        case .libraryOnly:
            try context.save()
        case .clubProposed, .clubCompleted:
            guard let activeClub else {
                try context.save()
                return book
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

        return book
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save library changes: \(error.localizedDescription)")
        }
    }
}

private enum DesktopLibrarySidebar: String, Identifiable {
    case addBook

    var id: String { rawValue }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case owned
    case wishlist
    case loaned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .owned: return "Owned"
        case .wishlist: return "Wishlist"
        case .loaned: return "Loaned"
        }
    }
}

private struct DesktopLibrarySearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search personal shelf", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear shelf search")
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(BookLoomStyle.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LibrarySummaryHeader: View {
    let allCount: Int
    let ownedCount: Int
    let readCount: Int
    let wishlistCount: Int
    let signedCount: Int
    let loanedCount: Int
    let giftCount: Int
    let shelfCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                BrandBadge(size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Personal Shelf")
                        .font(.headline.bold())
                        .foregroundStyle(BookLoomStyle.ink)
                    Text("\(allCount) books · \(ownedCount) owned")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                LibraryStatTile(value: "\(readCount)", label: "read", systemImage: "checkmark.seal.fill")
                LibraryStatTile(value: "\(ownedCount)", label: "owned", systemImage: "books.vertical.fill")
                LibraryStatTile(value: "\(wishlistCount)", label: "wishlist", systemImage: "star.fill")
                LibraryStatTile(value: "\(signedCount)", label: "signed", systemImage: "signature")
                LibraryStatTile(value: "\(loanedCount)", label: "loaned", systemImage: "arrowshape.turn.up.right.fill")
                LibraryStatTile(value: "\(giftCount)", label: "gifts", systemImage: "gift.fill")
                LibraryStatTile(value: "\(shelfCount)", label: "imports", systemImage: "tray.full.fill")
            }
        }
        .bookLoomCard(padding: 12)
    }
}

private struct LibraryStatTile: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(BookLoomStyle.indigo)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.headline.bold())
                    .foregroundStyle(BookLoomStyle.ink)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(BookLoomStyle.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PendingShelfSection: View {
    let pending: [SharedImportInbox.PendingImport]
    let onAddToLibrary: (SharedImportInbox.PendingImport) -> Void
    let onAddToClub: (SharedImportInbox.PendingImport) -> Void
    let onRemove: (SharedImportInbox.PendingImport) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Imports", detail: "\(pending.count)")

            ForEach(pending.prefix(3)) { item in
                PendingShelfRow(
                    item: item,
                    onAddToLibrary: { onAddToLibrary(item) },
                    onAddToClub: { onAddToClub(item) },
                    onRemove: { onRemove(item) }
                )
            }
        }
        .bookLoomCard(padding: 10)
    }
}

private struct PendingShelfRow: View {
    let item: SharedImportInbox.PendingImport
    let onAddToLibrary: () -> Void
    let onAddToClub: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BookCoverTile(
                title: item.displayTitle ?? "Book",
                author: item.displayAuthor ?? "",
                coverURL: item.coverURL,
                width: 38,
                height: 54
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle ?? item.url.lastPathComponent)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(2)
                if let author = item.displayAuthor {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Button(action: onAddToLibrary) {
                        Label("Save to Shelf", systemImage: "books.vertical.fill")
                    }
                    Button(action: onAddToClub) {
                        Label("Add to Club", systemImage: "person.2.fill")
                    }
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Discard import")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .labelStyle(.iconOnly)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(BookLoomStyle.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LibraryBookSidebarRow: View {
    @Bindable var book: LibraryBook

    var body: some View {
        HStack(spacing: 10) {
            BookCoverTile(
                title: book.displayTitle,
                author: book.displayAuthor,
                coverURL: book.coverImageURL,
                width: 44,
                height: 62
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(book.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(2)
                if !book.displayAuthor.isEmpty {
                    Text(book.displayAuthor)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                LibraryBadgeLine(badges: book.ownershipBadges)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LibraryBookDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var book: LibraryBook
    let onDelete: () -> Void

    @State private var priceText: String
    @State private var showingMetadataSearch = false

    init(book: LibraryBook, onDelete: @escaping () -> Void) {
        self.book = book
        self.onDelete = onDelete
        _priceText = State(initialValue: Self.priceText(for: book))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LibraryBookHero(
                    book: book,
                    onFindMetadata: { showingMetadataSearch = true },
                    onDelete: onDelete
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], alignment: .leading, spacing: 14) {
                    detailsCard
                    ownershipCard
                    if book.isOnLoan && book.countsAsOwned {
                        loanCard
                    }
                    giftCard
                    notesCard
                }
            }
            .padding(22)
            .frame(maxWidth: 1180, alignment: .topLeading)
        }
        .sheet(isPresented: $showingMetadataSearch) {
            BookMetadataSearchView(title: book.title, author: book.author, isbn: book.isbn) { candidate in
                apply(candidate)
            }
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Book")
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
            Button {
                saveChanges()
            } label: {
                Label("Save Details", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(BookLoomProminentButtonStyle())
            .bookLoomActionWidth(minWidth: 170)
        }
        .textFieldStyle(.roundedBorder)
        .bookLoomCard(padding: 12)
    }

    private var ownershipCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Ownership")
            HStack {
                Text("Rating")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 12)
                StarRatingPicker(stars: ratingBinding)
            }
            propertyButtonGrid
            TextField("Paid", text: $priceText, prompt: Text("$0.00"))
            TextField("Purchased from", text: $book.purchaseSource)
            Button {
                clearPrice()
            } label: {
                Label("Clear Price", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(priceText.trimmed.isEmpty && book.purchasePriceCents == nil)
        }
        .textFieldStyle(.roundedBorder)
        .bookLoomCard(padding: 12)
    }

    private var loanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Loan")
            TextField("Loaned to", text: $book.loanedTo)
            Button {
                markReturned()
            } label: {
                Label("Mark Returned", systemImage: "arrow.uturn.left.circle.fill")
            }
            .buttonStyle(.bordered)
        }
        .textFieldStyle(.roundedBorder)
        .bookLoomCard(padding: 12)
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

    private var giftCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Gift Plan")
            TextField("Give to", text: $book.intendedRecipient)
            TextField("Occasion", text: $book.giftOccasion)
            Button {
                clearGiftPlan()
            } label: {
                Label("Clear Gift Plan", systemImage: "gift")
            }
            .buttonStyle(.bordered)
            .disabled(!book.hasGiftPlan && book.giftOccasion.trimmed.isEmpty)
        }
        .textFieldStyle(.roundedBorder)
        .bookLoomCard(padding: 12)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Private Notes")
            TextField("Edition notes, provenance, repairs, reminders...", text: $book.privateNotes, axis: .vertical)
                .lineLimit(5...9)
                .textFieldStyle(.roundedBorder)
        }
        .bookLoomCard(padding: 12)
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
        saveChanges()
    }

    private func saveChanges() {
        applyPrice()
        book.updatedAt = .now
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save library book: \(error.localizedDescription)")
        }
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
        saveChanges()
    }

    private func markReturned() {
        book.isOnLoan = false
        book.loanedTo = ""
        book.loanedAt = nil
        book.loanDueDate = nil
        saveChanges()
    }

    private func clearGiftPlan() {
        book.intendedRecipient = ""
        book.giftOccasion = ""
        book.giftByDate = nil
        saveChanges()
    }

    private static func priceText(for book: LibraryBook) -> String {
        guard let cents = book.purchasePriceCents else { return "" }
        return String(format: "%.2f", Double(cents) / 100)
    }
}

private struct LibraryBookHero: View {
    @Bindable var book: LibraryBook
    let onFindMetadata: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            BookCoverTile(
                title: book.displayTitle,
                author: book.displayAuthor,
                coverURL: book.coverImageURL,
                width: 128,
                height: 184
            )

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.displayTitle)
                        .font(.largeTitle.bold())
                        .foregroundStyle(BookLoomStyle.ink)
                        .lineLimit(3)
                    if !book.displayAuthor.isEmpty {
                        Text(book.displayAuthor)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                LibraryBadgeLine(badges: book.ownershipBadges)

                HStack(spacing: 8) {
                    Label(book.format.displayName, systemImage: "book.closed.fill")
                    Label(book.condition.displayName, systemImage: "checkmark.seal.fill")
                    if !book.shelfLocation.trimmed.isEmpty {
                        Label(book.shelfLocation, systemImage: "mappin.and.ellipse")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                if !book.bookDescription.trimmed.isEmpty {
                    Text(book.bookDescription)
                        .font(.callout)
                        .foregroundStyle(BookLoomStyle.ink)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button(action: onFindMetadata) {
                        Label("Search for Cover and Details", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete from Shelf", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 0)
                }
            }
        }
        .bookLoomCard(padding: 16)
    }
}

private struct LibraryBadgeLine: View {
    let badges: [String]

    var body: some View {
        if badges.isEmpty {
            Text("No ownership notes")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BookLoomStyle.indigo)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(BookLoomStyle.indigo.opacity(0.10), in: Capsule())
                }
            }
        }
    }
}

private struct LibraryBookEmptyState: View {
    let onAddBook: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            BrandBadge(size: 68)
            VStack(spacing: 5) {
                Text("Build Your Shelf")
                    .font(.title.bold())
                    .foregroundStyle(BookLoomStyle.ink)
                Text("Track owned copies, wishlist titles, read history, loans, gift plans, purchase details, and shelf locations.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            Button(action: onAddBook) {
                Label("Add Book", systemImage: "plus.circle.fill")
            }
            .buttonStyle(BookLoomProminentButtonStyle())
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

#endif

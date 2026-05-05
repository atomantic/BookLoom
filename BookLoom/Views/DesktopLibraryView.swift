#if os(macOS)
import SwiftUI
import SwiftData

struct DesktopLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(GoodreadsImportInbox.self) private var goodreadsInbox
    @Query(sort: \LibraryBook.updatedAt, order: .reverse) private var libraryBooks: [LibraryBook]

    @State private var selectedBookID: PersistentIdentifier?
    @State private var searchText = ""
    @State private var filter: LibraryFilter = .all
    @State private var showingNewBook = false

    var body: some View {
        HStack(spacing: 0) {
            librarySidebar
                .frame(minWidth: 330, idealWidth: 390, maxWidth: 460)
                .background(BookLoomStyle.ink.opacity(0.035))

            Divider()

            Group {
                if let selectedBook {
                    LibraryBookDetailView(book: selectedBook)
                        .id(selectedBook.persistentModelID)
                } else {
                    LibraryBookEmptyState(onAddBook: { showingNewBook = true })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .bookLoomScreenBackground()
        .navigationTitle("Shelf")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewBook = true
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
        }
        .sheet(isPresented: $showingNewBook) {
            NewLibraryBookView { book in
                context.insert(book)
                saveContext()
                selectedBookID = book.persistentModelID
            }
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
                totalCount: libraryBooks.count,
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

    private var filteredBooks: [LibraryBook] {
        let filtered = libraryBooks.filter { book in
            switch filter {
            case .all: return true
            case .signed: return book.isSigned
            case .loaned: return book.isOnLoan
            case .gift: return book.hasGiftPlan
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
        for index in offsets {
            context.delete(filteredBooks[index])
        }
        saveContext()
        selectedBookID = filteredBooks.first?.persistentModelID
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save library changes: \(error.localizedDescription)")
        }
    }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case signed
    case loaned
    case gift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .signed: return "Signed"
        case .loaned: return "Loaned"
        case .gift: return "Gifts"
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
    let totalCount: Int
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
                    Text("\(totalCount) books managed")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
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

    @State private var priceText: String
    @State private var showingMetadataSearch = false

    init(book: LibraryBook) {
        self.book = book
        _priceText = State(initialValue: Self.priceText(for: book))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LibraryBookHero(book: book, onFindMetadata: { showingMetadataSearch = true })

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], alignment: .leading, spacing: 14) {
                    detailsCard
                    ownershipCard
                    loanCard
                    giftCard
                    notesCard
                }
            }
            .padding(22)
            .frame(maxWidth: 1180, alignment: .topLeading)
        }
        .sheet(isPresented: $showingMetadataSearch) {
            BookMetadataSearchView(title: book.title, author: book.author) { candidate in
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
            .buttonStyle(.borderedProminent)
            .bookLoomActionWidth(minWidth: 170)
        }
        .textFieldStyle(.roundedBorder)
        .bookLoomCard(padding: 12)
    }

    private var ownershipCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Ownership")
            Toggle("Signed copy", isOn: $book.isSigned)
                .toggleStyle(.switch)
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
            Toggle("Currently on loan", isOn: $book.isOnLoan)
                .toggleStyle(.switch)
            TextField("Loaned to", text: $book.loanedTo)
                .disabled(!book.isOnLoan)
            if book.isOnLoan {
                Button {
                    markReturned()
                } label: {
                    Label("Mark Returned", systemImage: "arrow.uturn.left.circle.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .textFieldStyle(.roundedBorder)
        .bookLoomCard(padding: 12)
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

    private func apply(_ candidate: BookMetadataCandidate) {
        book.title = candidate.title
        book.author = candidate.authorLine
        book.isbn = candidate.isbn ?? book.isbn
        book.bookDescription = candidate.description ?? ""
        book.publishedYear = candidate.publishedYear
        book.coverURL = candidate.coverURL?.absoluteString ?? ""
        book.externalProvider = candidate.provider.rawValue
        book.externalID = candidate.externalID
        book.sourceURLString = candidate.sourceURL?.absoluteString ?? book.sourceURLString
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

                HStack {
                    Button(action: onFindMetadata) {
                        Label("Find Cover & Details", systemImage: "magnifyingglass")
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
                Text("Track owned copies, signed editions, loaned books, gift plans, purchase details, and shelf locations.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            Button(action: onAddBook) {
                Label("Add Book", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

private struct NewLibraryBookView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (LibraryBook) -> Void

    @State private var title = ""
    @State private var author = ""
    @State private var isbn = ""
    @State private var shelfLocation = ""
    @State private var priceText = ""
    @State private var isSigned = false
    @State private var format: LibraryBookFormat = .hardcover
    @State private var selectedMetadata: BookMetadataCandidate?
    @State private var showingMetadataSearch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        BookCoverTile(
                            title: title,
                            author: author,
                            coverURL: selectedMetadata?.coverURL,
                            width: 82,
                            height: 118
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add to Shelf")
                                .font(.title2.bold())
                                .foregroundStyle(BookLoomStyle.ink)
                            TextField("Title", text: $title)
                            TextField("Author", text: $author)
                            TextField("ISBN", text: $isbn)
                        }
                    }

                    HStack(spacing: 10) {
                        Picker("Format", selection: $format) {
                            ForEach(LibraryBookFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        Toggle("Signed", isOn: $isSigned)
                            .toggleStyle(.switch)
                    }

                    TextField("Shelf or room", text: $shelfLocation)
                    TextField("Paid", text: $priceText, prompt: Text("$0.00"))

                    Button {
                        showingMetadataSearch = true
                    } label: {
                        Label(selectedMetadata == nil ? "Find Cover & Details" : "Change Cover & Details", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .bookLoomActionWidth(minWidth: 190)
                    .disabled(title.trimmed.isEmpty)

                    Button {
                        save()
                    } label: {
                        Label("Save to Shelf", systemImage: "books.vertical.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .bookLoomActionWidth(minWidth: 190)
                    .disabled(title.trimmed.isEmpty)
                }
                .textFieldStyle(.roundedBorder)
                .padding(18)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .bookLoomScreenBackground()
            .navigationTitle("New Shelf Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingMetadataSearch) {
                BookMetadataSearchView(title: title, author: author) { candidate in
                    apply(candidate)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 560)
    }

    private func apply(_ candidate: BookMetadataCandidate) {
        title = candidate.title
        author = candidate.authorLine
        if let candidateISBN = candidate.isbn {
            isbn = candidateISBN
        }
        selectedMetadata = candidate
    }

    private func save() {
        let book = LibraryBook(
            title: title.trimmed,
            author: author.trimmed,
            isbn: isbn.trimmed,
            bookDescription: selectedMetadata?.description ?? "",
            publishedYear: selectedMetadata?.publishedYear,
            coverURL: selectedMetadata?.coverURL?.absoluteString ?? "",
            externalProvider: selectedMetadata?.provider.rawValue ?? "",
            externalID: selectedMetadata?.externalID ?? "",
            sourceURLString: selectedMetadata?.sourceURL?.absoluteString ?? ""
        )
        book.format = format
        book.isSigned = isSigned
        book.shelfLocation = shelfLocation.trimmed
        if let cents = parsedPriceCents {
            book.purchasePriceCents = cents
        }
        onSave(book)
        dismiss()
    }

    private var parsedPriceCents: Int? {
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

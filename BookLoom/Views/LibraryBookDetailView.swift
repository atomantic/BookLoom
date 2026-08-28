#if os(macOS)
import SwiftUI
import SwiftData

struct LibraryBookDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var book: LibraryBook
    let onDelete: () -> Void

    @State private var priceText: String
    @State private var showingMetadataSearch = false
    @State private var showingCoverZoom = false
    @State private var mutationError: LibraryMutationError?

    private var editor: LibraryBookEditor { LibraryBookEditor(book) }

    init(book: LibraryBook, onDelete: @escaping () -> Void) {
        self.book = book
        self.onDelete = onDelete
        _priceText = State(initialValue: LibraryBookEditor.priceText(for: book))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LibraryBookHero(
                    book: book,
                    onFindMetadata: { showingMetadataSearch = true },
                    onViewCover: { showingCoverZoom = true },
                    onDelete: onDelete,
                    onCoverChange: applyCoverChange
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
        .sheet(isPresented: $showingCoverZoom) {
            BookCoverZoomView(
                title: book.displayTitle,
                author: book.displayAuthor,
                coverURL: book.coverImageURL
            ) {
                showingCoverZoom = false
            }
        }
        .alert("Shelf Change Failed", isPresented: .presence(of: $mutationError)) {
            Button("OK") { mutationError = nil }
        } message: {
            Text(mutationError?.localizedDescription ?? "The book couldn't be saved.")
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Book")
            TextField("Title", text: $book.title)
            TextField("Author", text: $book.author)
            TextField("ISBN", text: $book.isbn)
            Picker("Format", selection: editor.format) {
                ForEach(LibraryBookFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            Picker("Condition", selection: editor.condition) {
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
                StarRatingPicker(stars: editor.rating)
            }
            propertyButtonGrid
            TextField(
                "Paid",
                text: $priceText,
                prompt: Text(CurrencyTextCodec.editableText(for: 0))
            )
            TextField("Purchased from", text: $book.purchaseSource)
            Button {
                clearPrice()
            } label: {
                Label("Clear Price", systemImage: "xmark.circle")
            }
            .buttonStyle(BookLoomSecondaryButtonStyle())
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
            .buttonStyle(BookLoomSecondaryButtonStyle())
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
                isOn: editor.owned
            )
            AddBookPropertyButton(
                title: "Wishlist",
                systemImage: "star.fill",
                tint: BookLoomStyle.gold,
                isOn: editor.wishlist
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
                isOn: editor.audiobook
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
                isOn: editor.loan
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
            .buttonStyle(BookLoomSecondaryButtonStyle())
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

    private func apply(_ candidate: BookMetadataCandidate) {
        book.applyMetadata(candidate)
        saveChanges()
    }

    private func applyCoverChange(_ newCoverURL: String) {
        book.coverURL = newCoverURL
        saveChanges()
    }

    private func saveChanges() {
        editor.applyPrice(from: priceText)
        book.updatedAt = .now
        do {
            try LibraryMutationService.savePersonalLibraryChanges(context: context)
        } catch {
            mutationError = error as? LibraryMutationError
                ?? LibraryMutationError(operation: "save this book", underlying: error)
            priceText = LibraryBookEditor.priceText(for: book)
        }
    }

    private func clearPrice() {
        priceText = ""
        book.purchasePriceCents = nil
        saveChanges()
    }

    private func markReturned() {
        editor.clearLoan()
        saveChanges()
    }

    private func clearGiftPlan() {
        editor.clearGiftPlan()
        saveChanges()
    }
}

private struct LibraryBookHero: View {
    @Bindable var book: LibraryBook
    let onFindMetadata: () -> Void
    let onViewCover: () -> Void
    let onDelete: () -> Void
    let onCoverChange: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Button(action: onViewCover) {
                BookCoverTile(
                    title: book.displayTitle,
                    author: book.displayAuthor,
                    coverURL: book.coverImageURL,
                    width: 128,
                    height: 184
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View larger cover for \(book.displayTitle)")
            .accessibilityHint("Opens an enlarged book cover")

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

                // These three actions don't truncate, so a single HStack imposes
                // a hard ~570pt minimum on the whole detail pane — enough that,
                // with the sidebar and nav rail, the content can't fit a narrow
                // window and clips. Fall back to a vertical stack when the row
                // won't fit so the detail can shrink with the window.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        heroActions
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        heroActions
                    }
                }
            }
        }
        .bookLoomCard(padding: 16)
        // The .largeTitle hero title can fill the entire macOS detail pane at
        // the highest system text sizes; cap it while still honoring AX tiers.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder private var heroActions: some View {
        Button(action: onFindMetadata) {
            Label("Search for Cover and Details", systemImage: "magnifyingglass")
        }
        .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.indigo))

        if book.isAccelerando {
            AccelerandoReaderAction(book: book)
        }

        ManualCoverPicker(
            identifier: book.libraryID,
            currentCoverURL: book.coverURL,
            onCoverChange: onCoverChange
        )

        Button(role: .destructive, action: onDelete) {
            Label("Delete from Shelf", systemImage: "trash")
        }
        .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.coral))
    }
}

struct LibraryBadgeLine: View {
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

struct LibraryBookEmptyState: View {
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

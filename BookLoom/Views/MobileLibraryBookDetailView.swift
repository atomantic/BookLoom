#if os(iOS)
import SwiftUI

/// Outcome of attempting to add a shelf book to the active club's proposals.
/// Shared by `LibraryTabView` (which performs the add) and
/// `MobileLibraryBookDetailView` (which surfaces the result in an alert).
enum ShelfClubAddOutcome: Equatable {
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

extension BookClub {
    func containsLibraryBook(_ book: LibraryBook) -> Bool {
        (submissions ?? []).contains { $0.matchesLibraryBook(book) }
    }
}

extension BookSubmission {
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

extension LibraryBookFormat {
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

struct MobileLibraryBookDetailView: View {
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

    private var editor: LibraryBookEditor { LibraryBookEditor(book) }

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
        _priceText = State(initialValue: LibraryBookEditor.priceText(for: book))
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
        VStack(alignment: .leading, spacing: 12) {
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

            ManualCoverPicker(
                identifier: book.libraryID,
                currentCoverURL: book.coverURL,
                onCoverChange: applyCoverChange
            )
        }
        .bookLoomCard(padding: 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyCoverChange(_ newCoverURL: String) {
        book.coverURL = newCoverURL
        book.updatedAt = .now
        onSave()
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
                        editor.format.wrappedValue = format
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
                        editor.condition.wrappedValue = condition
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
                StarRatingPicker(stars: editor.rating)
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
                editor.applyPrice(from: priceText)
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

    private func apply(_ candidate: BookMetadataCandidate) {
        book.applyMetadata(candidate)
        onSave()
    }

    private func clearPrice() {
        priceText = ""
        book.purchasePriceCents = nil
        book.purchaseSource = ""
        book.updatedAt = .now
        onSave()
    }

    private func markReturned() {
        editor.clearLoan()
        onSave()
    }

    private func clearGiftPlan() {
        editor.clearGiftPlan()
        onSave()
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

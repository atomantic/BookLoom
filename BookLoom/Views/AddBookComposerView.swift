import SwiftUI

enum AddBookComposerAction: Equatable {
    case libraryOnly
    case clubProposed
    case clubCompleted
}

enum AddBookComposerMode: Equatable {
    case library
    case club(name: String)

    var navigationTitle: String {
        switch self {
        case .library: return "New Shelf Book"
        case .club: return "Add Book"
        }
    }

    var heading: String {
        switch self {
        case .library: return "Add to Library"
        case .club: return "Add a Book"
        }
    }

    var subheading: String? {
        switch self {
        case .library:
            return "Track ownership, wishlist, read history, loans, and purchase details."
        case .club(let name):
            return name
        }
    }

    var supportsClubActions: Bool {
        if case .club = self { return true }
        return false
    }
}

struct AddBookDraft {
    var title = ""
    var author = ""
    var isbn = ""
    var selectedMetadata: BookMetadataCandidate?
    var didRead = false
    var didListen = false
    var isOwned = true
    var isWishlist = false
    var format: LibraryBookFormat = .hardcover
    var condition: LibraryBookCondition = .good
    var shelfLocation = ""
    var isSigned = false
    var isOnLoan = false
    var loanedTo = ""
    var personalRatingStars = 0
    var priceText = ""
    var purchaseSource = ""

    var trimmedTitle: String { title.trimmed }

    var priceCents: Int? {
        guard case .cents(let cents) = CurrencyTextCodec.parse(priceText) else { return nil }
        return cents
    }

    mutating func apply(_ candidate: BookMetadataCandidate) {
        title = candidate.title
        author = candidate.authorLine
        if let candidateISBN = candidate.isbn {
            isbn = candidateISBN
        }
        selectedMetadata = candidate
    }

    func makeLibraryBook(now: Date = .now) -> LibraryBook {
        let book = LibraryBook(
            title: title.trimmed,
            author: author.trimmed,
            isbn: selectedMetadata?.primaryISBN.trimmedOrNil ?? isbn.trimmed,
            bookDescription: selectedMetadata?.description ?? "",
            publishedYear: selectedMetadata?.publishedYear,
            coverURL: selectedMetadata?.coverURL?.absoluteString ?? "",
            externalProvider: selectedMetadata?.provider.rawValue ?? "",
            externalID: selectedMetadata?.externalID ?? "",
            sourceURLString: selectedMetadata?.sourceURL?.absoluteString ?? "",
            addedAt: now
        )
        applyLibraryFields(to: book)
        return book
    }

    func applyLibraryFields(to book: LibraryBook, preservingExistingTracking: Bool = false) {
        let existingRead = preservingExistingTracking && book.didRead
        let existingListen = preservingExistingTracking && book.didListenToAudiobook

        book.title = title.trimmed
        book.author = author.trimmed
        book.isbn = selectedMetadata?.primaryISBN.trimmedOrNil ?? isbn.trimmed
        book.bookDescription = selectedMetadata?.description ?? book.bookDescription
        book.publishedYear = selectedMetadata?.publishedYear ?? book.publishedYear
        book.coverURL = selectedMetadata?.coverURL?.absoluteString ?? book.coverURL
        book.externalProvider = selectedMetadata?.provider.rawValue ?? book.externalProvider
        book.externalID = selectedMetadata?.externalID ?? book.externalID
        book.sourceURLString = selectedMetadata?.sourceURL?.absoluteString ?? book.sourceURLString
        book.format = format
        book.condition = condition
        book.shelfLocation = shelfLocation.trimmed
        book.isSigned = isSigned
        book.setOwned(isOwned)
        book.setWishlist(isWishlist)
        book.personalRatingStars = min(max(personalRatingStars, 0), 5)
        book.didRead = existingRead || personalRatingStars > 0 || didRead || didListen
        book.didListenToAudiobook = existingListen || didListen
        book.isOnLoan = isOnLoan && book.countsAsOwned
        if book.isOnLoan {
            book.loanedTo = loanedTo.trimmed
            book.loanedAt = book.loanedAt ?? .now
        } else {
            book.loanedTo = ""
            book.loanedAt = nil
            book.loanDueDate = nil
        }
        book.purchaseSource = purchaseSource.trimmed
        book.purchasePriceCents = priceCents
        book.updatedAt = .now
    }

    func makeSubmission(
        memberID: String,
        memberName: String,
        status: BookSubmissionStatus,
        now: Date = .now
    ) -> BookSubmission {
        let submission = BookSubmission(
            title: title.trimmed,
            author: author.trimmed,
            isbn: selectedMetadata?.primaryISBN.trimmedOrNil ?? isbn.trimmed,
            bookDescription: selectedMetadata?.description ?? "",
            publishedYear: selectedMetadata?.publishedYear,
            coverURL: selectedMetadata?.coverURL?.absoluteString ?? "",
            externalProvider: selectedMetadata?.provider.rawValue ?? "",
            externalID: selectedMetadata?.externalID ?? "",
            submittedBy: memberName,
            submittedByMemberID: memberID,
            submittedAt: now,
            status: status
        )
        if status == .completed {
            submission.completedAt = now
        }
        return submission
    }
}

struct AddBookComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let mode: AddBookComposerMode
    let onCancel: (() -> Void)?
    let onSubmit: (AddBookDraft, AddBookComposerAction) async throws -> Void

    @State private var draft = AddBookDraft()
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showingCopyDetails = false
    @State private var showingPurchaseDetails = false

    init(
        mode: AddBookComposerMode,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (AddBookDraft, AddBookComposerAction) async throws -> Void
    ) {
        self.mode = mode
        self.onCancel = onCancel
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            content
                .bookLoomScreenBackground()
                .navigationTitle(mode.navigationTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { closeComposer() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
        .alert("Couldn't Save Book", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        iOSContent
        #else
        macOSContent
        #endif
    }

    #if os(iOS)
    private var iOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let selectedMetadata = draft.selectedMetadata {
                    BookLoomCompactCard {
                        BookMetadataVerificationPreview(
                            title: draft.title,
                            author: draft.author,
                            candidate: selectedMetadata
                        )
                    }
                }

                bookDetailsCard
                trackingCard
                moreCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .bottom) {
            actionButtons
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(.regularMaterial)
        }
    }

    private var bookDetailsCard: some View {
        BookLoomCompactCard(spacing: 12) {
            BookLoomCompactTextField("Title", text: $draft.title)
            BookLoomCompactDivider()
            BookLoomCompactTextField("Author", text: $draft.author)
            BookLoomCompactDivider()
            ISBNMetadataLookupControls(
                title: $draft.title,
                author: $draft.author,
                isbn: $draft.isbn,
                selectedMetadata: $draft.selectedMetadata,
                layout: .fieldWithScan(placeholder: "ISBN", scanTitle: "Scan")
            )
            iOSLookupActions
                .padding(.top, 2)
        }
    }

    private var trackingCard: some View {
        BookLoomCompactCard(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("Rating")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                Spacer(minLength: 12)
                StarRatingPicker(stars: ratingBinding)
            }
            BookLoomCompactDivider()
            propertyButtonGrid
            if draft.isOnLoan {
                BookLoomCompactDivider()
                BookLoomCompactTextField("Loaned to", text: $draft.loanedTo)
            }
        }
    }

    private var moreCard: some View {
        BookLoomCompactCard(spacing: 0) {
            DisclosureGroup("Copy details", isExpanded: $showingCopyDetails) {
                VStack(spacing: 12) {
                    Picker("Format", selection: $draft.format) {
                        ForEach(LibraryBookFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    Picker("Condition", selection: $draft.condition) {
                        ForEach(LibraryBookCondition.allCases) { condition in
                            Text(condition.displayName).tag(condition)
                        }
                    }
                    BookLoomCompactTextField("Shelf or room", text: $draft.shelfLocation)
                }
                .padding(.top, 12)
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(BookLoomStyle.ink)
            .tint(BookLoomStyle.plum)
            .padding(.vertical, 12)

            BookLoomCompactDivider()

            DisclosureGroup("Purchase", isExpanded: $showingPurchaseDetails) {
                VStack(spacing: 12) {
                    BookLoomCompactTextField(
                        "Paid",
                        text: $draft.priceText,
                        placeholder: CurrencyTextCodec.editableText(for: 0),
                        keyboard: .decimalPad
                    )
                    BookLoomCompactTextField("Purchased from", text: $draft.purchaseSource)
                }
                .padding(.top, 12)
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(BookLoomStyle.ink)
            .tint(BookLoomStyle.plum)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var iOSLookupActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if draft.selectedMetadata == nil {
                GoodreadsMetadataImportControls(
                    title: $draft.title,
                    author: $draft.author,
                    isbn: $draft.isbn,
                    selectedMetadata: $draft.selectedMetadata,
                    importButtonTitle: "Paste Goodreads",
                    importButtonSystemImage: "doc.on.clipboard",
                    fillsAvailableWidth: true
                )
            }

            BookMetadataSearchControls(
                title: $draft.title,
                author: $draft.author,
                isbn: $draft.isbn,
                selectedMetadata: $draft.selectedMetadata,
                showsSummary: false,
                findButtonTitle: "Search for Cover and Details",
                changeButtonTitle: "Search for Cover and Details",
                fillsAvailableWidth: true
            )
        }
        .controlSize(.regular)
    }
    #endif

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
                isOn: $draft.didRead
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
                isOn: $draft.isSigned
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

    #if os(macOS)
    private var macOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                LazyVGrid(columns: macOSComposerColumns, alignment: .leading, spacing: 14) {
                    bookCard
                    importCard
                    ownershipCard
                    copyCard
                    if draft.isOnLoan {
                        loanCard
                    }
                    purchaseCard
                }
                actionButtons
            }
            .textFieldStyle(.roundedBorder)
            .padding(18)
            .frame(maxWidth: 920, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var macOSComposerColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 300, maximum: 440), spacing: 14, alignment: .top)
        ]
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCoverTile(
                title: draft.title,
                author: draft.author,
                coverURL: draft.selectedMetadata?.coverURL,
                width: 82,
                height: 118
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(mode.heading)
                    .font(.title2.bold())
                    .foregroundStyle(BookLoomStyle.ink)
                if let subheading = mode.subheading {
                    Text(subheading)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 12)
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Import")
            GoodreadsMetadataImportControls(
                title: $draft.title,
                author: $draft.author,
                isbn: $draft.isbn,
                selectedMetadata: $draft.selectedMetadata,
                importButtonTitle: "Paste Goodreads URL",
                importButtonSystemImage: "doc.on.clipboard"
            )
        }
        .bookLoomCard(padding: 12)
    }

    private var bookCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Book")
            TextField("Title", text: $draft.title)
            TextField("Author", text: $draft.author)
            TextField("ISBN", text: $draft.isbn)
            BookMetadataSearchControls(
                title: $draft.title,
                author: $draft.author,
                isbn: $draft.isbn,
                selectedMetadata: $draft.selectedMetadata
            )
        }
        .bookLoomCard(padding: 12)
    }

    private var ownershipCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Personal Tracking")
            HStack {
                Text("Rating")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 12)
                StarRatingPicker(stars: ratingBinding)
            }
            propertyButtonGrid
        }
        .bookLoomCard(padding: 12)
    }

    private var copyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Copy Details")
            Picker("Format", selection: $draft.format) {
                ForEach(LibraryBookFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            Picker("Condition", selection: $draft.condition) {
                ForEach(LibraryBookCondition.allCases) { condition in
                    Text(condition.displayName).tag(condition)
                }
            }
            TextField("Shelf or room", text: $draft.shelfLocation)
        }
        .bookLoomCard(padding: 12)
    }

    private var loanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Loan")
            TextField("Loaned to", text: $draft.loanedTo)
        }
        .bookLoomCard(padding: 12)
    }

    private var purchaseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Purchase")
            TextField(
                "Paid",
                text: $draft.priceText,
                prompt: Text(CurrencyTextCodec.editableText(for: 0))
            )
            TextField("Purchased from", text: $draft.purchaseSource)
        }
        .bookLoomCard(padding: 12)
    }
    #endif

    @ViewBuilder
    private var actionButtons: some View {
        let disabled = draft.trimmedTitle.isEmpty || isSaving
        VStack(alignment: .leading, spacing: 10) {
            Button {
                submit(.libraryOnly)
            } label: {
                Label(isSaving ? "Saving..." : "Save to Library", systemImage: "books.vertical.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookLoomProminentButtonStyle())
            .disabled(disabled)

            if mode.supportsClubActions {
                Button {
                    submit(.clubProposed)
                } label: {
                    Label(isSaving ? "Saving..." : "Save to Library + Propose to Club", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.indigo))
                .disabled(disabled)

                Button {
                    submit(.clubCompleted)
                } label: {
                    Label(isSaving ? "Saving..." : "Save to Library + Mark Completed in Club", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.sage))
                .disabled(disabled)
            }
        }
        #if os(macOS)
        .bookLoomCard(padding: 12)
        #endif
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { isPresented in
                if !isPresented {
                    saveError = nil
                }
            }
        )
    }

    private var ownedBinding: Binding<Bool> {
        Binding(
            get: { draft.isOwned },
            set: {
                draft.isOwned = $0
                if $0 {
                    draft.isWishlist = false
                } else {
                    draft.isOnLoan = false
                    draft.loanedTo = ""
                }
            }
        )
    }

    private var wishlistBinding: Binding<Bool> {
        Binding(
            get: { draft.isWishlist },
            set: {
                draft.isWishlist = $0
                if $0 {
                    draft.isOwned = false
                    draft.isOnLoan = false
                    draft.loanedTo = ""
                }
            }
        )
    }

    private var audiobookBinding: Binding<Bool> {
        Binding(
            get: { draft.didListen },
            set: {
                draft.didListen = $0
                if $0 {
                    draft.didRead = true
                }
            }
        )
    }

    private var loanBinding: Binding<Bool> {
        Binding(
            get: { draft.isOnLoan && draft.isOwned },
            set: {
                draft.isOnLoan = $0
                if $0 {
                    draft.isOwned = true
                    draft.isWishlist = false
                } else {
                    draft.loanedTo = ""
                }
            }
        )
    }

    private var ratingBinding: Binding<Int> {
        Binding(
            get: { draft.personalRatingStars },
            set: {
                draft.personalRatingStars = min(max($0, 0), 5)
                if draft.personalRatingStars > 0 {
                    draft.didRead = true
                }
            }
        )
    }

    private func submit(_ action: AddBookComposerAction) {
        guard !draft.trimmedTitle.isEmpty, !isSaving else { return }
        isSaving = true
        saveError = nil
        Task {
            do {
                try await onSubmit(draft, action)
                await MainActor.run {
                    isSaving = false
                    closeComposer()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }

    private func closeComposer() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }
}

struct AddBookPropertyButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var isOn: Bool

    let title: String
    let systemImage: String
    let tint: Color

    init(title: String, systemImage: String, tint: Color, isOn: Binding<Bool>) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self._isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isOn ? "checkmark.circle.fill" : systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.prefersExpandedControlLayout ? 2 : 1)
                    .minimumScaleFactor(dynamicTypeSize.prefersExpandedControlLayout ? 0.9 : 0.82)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isOn ? tint : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isOn ? tint.opacity(0.55) : Color.secondary.opacity(0.22), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
    }

    private var background: some ShapeStyle {
        isOn ? tint.opacity(0.16) : Color.secondary.opacity(0.08)
    }
}

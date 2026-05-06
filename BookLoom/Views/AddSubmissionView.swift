import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AddSubmissionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(GoodreadsImportInbox.self) private var goodreadsInbox

    @Bindable var club: BookClub
    @Query(sort: \LibraryBook.updatedAt, order: .reverse) private var libraryBooks: [LibraryBook]

    @State private var title: String = ""
    @State private var author: String = ""
    @State private var isbn: String = ""
    @State private var selectedMetadata: BookMetadataCandidate?
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var saveCopyToLibrary = false
    @State private var markLibraryCopyRead = false
    @State private var markLibraryCopyListened = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    BookCoverTile(
                        title: title,
                        author: author,
                        coverURL: selectedMetadata?.coverURL,
                        width: 64,
                        height: 88
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add a Book")
                            .font(.title3.bold())
                            .foregroundStyle(BookLoomStyle.ink)
                        Text(club.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .bookLoomCard(padding: 12)
                .frame(maxWidth: 500)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Import from Goodreads", systemImage: "link")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BookLoomStyle.ink)

                    GoodreadsMetadataImportControls(
                        title: $title,
                        author: $author,
                        isbn: $isbn,
                        selectedMetadata: $selectedMetadata,
                        importButtonTitle: "Import",
                        importButtonSystemImage: "square.and.arrow.down",
                        buttonStyle: .secondaryIndigo
                    )
                    .textFieldStyle(.roundedBorder)
                }
                .bookLoomCard(padding: 12)
                .frame(maxWidth: 500)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Title", text: $title)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif

                    TextField("Author", text: $author)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif

                    #if os(iOS)
                    ISBNMetadataLookupControls(
                        title: $title,
                        author: $author,
                        isbn: $isbn,
                        selectedMetadata: $selectedMetadata,
                        layout: .fieldWithScan(placeholder: "ISBN (optional)", scanTitle: "Scan")
                    )
                    #else
                    TextField("ISBN (optional)", text: $isbn)
                    #endif

                    BookMetadataSearchControls(
                        title: $title,
                        author: $author,
                        isbn: $isbn,
                        selectedMetadata: $selectedMetadata,
                        buttonStyle: .secondaryIndigo
                    )

                    Toggle(isOn: $saveCopyToLibrary) {
                        Label("Keep on my Shelf", systemImage: "books.vertical.fill")
                    }

                    if saveCopyToLibrary {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("I read this", isOn: $markLibraryCopyRead)
                            Toggle("I listened to the audiobook", isOn: $markLibraryCopyListened)
                        }
                        .font(.subheadline)
                        .padding(10)
                        .background(BookLoomStyle.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Button {
                        Task { await addSubmission(asRead: false) }
                    } label: {
                        Label(isSaving ? "Adding..." : "Add to Proposals", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .bookLoomActionWidth()
                    .disabled(trimmedTitle.isEmpty || isSaving)

                    Button {
                        Task { await addSubmission(asRead: true) }
                    } label: {
                        Label(isSaving ? "Saving..." : "Save to Completed", systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.sage))
                    .disabled(trimmedTitle.isEmpty || isSaving)

                    Button {
                        saveToShelf()
                    } label: {
                        Label(isSaving ? "Saving..." : "Save to Shelf", systemImage: "tray.and.arrow.down.fill")
                    }
                    .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.plum))
                    .disabled(trimmedTitle.isEmpty || isSaving)
                }
                .textFieldStyle(.roundedBorder)
                .bookLoomCard(padding: 12)
                .frame(maxWidth: 500)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .bookLoomScreenBackground()
        .navigationTitle("Add Book")
        .bookLoomNavigationBar()
        .alert("Couldn't Add Book", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    private var trimmedTitle: String { title.trimmed }

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

    private func addSubmission(asRead: Bool) async {
        guard let title = title.trimmedOrNil else { return }
        isSaving = true
        defer { isSaving = false }

        let now = Date.now
        let submission = BookSubmission(
            title: title,
            author: author.trimmed,
            isbn: isbn.trimmed,
            bookDescription: selectedMetadata?.description ?? "",
            publishedYear: selectedMetadata?.publishedYear,
            coverURL: selectedMetadata?.coverURL?.absoluteString ?? "",
            externalProvider: selectedMetadata?.provider.rawValue ?? "",
            externalID: selectedMetadata?.externalID ?? "",
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
        if saveCopyToLibrary {
            saveLibraryCopy(from: submission, asRead: asRead)
        }
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func saveLibraryCopy(from submission: BookSubmission, asRead: Bool) {
        if let existing = libraryBooks.first(where: { $0.matchesSubmission(submission) }) {
            existing.didRead = existing.didRead || asRead || markLibraryCopyRead
            existing.didListenToAudiobook = existing.didListenToAudiobook || markLibraryCopyListened
            existing.updatedAt = .now
            return
        }

        let book = LibraryBook.fromSubmission(submission)
        book.didRead = asRead || markLibraryCopyRead
        book.didListenToAudiobook = markLibraryCopyListened
        context.insert(book)
    }

    private func saveToShelf() {
        guard let title = title.trimmedOrNil else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let now = Date.now
        let url = selectedMetadata?.sourceURL ?? URL(string: "bookloom://shelf/\(UUID().uuidString)")!
        let enqueueDate = now.addingTimeInterval(-GoodreadsImportInbox.autoPresentMaxAge - 1)
        SharedImportInbox.enqueue(url, now: enqueueDate)
        SharedImportInbox.update(url, now: now) { entry in
            entry.title = title
            entry.author = author.trimmedOrNil
            entry.coverURLString = selectedMetadata?.coverURL?.absoluteString
            entry.bookDescription = selectedMetadata?.description
            entry.publishedYear = selectedMetadata?.publishedYear
            entry.isbn = selectedMetadata?.primaryISBN.trimmedOrNil ?? isbn.trimmedOrNil
            entry.externalProvider = selectedMetadata?.provider.rawValue
            entry.externalID = selectedMetadata?.externalID ?? url.lastPathComponent
            entry.metadataFetchedAt = now
        }
        goodreadsInbox.refresh()
        dismiss()
    }

}

enum MetadataLookupButtonStyle {
    case bordered
    case secondaryIndigo
}

struct GoodreadsMetadataImportControls: View {
    @Binding var title: String
    @Binding var author: String
    @Binding var isbn: String
    @Binding var selectedMetadata: BookMetadataCandidate?

    let importButtonTitle: String
    let importButtonSystemImage: String
    let buttonStyle: MetadataLookupButtonStyle

    @State private var goodreadsURL = ""
    @State private var isImporting = false
    @State private var importError: String?

    private let metadataService = BookMetadataService()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Paste Goodreads share link", text: $goodreadsURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    #endif

                Button {
                    pasteGoodreadsURL()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityLabel("Paste Goodreads link from clipboard")
            }

            importButton

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(BookLoomStyle.coral)
            }
        }
    }

    @ViewBuilder
    private var importButton: some View {
        let button = Button {
            Task { await importFromGoodreads() }
        } label: {
            Label(isImporting ? "Importing..." : importButtonTitle, systemImage: importButtonSystemImage)
        }
        .disabled(goodreadsURL.trimmed.isEmpty || isImporting)

        switch buttonStyle {
        case .bordered:
            button.buttonStyle(.bordered)
        case .secondaryIndigo:
            button.buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.indigo))
        }
    }

    private func importFromGoodreads() async {
        let trimmed = goodreadsURL.trimmed
        guard let url = URL(string: trimmed) else {
            importError = BookMetadataError.invalidGoodreadsURL.localizedDescription
            return
        }
        importError = nil
        isImporting = true
        defer { isImporting = false }

        do {
            let candidate = try await metadataService.importFromGoodreads(url: url)
            apply(candidate)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func pasteGoodreadsURL() {
        guard let pasted = Self.clipboardString()?.trimmed, !pasted.isEmpty else { return }
        goodreadsURL = pasted
        importError = nil
        if URL(string: pasted) != nil {
            Task { await importFromGoodreads() }
        }
    }

    private func apply(_ candidate: BookMetadataCandidate) {
        title = candidate.title
        author = candidate.authorLine
        if let candidateISBN = candidate.isbn {
            isbn = candidateISBN
        }
        selectedMetadata = candidate
    }

    private static func clipboardString() -> String? {
        #if os(iOS)
        UIPasteboard.general.string
        #elseif os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        nil
        #endif
    }
}

#if os(iOS)
enum ISBNMetadataLookupLayout {
    case fieldWithScan(placeholder: String, scanTitle: String)
    case scanButtonOnly(title: String)
}

struct ISBNMetadataLookupControls: View {
    @Binding var title: String
    @Binding var author: String
    @Binding var isbn: String
    @Binding var selectedMetadata: BookMetadataCandidate?

    let layout: ISBNMetadataLookupLayout

    @State private var showingScanner = false
    @State private var isLookingUp = false
    @State private var lookupError: String?

    private let metadataService = BookMetadataService()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch layout {
            case .fieldWithScan(let placeholder, let scanTitle):
                HStack(spacing: 8) {
                    isbnField(placeholder: placeholder)

                    scanButton(title: scanTitle)
                }
            case .scanButtonOnly(let title):
                scanButton(title: title)
            }

            if isLookingUp {
                ProgressView("Looking up ISBN...")
                    .font(.caption)
            }

            if let lookupError {
                Text(lookupError)
                    .font(.caption)
                    .foregroundStyle(BookLoomStyle.coral)
            }
        }
        .sheet(isPresented: $showingScanner) {
            ISBNScannerView { scannedISBN in
                showingScanner = false
                Task { await applyScannedISBN(scannedISBN) }
            } onCancel: {
                showingScanner = false
            }
            .ignoresSafeArea()
        }
    }

    private func isbnField(placeholder: String) -> some View {
        TextField(placeholder, text: $isbn)
            .textInputAutocapitalization(.characters)
            .keyboardType(.numbersAndPunctuation)
            .autocorrectionDisabled()
    }

    private func scanButton(title: String) -> some View {
        Button {
            showingScanner = true
        } label: {
            Label(title, systemImage: "barcode.viewfinder")
        }
        .buttonStyle(.bordered)
        .disabled(isLookingUp)
    }

    @MainActor
    private func applyScannedISBN(_ scannedISBN: String) async {
        isbn = scannedISBN
        lookupError = nil
        isLookingUp = true
        defer { isLookingUp = false }

        do {
            let candidate = try await metadataService.lookupISBN(scannedISBN)
            apply(candidate)
        } catch {
            lookupError = error.localizedDescription
        }
    }

    private func apply(_ candidate: BookMetadataCandidate) {
        title = candidate.title
        author = candidate.authorLine
        if let candidateISBN = candidate.isbn {
            isbn = candidateISBN
        }
        selectedMetadata = candidate
    }
}
#endif

struct BookMetadataSearchControls: View {
    @Binding var title: String
    @Binding var author: String
    @Binding var isbn: String
    @Binding var selectedMetadata: BookMetadataCandidate?

    let buttonStyle: MetadataLookupButtonStyle

    @State private var showingMetadataSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchButton

            if let selectedMetadata {
                BookMetadataSummary(candidate: selectedMetadata)
            }
        }
        .sheet(isPresented: $showingMetadataSearch) {
            BookMetadataSearchView(title: title, author: author) { candidate in
                apply(candidate)
            }
        }
    }

    @ViewBuilder
    private var searchButton: some View {
        let button = Button {
            showingMetadataSearch = true
        } label: {
            Label(selectedMetadata == nil ? "Find Cover & Details" : "Change Cover & Details", systemImage: "magnifyingglass")
        }
        .disabled(title.trimmed.isEmpty)

        switch buttonStyle {
        case .bordered:
            button.buttonStyle(.bordered)
        case .secondaryIndigo:
            button.buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.indigo))
        }
    }

    private func apply(_ candidate: BookMetadataCandidate) {
        title = candidate.title
        author = candidate.authorLine
        if let candidateISBN = candidate.isbn {
            isbn = candidateISBN
        }
        selectedMetadata = candidate
    }
}

struct BookMetadataSummary: View {
    let candidate: BookMetadataCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Matched with \(candidate.provider.displayName)", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BookLoomStyle.sage)

            if let year = candidate.publishedYear {
                Text("First published \(String(year))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let description = candidate.description?.trimmedOrNil {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(BookLoomStyle.sage.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

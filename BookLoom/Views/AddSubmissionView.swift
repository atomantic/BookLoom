import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AddSubmissionView: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity

    @Bindable var club: BookClub
    @Query(sort: \LibraryBook.updatedAt, order: .reverse) private var libraryBooks: [LibraryBook]

    var body: some View {
        AddBookComposerView(mode: .club(name: club.name)) { draft, action in
            try save(draft, action: action)
        }
    }

    private func save(_ draft: AddBookDraft, action: AddBookComposerAction) throws {
        _ = upsertLibraryBook(from: draft)

        switch action {
        case .libraryOnly:
            try context.save()
        case .clubProposed, .clubCompleted:
            let status: BookSubmissionStatus = action == .clubCompleted ? .completed : .proposed
            let submission = draft.makeSubmission(
                memberID: memberIdentity.memberID,
                memberName: memberIdentity.name,
                status: status
            )
            club.addSubmission(submission)
            context.insert(submission)
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
        }
    }

    private func upsertLibraryBook(from draft: AddBookDraft) -> LibraryBook {
        if let existing = existingLibraryBook(for: draft) {
            draft.applyLibraryFields(to: existing, preservingExistingTracking: true)
            return existing
        }

        let book = draft.makeLibraryBook()
        context.insert(book)
        return book
    }

    private func existingLibraryBook(for draft: AddBookDraft) -> LibraryBook? {
        if let provider = draft.selectedMetadata?.provider.rawValue.trimmedOrNil,
           let externalID = draft.selectedMetadata?.externalID.trimmedOrNil,
           let match = libraryBooks.first(where: { $0.externalProvider == provider && $0.externalID == externalID }) {
            return match
        }

        let isbn = draft.selectedMetadata?.primaryISBN.trimmedOrNil ?? draft.isbn.trimmedOrNil
        if let isbn, let match = libraryBooks.first(where: { $0.isbn == isbn }) {
            return match
        }

        let title = draft.title.trimmed.lowercased()
        let author = draft.author.trimmed.lowercased()
        guard !title.isEmpty else { return nil }
        return libraryBooks.first {
            $0.displayTitle.lowercased() == title && $0.displayAuthor.lowercased() == author
        }
    }
}

/// Shared target for the three metadata import controls. Bundles the four
/// fields a candidate writes back into so the apply logic lives in one place.
struct BookMetadataSelection {
    @Binding var title: String
    @Binding var author: String
    @Binding var isbn: String
    @Binding var selectedMetadata: BookMetadataCandidate?

    func apply(_ candidate: BookMetadataCandidate) {
        title = candidate.title
        author = candidate.authorLine
        if let candidateISBN = candidate.isbn {
            isbn = candidateISBN
        }
        selectedMetadata = candidate
    }
}

struct GoodreadsMetadataImportControls: View {
    @Binding var title: String
    @Binding var author: String
    @Binding var isbn: String
    @Binding var selectedMetadata: BookMetadataCandidate?

    let importButtonTitle: String
    let importButtonSystemImage: String
    var tint = BookLoomStyle.plum
    var fillsAvailableWidth = false

    @State private var isImporting = false
    @State private var importError: String?

    private let metadataService = BookMetadataService()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            pasteButton

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(BookLoomStyle.coral)
            }
        }
    }

    @ViewBuilder
    private var pasteButton: some View {
        Button {
            pasteAndImport()
        } label: {
            Label(isImporting ? "Importing..." : importButtonTitle, systemImage: importButtonSystemImage)
                .symbolRenderingMode(.monochrome)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
        }
        .disabled(isImporting)
        .accessibilityLabel("Paste Goodreads link from clipboard and import")
        .buttonStyle(BookLoomSecondaryButtonStyle(tint: tint))
    }

    private func pasteAndImport() {
        guard let pasted = Self.clipboardString()?.trimmed, !pasted.isEmpty else {
            importError = "No link on the clipboard. Copy a Goodreads share link first."
            return
        }
        guard let url = URL(string: pasted) else {
            importError = BookMetadataError.invalidGoodreadsURL.localizedDescription
            return
        }
        importError = nil
        Task { await importFromGoodreads(url: url) }
    }

    private func importFromGoodreads(url: URL) async {
        isImporting = true
        defer { isImporting = false }

        do {
            let candidate = try await metadataService.importFromGoodreads(url: url)
            selection.apply(candidate)
        } catch {
            importError = error.localizedDescription
        }
    }

    private var selection: BookMetadataSelection {
        BookMetadataSelection(title: $title, author: $author, isbn: $isbn, selectedMetadata: $selectedMetadata)
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
    var fillsAvailableWidth = false

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
            .font(.body)
            .foregroundStyle(BookLoomStyle.ink)
            .textInputAutocapitalization(.characters)
            .keyboardType(.numbersAndPunctuation)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            }
    }

    private func scanButton(title: String) -> some View {
        Button {
            showingScanner = true
        } label: {
            Label(title, systemImage: "barcode.viewfinder")
                .symbolRenderingMode(.monochrome)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
        }
        .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.plum))
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
            selection.apply(candidate)
        } catch {
            lookupError = error.localizedDescription
        }
    }

    private var selection: BookMetadataSelection {
        BookMetadataSelection(title: $title, author: $author, isbn: $isbn, selectedMetadata: $selectedMetadata)
    }
}
#endif

struct BookMetadataSearchControls: View {
    @Binding var title: String
    @Binding var author: String
    @Binding var isbn: String
    @Binding var selectedMetadata: BookMetadataCandidate?

    var tint = BookLoomStyle.indigo
    var showsSummary = true
    var findButtonTitle = "Search for Cover and Details"
    var changeButtonTitle = "Search for Cover and Details"
    var fillsAvailableWidth = false

    @State private var showingMetadataSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchButton

            if showsSummary, let selectedMetadata {
                BookMetadataSummary(candidate: selectedMetadata)
            }
        }
        .sheet(isPresented: $showingMetadataSearch) {
            BookMetadataSearchView(title: title, author: author, isbn: isbn) { candidate in
                selection.apply(candidate)
            }
        }
    }

    @ViewBuilder
    private var searchButton: some View {
        Button {
            showingMetadataSearch = true
        } label: {
            Label(selectedMetadata == nil ? findButtonTitle : changeButtonTitle, systemImage: "magnifyingglass")
                .symbolRenderingMode(.monochrome)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
        }
        .disabled(title.trimmed.isEmpty)
        .buttonStyle(BookLoomSecondaryButtonStyle(tint: tint))
    }

    private var selection: BookMetadataSelection {
        BookMetadataSelection(title: $title, author: $author, isbn: $isbn, selectedMetadata: $selectedMetadata)
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

struct BookMetadataVerificationPreview: View {
    let title: String
    let author: String
    let candidate: BookMetadataCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCoverTile(
                title: displayTitle,
                author: displayAuthor,
                coverURL: candidate.coverURL,
                width: 92,
                height: 136
            )
            .accessibilityLabel("Matched cover for \(displayTitle)")

            VStack(alignment: .leading, spacing: 8) {
                Text(displayTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(3)

                if !displayAuthor.isEmpty {
                    Text(displayAuthor)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                BookMetadataSummary(candidate: candidate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private var displayTitle: String {
        title.trimmedOrNil ?? candidate.title
    }

    private var displayAuthor: String {
        author.trimmedOrNil ?? candidate.authorLine
    }
}

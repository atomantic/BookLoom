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

    @Bindable var club: BookClub

    @State private var title: String = ""
    @State private var author: String = ""
    @State private var isbn: String = ""
    @State private var selectedMetadata: BookMetadataCandidate?
    @State private var showingMetadataSearch = false
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var goodreadsURL: String = ""
    @State private var isImportingGoodreads = false
    @State private var goodreadsError: String?

    private let metadataService = BookMetadataService()

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

                    HStack(spacing: 8) {
                        TextField("Paste Goodreads share link", text: $goodreadsURL, prompt: Text("Paste Goodreads share link").foregroundStyle(.tertiary))
                            .textFieldStyle(.roundedBorder)
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

                    Button {
                        Task { await importFromGoodreads() }
                    } label: {
                        Label(isImportingGoodreads ? "Importing..." : "Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.indigo))
                    .disabled(goodreadsURL.trimmed.isEmpty || isImportingGoodreads)

                    if let goodreadsError {
                        Text(goodreadsError)
                            .font(.caption)
                            .foregroundStyle(BookLoomStyle.coral)
                    }
                }
                .bookLoomCard(padding: 12)
                .frame(maxWidth: 500)

                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        TextField("Title", text: $title)
                        TextField("Author", text: $author)
                        TextField("ISBN (optional)", text: $isbn)
                    }
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif

                    Button {
                        showingMetadataSearch = true
                    } label: {
                        Label(selectedMetadata == nil ? "Find Cover & Details" : "Change Cover & Details", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.indigo))
                    .disabled(trimmedTitle.isEmpty)

                    if let selectedMetadata {
                        BookMetadataSummary(candidate: selectedMetadata)
                    }

                    Button {
                        Task { await addSubmission(asRead: false) }
                    } label: {
                        Label(isSaving ? "Adding..." : "Add to Proposals", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(trimmedTitle.isEmpty || isSaving)

                    Button {
                        Task { await addSubmission(asRead: true) }
                    } label: {
                        Label(isSaving ? "Saving..." : "Save to Completed", systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.sage))
                    .disabled(trimmedTitle.isEmpty || isSaving)
                }
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
        .sheet(isPresented: $showingMetadataSearch) {
            BookMetadataSearchView(title: title, author: author) { candidate in
                apply(candidate)
            }
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

    private func apply(_ candidate: BookMetadataCandidate) {
        title = candidate.title
        author = candidate.authorLine
        if let isbn = candidate.isbn {
            self.isbn = isbn
        }
        selectedMetadata = candidate
    }

    private func importFromGoodreads() async {
        let trimmed = goodreadsURL.trimmed
        guard let url = URL(string: trimmed) else {
            goodreadsError = BookMetadataError.invalidGoodreadsURL.localizedDescription
            return
        }
        goodreadsError = nil
        isImportingGoodreads = true
        defer { isImportingGoodreads = false }

        do {
            let candidate = try await metadataService.importFromGoodreads(url: url)
            apply(candidate)
        } catch {
            goodreadsError = error.localizedDescription
        }
    }

    private func pasteGoodreadsURL() {
        guard let pasted = Self.clipboardString()?.trimmed, !pasted.isEmpty else { return }
        goodreadsURL = pasted
        goodreadsError = nil
        if URL(string: pasted) != nil {
            Task { await importFromGoodreads() }
        }
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

private struct BookMetadataSummary: View {
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

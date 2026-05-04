import SwiftUI
import SwiftData

/// Sheet shown after the user shares a Goodreads link to BookLoom (via the
/// Share Extension or `bookloom://import?url=...`). Fetches metadata, lets
/// the user pick a club, and adds the book to proposals or marks it read.
struct GoodreadsImportSheet: View {
    let goodreadsURL: URL
    let clubs: [BookClub]
    let initiallyActiveClub: BookClub?
    /// Called when the sheet is finishing. `saved` is `true` when the user
    /// successfully added the book to a club, `false` when they cancelled.
    /// Cancelled URLs stay in `SharedImportInbox` so the user can come back
    /// to them from the visible Import Inbox banner instead of losing the
    /// share entirely.
    var onDismiss: (Bool) -> Void

    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity

    @State private var candidate: BookMetadataCandidate?
    @State private var fetchError: String?
    @State private var isFetching = true
    @State private var isSaving = false
    @State private var selectedClubID: PersistentIdentifier?

    private let metadataService = BookMetadataService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header

                    if isFetching {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Fetching from Goodreads…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                    } else if let candidate {
                        BookCard(candidate: candidate)
                    } else if let fetchError {
                        Label(fetchError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(BookLoomStyle.coral)
                            .padding(.vertical, 12)
                    }

                    if !clubs.isEmpty {
                        clubPicker
                    } else {
                        Label("Create a book club before importing.", systemImage: "person.3")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }

                    actionButtons
                }
                .padding(16)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .bookLoomScreenBackground()
            .navigationTitle("Add from Goodreads")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss(false) }
                }
            }
        }
        .task { await loadMetadata() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.title2)
                .foregroundStyle(BookLoomStyle.plum)
            VStack(alignment: .leading, spacing: 2) {
                Text("Imported from Goodreads")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                Text(goodreadsURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 12)
    }

    private var clubPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add to club")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BookLoomStyle.ink)
            Picker("Club", selection: Binding(
                get: { selectedClubID ?? clubs.first?.persistentModelID },
                set: { selectedClubID = $0 }
            )) {
                ForEach(clubs, id: \.persistentModelID) { club in
                    Text(club.name).tag(Optional(club.persistentModelID))
                }
            }
            #if os(iOS)
            .pickerStyle(.menu)
            #endif
        }
        .bookLoomCard(padding: 12)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await save(asRead: false) }
            } label: {
                Label(isSaving ? "Adding…" : "Add to Proposals", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(saveDisabled)

            Button {
                Task { await save(asRead: true) }
            } label: {
                Label(isSaving ? "Saving…" : "Save to Read", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(saveDisabled)
        }
    }

    private var saveDisabled: Bool {
        candidate == nil || clubs.isEmpty || isSaving || isFetching
    }

    private var resolvedClub: BookClub? {
        if let selectedClubID, let match = clubs.first(where: { $0.persistentModelID == selectedClubID }) {
            return match
        }
        return initiallyActiveClub ?? clubs.first
    }

    private func loadMetadata() async {
        if selectedClubID == nil {
            selectedClubID = (initiallyActiveClub ?? clubs.first)?.persistentModelID
        }
        isFetching = true
        fetchError = nil
        defer { isFetching = false }

        do {
            candidate = try await metadataService.importFromGoodreads(url: goodreadsURL)
        } catch {
            fetchError = error.localizedDescription
        }
    }

    private func save(asRead: Bool) async {
        guard let candidate, let club = resolvedClub else { return }
        isSaving = true
        defer { isSaving = false }

        let now = Date.now
        let submission = BookSubmission(
            title: candidate.title,
            author: candidate.authorLine,
            isbn: candidate.primaryISBN,
            bookDescription: candidate.description ?? "",
            publishedYear: candidate.publishedYear,
            coverURL: candidate.coverURL?.absoluteString ?? "",
            externalProvider: candidate.provider.rawValue,
            externalID: candidate.externalID,
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
            onDismiss(true)
        } catch {
            fetchError = error.localizedDescription
        }
    }
}

private struct BookCard: View {
    let candidate: BookMetadataCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BookCoverTile(
                title: candidate.title,
                author: candidate.authorLine,
                coverURL: candidate.coverURL,
                width: 64,
                height: 88
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.headline)
                    .foregroundStyle(BookLoomStyle.ink)
                if !candidate.authorLine.isEmpty {
                    Text(candidate.authorLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let year = candidate.publishedYear {
                    Text("First published \(String(year))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let description = candidate.description?.trimmedOrNil {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 12)
    }
}

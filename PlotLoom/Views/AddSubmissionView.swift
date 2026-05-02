import SwiftUI
import SwiftData

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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    BookCoverTile(
                        title: title,
                        author: author,
                        coverURL: selectedMetadata?.coverURL,
                        width: 96,
                        height: 132
                    )
                    Text("Add a Proposal")
                        .font(.title.bold())
                        .foregroundStyle(PlotLoomStyle.ink)
                    Text(club.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 14) {
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
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(trimmedTitle.isEmpty)

                    if let selectedMetadata {
                        BookMetadataSummary(candidate: selectedMetadata)
                    }

                    Button(action: addSubmission) {
                        Label("Add to Proposals", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(trimmedTitle.isEmpty)
                }
                .plotLoomCard(padding: 18)
                .frame(maxWidth: 500)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .plotLoomScreenBackground()
        .navigationTitle("Add Book")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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

    private func addSubmission() {
        guard let title = title.trimmedOrNil else { return }
        let submission = BookSubmission(
            title: title,
            author: author.trimmed,
            isbn: isbn.trimmed,
            bookDescription: selectedMetadata?.description ?? "",
            publishedYear: selectedMetadata?.publishedYear,
            coverURL: selectedMetadata?.coverURL?.absoluteString ?? "",
            externalProvider: selectedMetadata?.provider.rawValue ?? "",
            externalID: selectedMetadata?.externalID ?? "",
            submittedBy: memberIdentity.name
        )
        club.addSubmission(submission)
        context.insert(submission)
        do {
            try context.save()
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
}

private struct BookMetadataSummary: View {
    let candidate: BookMetadataCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Matched with \(candidate.provider.displayName)", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PlotLoomStyle.sage)

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
        .padding(12)
        .background(PlotLoomStyle.sage.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

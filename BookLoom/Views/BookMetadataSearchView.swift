import SwiftUI

struct BookMetadataSearchView: View {
    let title: String
    let author: String
    var isbn: String = ""
    let onSelect: (BookMetadataCandidate) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [BookMetadataCandidate] = []
    @State private var isSearching = true
    @State private var errorMessage: String?

    private let service = BookMetadataService()

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    ProgressView("Finding book details...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 42))
                            .foregroundStyle(BookLoomStyle.coral)
                        Text("Couldn't Search")
                            .font(.title3.bold())
                            .foregroundStyle(BookLoomStyle.ink)
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Button {
                            Task { await search() }
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(BookLoomProminentButtonStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if candidates.isEmpty {
                    InlineEmptyState(
                        systemImage: "magnifyingglass",
                        title: "No Matches",
                        message: "Try adding the author or checking the spelling."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(candidates) { candidate in
                        Button {
                            onSelect(candidate)
                            dismiss()
                        } label: {
                            BookMetadataCandidateRow(candidate: candidate)
                        }
                        .buttonStyle(.plain)
                        .bookLoomListRow()
                    }
                    .bookLoomListStyle()
                    .scrollContentBackground(.hidden)
                }
            }
            .bookLoomScreenBackground()
            .navigationTitle("Choose Match")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await search() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    private func search() async {
        isSearching = true
        errorMessage = nil
        do {
            if title.trimmed.isEmpty, !isbn.trimmed.isEmpty {
                candidates = [try await service.lookupISBN(isbn)]
            } else {
                candidates = try await service.search(title: title, author: author)
            }
        } catch {
            candidates = []
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }
}

private struct BookMetadataCandidateRow: View {
    let candidate: BookMetadataCandidate

    var body: some View {
        HStack(spacing: 12) {
            BookCoverTile(
                title: candidate.title,
                author: candidate.authorLine,
                coverURL: candidate.coverURL,
                width: 50,
                height: 68
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(candidate.title)
                    .font(.headline)
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(2)

                if !candidate.authorLine.isEmpty {
                    Text(candidate.authorLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if let publishedYear = candidate.publishedYear {
                        TintedCapsuleLabel(text: "\(publishedYear)", tint: BookLoomStyle.sage, horizontalPadding: 8, verticalPadding: 4)
                    }
                    TintedCapsuleLabel(text: candidate.provider.displayName, tint: BookLoomStyle.plum, horizontalPadding: 8, verticalPadding: 4)
                }

                if let description = candidate.description?.trimmedOrNil {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .bookLoomCard(padding: 10)
    }
}

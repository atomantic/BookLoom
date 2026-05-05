import SwiftUI

/// Rendered both inside the Club screen Imports bucket (when a club is active) and
/// inside `NoActiveClubView` (when the user shared books before creating a
/// club). Without the second placement, a user who shares from Goodreads before
/// creating their first club sees no queued imports anywhere.
struct ImportInboxBanner: View {
    let pending: [SharedImportInbox.PendingImport]
    let onTap: (URL) -> Void
    let onRemove: (URL) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(pending) { item in
                ImportInboxRow(
                    item: item,
                    onTap: { onTap(item.url) },
                    onRemove: { onRemove(item.url) }
                )
            }
        }
        .bookLoomCard(padding: 10)
    }
}

private struct ImportInboxRow: View {
    let item: SharedImportInbox.PendingImport
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    BookCoverTile(
                        title: item.displayTitle ?? fallbackTitle,
                        author: item.displayAuthor ?? "",
                        coverURL: item.coverURL,
                        width: 36,
                        height: 48
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayTitle ?? fallbackTitle)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(BookLoomStyle.ink)
                            .lineLimit(2)
                        if let author = item.displayAuthor {
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if !item.hasResolvedMetadata {
                            Text("Fetching from Goodreads…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.callout)
                    .foregroundStyle(BookLoomStyle.coral)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove import")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(BookLoomStyle.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// GoodreadsLinkExtractor canonicalizes shared URLs to
    /// `https://www.goodreads.com/book/show/<id>`, so the last path component
    /// is just the numeric ID. Used while metadata prefetch is in flight or
    /// after a fetch failure so the row still has a stable identifier.
    private var fallbackTitle: String {
        let id = item.url.lastPathComponent
        return id.isEmpty ? "Goodreads book" : "Goodreads book #\(id)"
    }
}

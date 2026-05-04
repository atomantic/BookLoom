import SwiftUI

/// Visible surface for `SharedImportInbox` (Goodreads share-extension queue).
///
/// Rendered both inside `BooksTabContent` (when a club is active) and inside
/// `NoActiveClubView` (when the user shared books before creating a club).
/// Without the second placement, a user who shares from Goodreads before
/// creating their first club sees no inbox anywhere — only the share-extension
/// confirmation alert that promised one.
///
/// Tapping a row sets `presentedItem` on the shared `GoodreadsImportInbox`,
/// which `MainTabs` watches via `.sheet(item:)` to open the import flow.
struct ImportInboxBanner: View {
    let pending: [SharedImportInbox.PendingImport]
    let onTap: (URL) -> Void
    let onRemove: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(headline, systemImage: "tray.and.arrow.down.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BookLoomStyle.ink)
            Text("Tap a book to fetch it from Goodreads and add it to a club.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(pending) { item in
                    ImportInboxRow(
                        item: item,
                        onTap: { onTap(item.url) },
                        onRemove: { onRemove(item.url) }
                    )
                }
            }
        }
        .bookLoomCard(padding: 12)
    }

    private var headline: String {
        let count = pending.count
        return count == 1 ? "1 book waiting from Goodreads" : "\(count) books waiting from Goodreads"
    }
}

private struct ImportInboxRow: View {
    let item: SharedImportInbox.PendingImport
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed.fill")
                        .font(.callout)
                        .foregroundStyle(BookLoomStyle.indigo)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(BookLoomStyle.ink)
                            .lineLimit(1)
                        Text(item.url.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 40)
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
            .accessibilityLabel("Remove from import inbox")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(BookLoomStyle.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var label: String {
        // GoodreadsLinkExtractor canonicalizes shared URLs to
        // `https://www.goodreads.com/book/show/<id>` (no slug), so the
        // last path component is just the numeric ID. Real titles arrive
        // when the user opens the row and the metadata fetch resolves.
        let id = item.url.lastPathComponent
        return id.isEmpty ? "Goodreads book" : "Goodreads book #\(id)"
    }
}

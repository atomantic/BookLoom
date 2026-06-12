import Foundation
import SwiftUI

/// Shared edit logic for a single `LibraryBook`, used by both the iOS
/// (`MobileLibraryBookDetailView`) and macOS (`LibraryBookDetailView`) detail
/// screens. Both platforms previously carried byte-identical copies of the
/// seven `Binding` factories, the price parsing/formatting, and the field-clear
/// mutators below.
///
/// This is a value type wrapping the book; it does **not** persist. Each detail
/// view owns its own save semantics (the platforms differ in exactly when they
/// call `context.save()`), so this type only mutates model fields. Callers
/// invoke their own save after a mutator returns.
struct LibraryBookEditor {
    let book: LibraryBook

    init(_ book: LibraryBook) {
        self.book = book
    }

    // MARK: - Binding factories

    var format: Binding<LibraryBookFormat> {
        Binding(
            get: { book.format },
            set: {
                book.format = $0
                book.updatedAt = .now
            }
        )
    }

    var condition: Binding<LibraryBookCondition> {
        Binding(
            get: { book.condition },
            set: {
                book.condition = $0
                book.updatedAt = .now
            }
        )
    }

    var rating: Binding<Int> {
        Binding(
            get: { min(max(book.personalRatingStars, 0), 5) },
            set: { book.setPersonalRatingStars($0) }
        )
    }

    var owned: Binding<Bool> {
        Binding(
            get: { book.countsAsOwned },
            set: { book.setOwned($0) }
        )
    }

    var wishlist: Binding<Bool> {
        Binding(
            get: { book.isWishlist },
            set: { book.setWishlist($0) }
        )
    }

    var audiobook: Binding<Bool> {
        Binding(
            get: { book.didListenToAudiobook },
            set: { book.setAudiobookListened($0) }
        )
    }

    var loan: Binding<Bool> {
        Binding(
            get: { book.isOnLoan && book.countsAsOwned },
            set: {
                book.isOnLoan = $0
                if $0 {
                    book.setOwned(true)
                    if book.loanedAt == nil {
                        book.loanedAt = .now
                    }
                } else {
                    book.loanedTo = ""
                    book.loanedAt = nil
                    book.loanDueDate = nil
                }
                book.updatedAt = .now
            }
        )
    }

    // MARK: - Price helpers

    /// Parses `priceText` into `book.purchasePriceCents`. Leaves the book
    /// unchanged when the text is non-empty but unparseable. Does not save.
    func applyPrice(from priceText: String) {
        let trimmed = priceText.trimmed
        guard !trimmed.isEmpty else {
            book.purchasePriceCents = nil
            return
        }
        let normalized = trimmed
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized) else { return }
        book.purchasePriceCents = Int((value * 100).rounded())
    }

    /// The editable price string for a book, formatted to two decimals.
    static func priceText(for book: LibraryBook) -> String {
        guard let cents = book.purchasePriceCents else { return "" }
        return String(format: "%.2f", Double(cents) / 100)
    }

    // MARK: - Field mutators (no save)

    /// Clears the loan state. Does not save.
    func clearLoan() {
        book.isOnLoan = false
        book.loanedTo = ""
        book.loanedAt = nil
        book.loanDueDate = nil
        book.updatedAt = .now
    }

    /// Clears the gift plan. Does not save.
    func clearGiftPlan() {
        book.intendedRecipient = ""
        book.giftOccasion = ""
        book.giftByDate = nil
        book.updatedAt = .now
    }
}

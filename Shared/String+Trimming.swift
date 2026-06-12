import Foundation

extension String {
    /// Whitespace- and newline-trimmed value.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whitespace-trimmed value, or `nil` if the trim leaves nothing.
    ///
    /// Lives in `Shared/` so the share extension — which can't import the
    /// main app's design system — shares one copy with the app.
    var trimmedOrNil: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

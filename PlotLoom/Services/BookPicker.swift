import Foundation

/// Picks a random proposed submission to become the next "current" read.
/// Pulled out as a free function so it's trivially testable without a ModelContext.
enum BookPicker {
    static func pickNext(from proposed: [BookSubmission]) -> BookSubmission? {
        proposed.filter { $0.status == .proposed }.randomElement()
    }
}

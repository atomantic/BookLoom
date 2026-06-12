import SwiftUI

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedOrNil: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

@MainActor
extension Binding where Value == Bool {
    static func presence<T>(of source: Binding<T?>) -> Binding<Bool> {
        Binding(
            get: { source.wrappedValue != nil },
            set: { if !$0 { source.wrappedValue = nil } }
        )
    }
}

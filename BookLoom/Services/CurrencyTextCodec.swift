import Foundation

enum CurrencyTextParseResult: Equatable {
    case empty
    case cents(Int)
    case invalid
}

/// Converts editable, locale-aware currency text to the app's stored integer-cents
/// representation and formats that representation for library editing and display.
enum CurrencyTextCodec {
    private static let displayFormatters = CurrencyDisplayFormatterStore()

    static func parse(
        _ text: String,
        locale: Locale = .current,
        currencyCode: String? = nil
    ) -> CurrencyTextParseResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let normalized = normalizedNumber(
            from: trimmed,
            locale: locale,
            currencyCode: currencyCode
        ), let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return .invalid
        }

        var cents = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &cents, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber,
              number.compare(NSDecimalNumber(value: Int.min)) != .orderedAscending,
              number.compare(NSDecimalNumber(value: Int.max)) != .orderedDescending else {
            return .invalid
        }
        return .cents(number.intValue)
    }

    /// Formats a price for an editable field without a currency symbol or grouping.
    static func editableText(for cents: Int?, locale: Locale = .current) -> String {
        guard let cents else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: decimalNumber(for: cents))
            ?? String(format: "%.2f", locale: locale, Double(cents) / 100)
    }

    /// Formats a stored price as a localized currency badge.
    static func displayText(
        for cents: Int,
        currencyCode: String,
        locale: Locale = .current
    ) -> String {
        let code = currencyCode.trimmedOrNil ?? "USD"
        return displayFormatters.string(
            from: decimalNumber(for: cents),
            currencyCode: code,
            locale: locale
        )
            ?? editableText(for: cents, locale: locale)
    }

    private static func normalizedNumber(
        from text: String,
        locale: Locale,
        currencyCode: String?
    ) -> String? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        if let currencyCode = currencyCode?.trimmedOrNil {
            formatter.currencyCode = currencyCode
        }

        var value = text
        for token in [formatter.currencySymbol, formatter.currencyCode, currencyCode]
            .compactMap({ $0?.trimmedOrNil })
            .sorted(by: { $0.count > $1.count }) {
            value = value.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        if let minusSign = formatter.minusSign, minusSign != "-" {
            value = value.replacingOccurrences(of: minusSign, with: "-")
        }
        if let plusSign = formatter.plusSign, plusSign != "+" {
            value = value.replacingOccurrences(of: plusSign, with: "+")
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        let decimalSeparator = formatter.decimalSeparator ?? "."
        let groupingSeparator = formatter.groupingSeparator ?? ","
        var numeric = ""
        for character in value {
            if let digit = character.wholeNumberValue {
                numeric.append(String(digit))
            } else if String(character) == decimalSeparator
                        || String(character) == groupingSeparator
                        || character == "+"
                        || character == "-" {
                numeric.append(character)
            } else if character.unicodeScalars.allSatisfy({
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || $0.properties.generalCategory == .currencySymbol
                    || $0.properties.generalCategory == .format
            }) {
                continue
            } else {
                return nil
            }
        }

        let unsigned: Substring
        if numeric.first == "+" || numeric.first == "-" {
            unsigned = numeric.dropFirst()
        } else {
            unsigned = numeric[...]
        }
        guard !unsigned.isEmpty,
              !unsigned.contains("+"),
              !unsigned.contains("-") else {
            return nil
        }

        let decimalParts = unsigned.components(separatedBy: decimalSeparator)
        guard decimalParts.count <= 2,
              let integerPart = decimalParts.first else {
            return nil
        }
        let fractionPart = decimalParts.count == 2 ? decimalParts[1] : nil
        guard !integerPart.isEmpty || fractionPart?.isEmpty == false,
              fractionPart?.contains(groupingSeparator) != true,
              fractionPart?.allSatisfy(\.isNumber) != false,
              validGrouping(
                integerPart,
                separator: groupingSeparator,
                primarySize: formatter.groupingSize,
                secondarySize: formatter.secondaryGroupingSize
              ) else {
            return nil
        }

        var result = numeric.hasPrefix("-") ? "-" : ""
        let normalizedInteger = integerPart.replacingOccurrences(of: groupingSeparator, with: "")
        result += normalizedInteger.isEmpty ? "0" : normalizedInteger
        if let fractionPart {
            result += "." + fractionPart
        }
        return result
    }

    private static func validGrouping(
        _ integerPart: String,
        separator: String,
        primarySize: Int,
        secondarySize: Int
    ) -> Bool {
        guard !separator.isEmpty, integerPart.contains(separator) else {
            return integerPart.allSatisfy(\.isNumber)
        }
        let groups = integerPart.components(separatedBy: separator)
        guard groups.count > 1, groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return false
        }

        let primary = primarySize > 0 ? primarySize : 3
        let secondary = secondarySize > 0 ? secondarySize : primary
        guard groups.last?.count == primary else { return false }
        if groups.count > 2,
           !groups.dropFirst().dropLast().allSatisfy({ $0.count == secondary }) {
            return false
        }
        let leadingLimit = groups.count > 2 ? secondary : primary
        return (1...leadingLimit).contains(groups[0].count)
    }

    private static func decimalNumber(for cents: Int) -> NSDecimalNumber {
        NSDecimalNumber(value: cents).dividing(by: 100)
    }
}

/// `ownershipBadges` formats prices while SwiftUI renders each library row. Keep
/// those formatters reusable, and serialize access because `NumberFormatter` is
/// mutable and may be reached from more than one actor.
private final class CurrencyDisplayFormatterStore: @unchecked Sendable {
    private let lock = NSLock()
    private var formatters: [String: NumberFormatter] = [:]

    func string(from number: NSNumber, currencyCode: String, locale: Locale) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(locale.identifier)|\(currencyCode)"
        let formatter: NumberFormatter
        if let cached = formatters[key] {
            formatter = cached
        } else {
            let newFormatter = NumberFormatter()
            newFormatter.locale = locale
            newFormatter.numberStyle = .currency
            newFormatter.currencyCode = currencyCode
            formatters[key] = newFormatter
            formatter = newFormatter
        }
        return formatter.string(from: number)
    }
}

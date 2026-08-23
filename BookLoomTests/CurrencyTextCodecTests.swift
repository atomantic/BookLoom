import XCTest
@testable import BookLoom

final class CurrencyTextCodecTests: XCTestCase {
    private let usLocale = Locale(identifier: "en_US")
    private let frenchLocale = Locale(identifier: "fr_FR")

    func test_parseTreatsEmptyAndWhitespaceOnlyInputAsEmpty() {
        XCTAssertEqual(CurrencyTextCodec.parse("", locale: usLocale), .empty)
        XCTAssertEqual(CurrencyTextCodec.parse(" \n\t", locale: usLocale), .empty)
    }

    func test_parseAcceptsCurrencyAndGroupingSymbols() {
        XCTAssertEqual(
            CurrencyTextCodec.parse("$1,234.56", locale: usLocale, currencyCode: "USD"),
            .cents(123_456)
        )
        XCTAssertEqual(
            CurrencyTextCodec.parse("USD 1,234.56", locale: usLocale, currencyCode: "USD"),
            .cents(123_456)
        )
    }

    func test_parseUsesLocaleDecimalAndGroupingSeparators() {
        XCTAssertEqual(
            CurrencyTextCodec.parse("1\u{202F}234,56 €", locale: frenchLocale, currencyCode: "EUR"),
            .cents(123_456)
        )
        XCTAssertEqual(
            CurrencyTextCodec.parse("1\u{00A0}234,56\u{00A0}kr", locale: Locale(identifier: "sv_SE"), currencyCode: "SEK"),
            .cents(123_456)
        )
    }

    func test_parseAcceptsFractionWithoutLeadingZero() {
        XCTAssertEqual(CurrencyTextCodec.parse(".50", locale: usLocale), .cents(50))
        XCTAssertEqual(CurrencyTextCodec.parse(",50", locale: frenchLocale), .cents(50))
    }

    func test_parseAcceptsFormatterGeneratedBidirectionalCurrencyText() {
        let locale = Locale(identifier: "ar_SA")
        let formatted = CurrencyTextCodec.displayText(for: 123_456, currencyCode: "SAR", locale: locale)

        XCTAssertEqual(
            CurrencyTextCodec.parse(formatted, locale: locale, currencyCode: "SAR"),
            .cents(123_456)
        )
    }

    func test_parseUsesCurrencySpecificDecimalSeparator() {
        let locale = Locale(identifier: "pt_CV")
        let formatted = CurrencyTextCodec.displayText(for: 123_456, currencyCode: "CVE", locale: locale)
        let editable = CurrencyTextCodec.editableText(for: 123_456, locale: locale)

        XCTAssertEqual(
            CurrencyTextCodec.parse(formatted, locale: locale, currencyCode: "CVE"),
            .cents(123_456)
        )
        XCTAssertEqual(
            CurrencyTextCodec.parse(editable, locale: locale, currencyCode: "CVE"),
            .cents(123_456)
        )
    }

    func test_parseAcceptsNegativeValues() {
        XCTAssertEqual(
            CurrencyTextCodec.parse("-$12.34", locale: usLocale, currencyCode: "USD"),
            .cents(-1_234)
        )
        let southAfricanLocale = Locale(identifier: "en_ZA")
        let formatted = CurrencyTextCodec.displayText(
            for: -123_456,
            currencyCode: "ZAR",
            locale: southAfricanLocale
        )
        XCTAssertEqual(
            CurrencyTextCodec.parse(formatted, locale: southAfricanLocale, currencyCode: "ZAR"),
            .cents(-123_456)
        )
    }

    func test_parseRoundsFractionalCentsIntoStoredRepresentation() {
        XCTAssertEqual(CurrencyTextCodec.parse("12.345", locale: usLocale), .cents(1_235))
    }

    func test_parseRejectsMalformedInput() {
        XCTAssertEqual(CurrencyTextCodec.parse("12.34abc", locale: usLocale), .invalid)
        XCTAssertEqual(CurrencyTextCodec.parse("$12,34.56", locale: usLocale), .invalid)
        XCTAssertEqual(CurrencyTextCodec.parse("12.3.4", locale: usLocale), .invalid)
        XCTAssertEqual(CurrencyTextCodec.parse("--12.34", locale: usLocale), .invalid)
    }

    func test_formattingPreservesStoredCentsAndPresentationStyles() {
        XCTAssertEqual(CurrencyTextCodec.editableText(for: 123_456, locale: usLocale), "1234.56")
        XCTAssertEqual(CurrencyTextCodec.editableText(for: 123_456, locale: frenchLocale), "1234,56")
        XCTAssertEqual(
            CurrencyTextCodec.displayText(for: 123_456, currencyCode: "USD", locale: usLocale),
            "$1,234.56"
        )
    }

    func test_editorPreservesExistingPriceForInvalidTextAndClearsEmptyText() {
        let book = LibraryBook(title: "Piranesi")
        book.purchasePriceCents = 2_800
        let editor = LibraryBookEditor(book)

        editor.applyPrice(from: "malformed")
        XCTAssertEqual(book.purchasePriceCents, 2_800)

        editor.applyPrice(from: "")
        XCTAssertNil(book.purchasePriceCents)
    }
}

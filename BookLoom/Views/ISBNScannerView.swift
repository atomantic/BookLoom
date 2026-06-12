#if os(iOS)
import SwiftUI
import Vision
import VisionKit

struct ISBNScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isSupported else {
            return ISBNScannerUnavailableViewController(
                message: "ISBN scanning requires a device with a supported camera."
            )
        }

        guard DataScannerViewController.isAvailable else {
            return ISBNScannerUnavailableViewController(
                message: "Camera access is needed to scan an ISBN."
            )
        }

        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13]),
                .text()
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        addCancelButton(to: scanner)

        do {
            try scanner.startScanning()
        } catch {
            return ISBNScannerUnavailableViewController(
                message: "Couldn't start the camera scanner."
            )
        }

        return scanner
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private func addCancelButton(to scanner: DataScannerViewController) {
        let cancel = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Cancel"
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        cancel.configuration = configuration
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.addAction(UIAction { _ in onCancel() }, for: .touchUpInside)

        scanner.view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.topAnchor.constraint(equalTo: scanner.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancel.trailingAnchor.constraint(equalTo: scanner.view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ])
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        weak var scanner: DataScannerViewController?
        private var didScan = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            scan(addedItems + allItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            scan(updatedItems + allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            scan([item])
        }

        private func scan(_ items: [RecognizedItem]) {
            guard !didScan else { return }
            for item in items {
                guard let isbn = ISBNScannerParser.isbn(in: item) else { continue }
                didScan = true
                scanner?.stopScanning()
                onScan(isbn)
                return
            }
        }
    }
}

enum ISBNScannerParser {
    static func isbn(in item: RecognizedItem) -> String? {
        switch item {
        case .barcode(let barcode):
            return barcode.payloadStringValue.flatMap(isbn(in:))
        case .text(let text):
            return isbn(in: text.transcript)
        @unknown default:
            return nil
        }
    }

    static func isbn(in value: String) -> String? {
        let uppercased = value.uppercased()

        if let labeled = labeledISBN(in: uppercased) {
            return labeled
        }

        let isbn13Digits = uppercased.filter(\.isNumber)
        if let isbn13 = isbn13Window(in: String(isbn13Digits)) {
            return isbn13
        }

        if uppercased.contains("ISBN") {
            let isbn10Characters = uppercased.filter { $0.isNumber || $0 == "X" }
            return isbn10Window(in: String(isbn10Characters))
        }

        return nil
    }

    // Compiled once; reused across every scanned frame to avoid recompiling the
    // pattern on the main thread for each barcode/text observation.
    private static let labeledISBNRegex = try? NSRegularExpression(
        pattern: #"ISBN(?:-1[03])?[\s:]*([0-9X][0-9X\-\s]{8,28}[0-9X])"#
    )

    private static func labeledISBN(in value: String) -> String? {
        guard let regex = labeledISBNRegex else { return nil }
        let range = NSRange(value.startIndex..., in: value)

        for match in regex.matches(in: value, range: range) {
            guard let matchRange = Range(match.range(at: 1), in: value) else { continue }
            let candidate = String(value[matchRange])
            let clean = candidate
                .filter { $0.isNumber || $0 == "X" }
                .map(String.init)
                .joined()

            if let isbn13 = isbn13Window(in: clean) {
                return isbn13
            }
            if let isbn10 = isbn10Window(in: clean) {
                return isbn10
            }
        }

        return nil
    }

    private static func isbn13Window(in digits: String) -> String? {
        guard digits.count >= 13 else { return nil }
        let characters = Array(digits)
        for index in 0...(characters.count - 13) {
            let candidate = String(characters[index..<(index + 13)])
            guard candidate.hasPrefix("978") || candidate.hasPrefix("979") else { continue }
            if isValidISBN13(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func isbn10Window(in value: String) -> String? {
        guard value.count >= 10 else { return nil }
        let characters = Array(value)
        for index in 0...(characters.count - 10) {
            let candidate = String(characters[index..<(index + 10)])
            if isValidISBN10(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func isValidISBN13(_ value: String) -> Bool {
        guard value.count == 13, value.allSatisfy(\.isNumber) else { return false }
        let digits = value.compactMap(\.wholeNumberValue)
        let sum = digits.prefix(12).enumerated().reduce(0) { partial, pair in
            partial + pair.element * (pair.offset.isMultiple(of: 2) ? 1 : 3)
        }
        let checkDigit = (10 - (sum % 10)) % 10
        return checkDigit == digits[12]
    }

    private static func isValidISBN10(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        var sum = 0
        for (index, character) in value.enumerated() {
            let digit: Int
            if character == "X", index == 9 {
                digit = 10
            } else if let wholeNumberValue = character.wholeNumberValue {
                digit = wholeNumberValue
            } else {
                return false
            }
            sum += digit * (10 - index)
        }
        return sum.isMultiple(of: 11)
    }
}

private final class ISBNScannerUnavailableViewController: UIViewController {
    private let message: String

    init(message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = message
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
#endif

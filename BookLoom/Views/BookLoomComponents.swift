import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct OnboardingHeroArtwork: View {
    @Environment(\.colorScheme) private var colorScheme

    var maxHeight: CGFloat = 260

    @ViewBuilder
    var body: some View {
        heroImage
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        colorScheme == .dark ? BookLoomStyle.paper.opacity(0.22) : .white.opacity(0.38),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.35) : BookLoomStyle.ink.opacity(0.10),
                radius: colorScheme == .dark ? 28 : 18,
                y: colorScheme == .dark ? 16 : 8
            )
    }

    private var heroImage: some View {
        Image("OnboardingHero")
            .resizable()
            .scaledToFill()
            .frame(width: maxHeight, height: maxHeight)
            .accessibilityHidden(true)
    }
}

struct BrandBadge: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [BookLoomStyle.indigo, BookLoomStyle.plum],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "books.vertical.fill")
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(BookLoomStyle.paper)
        }
        .frame(width: size, height: size)
        .shadow(color: BookLoomStyle.indigo.opacity(0.18), radius: size * 0.2, y: size * 0.1)
    }
}

struct TintedCapsuleLabel: View {
    let text: String
    let tint: Color
    var systemImage: String? = nil
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 6

    var body: some View {
        content
            .font(.caption.weight(.semibold))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(tint)
            .background(tint.opacity(0.13), in: Capsule())
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var content: some View {
        if let systemImage {
            Label(text, systemImage: systemImage)
                .accessibilityElement(children: .combine)
        } else {
            Text(text)
        }
    }
}

struct BookCardIndicator {
    let text: String
    let systemImage: String
    var visibleText: String? = nil
    var tint: Color = BookLoomStyle.indigo

    init(_ text: String, systemImage: String, visibleText: String? = nil, tint: Color = BookLoomStyle.indigo) {
        self.text = text
        self.systemImage = systemImage
        self.visibleText = visibleText
        self.tint = tint
    }
}

struct StandardBookCardRow: View {
    let title: String
    let author: String
    var coverURL: URL? = nil
    var indicators: [BookCardIndicator] = []
    var showsDisclosure = false
    var coverWidth: CGFloat = 58
    var coverHeight: CGFloat = 82

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BookCoverTile(
                title: title,
                author: author,
                coverURL: coverURL,
                width: coverWidth,
                height: coverHeight
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !author.isEmpty {
                    Text(author)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !indicators.isEmpty {
                    BookCardIndicatorGrid(indicators: indicators)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.72))
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bookLoomCard(padding: 10)
    }
}

struct StarRatingPicker: View {
    @Binding var stars: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { index in
                Button {
                    stars = (stars == index) ? 0 : index
                } label: {
                    Image(systemName: index <= stars ? "star.fill" : "star")
                        .foregroundStyle(BookLoomStyle.gold)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(index) star\(index == 1 ? "" : "s")")
            }
        }
        .font(.title2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rating")
        .accessibilityValue(stars == 0 ? "Not rated" : "\(stars) out of 5 stars")
    }
}

private struct BookCardIndicatorGrid: View {
    let indicators: [BookCardIndicator]

    private let columns = [
        GridItem(.adaptive(minimum: 38), spacing: 6, alignment: .leading)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(indicators.indices, id: \.self) { index in
                let indicator = indicators[index]
                BookCardIndicatorPill(indicator: indicator)
            }
        }
    }
}

private struct BookCardIndicatorPill: View {
    let indicator: BookCardIndicator

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: indicator.systemImage)
                .font(.caption.weight(.semibold))

            if let visibleText = indicator.visibleText {
                Text(visibleText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
            }
        }
        .foregroundStyle(indicator.tint)
        .padding(.horizontal, indicator.visibleText == nil ? 9 : 10)
        .padding(.vertical, 5)
        .frame(minWidth: indicator.visibleText == nil ? 38 : 50, minHeight: 28)
        .background(indicator.tint.opacity(0.13), in: Capsule())
        .accessibilityLabel(indicator.text)
    }
}

extension BookSubmissionStatus {
    var systemImage: String {
        switch self {
        case .proposed: "tray.full.fill"
        case .current: "book.fill"
        case .completed: "checkmark.seal.fill"
        case .skipped: "forward.fill"
        }
    }

    var tint: Color {
        switch self {
        case .proposed: BookLoomStyle.plum
        case .current: BookLoomStyle.sage
        case .completed: BookLoomStyle.indigo
        case .skipped: BookLoomStyle.coral
        }
    }
}

struct StatusPill: View {
    let status: BookSubmissionStatus

    var body: some View {
        TintedCapsuleLabel(text: status.displayName, tint: status.tint, systemImage: status.systemImage)
    }
}

/// Capsule action button shared by the Club tab's current-book row and the
/// submission detail hero card so both render identically.
struct BookLoomActionButton: View {
    let title: String
    var accessibilityTitle: String? = nil
    let systemImage: String
    let tint: Color
    let prominent: Bool
    var role: ButtonRole? = nil
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(dynamicTypeSize.prefersExpandedControlLayout ? .body.weight(.bold) : .footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, dynamicTypeSize.prefersExpandedControlLayout ? 12 : 8)
                .bookLoomActionWidth(minWidth: 128)
                .frame(minHeight: dynamicTypeSize.prefersExpandedControlLayout ? 52 : 40)
                .background(prominent ? tint : tint.opacity(0.16), in: Capsule())
                .foregroundStyle(prominent ? Color.white : tint)
                .accessibilityLabel(accessibilityTitle ?? title)
        }
        .buttonStyle(.plain)
    }
}

enum BookLoomTextFieldKeyboard {
    case `default`
    case numbersAndPunctuation
    case decimalPad
}

struct BookLoomCompactCard<Content: View>: View {
    let spacing: CGFloat
    let padding: CGFloat
    let content: Content

    init(spacing: CGFloat = 10, padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .bookLoomCard(padding: padding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BookLoomCompactDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.16))
            .frame(height: 1)
    }
}

struct BookLoomCompactTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String?
    var keyboard: BookLoomTextFieldKeyboard = .default
    var isMultiline = false
    var showsCaption = false

    init(
        _ title: String,
        text: Binding<String>,
        placeholder: String? = nil,
        keyboard: BookLoomTextFieldKeyboard = .default,
        isMultiline: Bool = false,
        showsCaption: Bool = false
    ) {
        self.title = title
        _text = text
        self.placeholder = placeholder
        self.keyboard = keyboard
        self.isMultiline = isMultiline
        self.showsCaption = showsCaption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsCaption {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            inputField
                .font(.body)
                .foregroundStyle(BookLoomStyle.ink)
                .lineLimit(isMultiline ? 4...8 : 1...1)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }
                .accessibilityLabel(title)
        }
    }

    private var inputField: some View {
        let field = TextField("", text: $text, prompt: Text(placeholder ?? title), axis: isMultiline ? .vertical : .horizontal)

        #if os(iOS)
        return field
            .keyboardType(uiKeyboardType)
            .autocorrectionDisabled(title == "ISBN")
            .textInputAutocapitalization(textCapitalization)
        #else
        return field
        #endif
    }

    #if os(iOS)
    private var textCapitalization: TextInputAutocapitalization {
        if title == "ISBN" {
            return .characters
        }
        if isMultiline {
            return .sentences
        }
        return .words
    }

    private var uiKeyboardType: UIKeyboardType {
        switch keyboard {
        case .default:
            return .default
        case .numbersAndPunctuation:
            return .numbersAndPunctuation
        case .decimalPad:
            return .decimalPad
        }
    }
    #endif
}

struct CountBadge: View {
    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        TintedCapsuleLabel(text: "\(value) \(label)", tint: tint, horizontalPadding: 8, verticalPadding: 5)
    }
}

struct MetricTile: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let value: String
    let label: String
    let systemImage: String
    var tint: Color = BookLoomStyle.indigo

    var body: some View {
        compactLayout
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.34),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                metricIcon
                valueText
            }
            labelText
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metricIcon: some View {
        Image(systemName: systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(tint)
            .imageScale(.medium)
    }

    private var valueText: some View {
        Text(value)
            .font(.headline.bold())
            .foregroundStyle(BookLoomStyle.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
    }

    private var labelText: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.prefersExpandedControlLayout ? 2 : 1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let detail {
                TintedCapsuleLabel(
                    text: detail,
                    tint: BookLoomStyle.plum,
                    horizontalPadding: 7,
                    verticalPadding: 3
                )
            }
        }
        .textCase(nil)
    }
}

struct InlineEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(BookLoomStyle.plum)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .bookLoomCard(padding: 14)
    }
}

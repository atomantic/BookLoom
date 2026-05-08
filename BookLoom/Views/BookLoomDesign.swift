import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum BookLoomStyle {
    static let ink = adaptiveColor(
        light: RGB(0.13, 0.12, 0.15),
        dark: RGB(0.97, 0.92, 0.84)
    )
    static let paper = Color(red: 0.965, green: 0.898, blue: 0.804)
    static let parchment = Color(red: 0.91, green: 0.80, blue: 0.64)
    static let indigo = adaptiveColor(
        light: RGB(0.13, 0.18, 0.38),
        dark: RGB(0.58, 0.65, 0.94)
    )
    static let plum = adaptiveColor(
        light: RGB(0.42, 0.25, 0.53),
        dark: RGB(0.76, 0.57, 0.84)
    )
    static let sage = adaptiveColor(
        light: RGB(0.37, 0.49, 0.34),
        dark: RGB(0.66, 0.76, 0.57)
    )
    static let coral = adaptiveColor(
        light: RGB(0.80, 0.31, 0.21),
        dark: RGB(0.96, 0.48, 0.35)
    )
    static let gold = adaptiveColor(
        light: RGB(0.83, 0.60, 0.24),
        dark: RGB(0.94, 0.72, 0.36)
    )

    static func screenGradient(for colorScheme: ColorScheme) -> LinearGradient {
        let colors: [Color]
        if colorScheme == .dark {
            colors = [
                Color(red: 0.09, green: 0.08, blue: 0.10),
                Color(red: 0.12, green: 0.13, blue: 0.18),
                Color(red: 0.18, green: 0.13, blue: 0.20)
            ]
        } else {
            colors = [
                BookLoomStyle.paper,
                BookLoomStyle.paper
            ]
        }
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private struct RGB {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
            self.red = CGFloat(red)
            self.green = CGFloat(green)
            self.blue = CGFloat(blue)
            self.alpha = CGFloat(alpha)
        }
    }

    private static func adaptiveColor(light: RGB, dark: RGB) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let color = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        })
        #elseif os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let color = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        })
        #else
        Color(red: Double(light.red), green: Double(light.green), blue: Double(light.blue), opacity: Double(light.alpha))
        #endif
    }
}

extension View {
    func bookLoomScreenBackground() -> some View {
        background(BookLoomScreenBackground().ignoresSafeArea())
    }

    func bookLoomCard(padding: CGFloat = 12, radius: CGFloat = 8) -> some View {
        modifier(BookLoomCardModifier(padding: padding, radius: radius))
    }

    func bookLoomListRow(top: CGFloat = 4, bottom: CGFloat = 4, horizontal: CGFloat = 14) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    func bookLoomListStyle(sectionSpacing: CGFloat = 14) -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            listStyle(.plain)
                .listSectionSpacing(sectionSpacing)
                .environment(\.defaultMinListRowHeight, 0)
        } else {
            listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 0)
        }
        #else
        listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
        #endif
    }

    /// Inline navigation title + opaque toolbar background. Without an opaque
    /// background, `bookLoomScreenBackground()` content scrolls under the
    /// transparent navbar and the inline title overlaps the first card text.
    @ViewBuilder
    func bookLoomNavigationBar() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    func bookLoomActionWidth(minWidth: CGFloat = 180) -> some View {
        modifier(BookLoomActionWidthModifier(minWidth: minWidth))
    }
}

extension DynamicTypeSize {
    /// Start using roomier stacked layouts before iOS reaches the formal
    /// accessibility sizes. `xxxLarge` already makes three-column controls
    /// compress badly on narrow iPhones.
    var prefersExpandedControlLayout: Bool {
        self >= .xxLarge
    }
}

struct BookLoomSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var tint: Color = BookLoomStyle.plum

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isEnabled ? tint : Color.secondary)
            .lineLimit(3)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(background(pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .modifier(BookLoomActionWidthModifier(minWidth: 190))
            .opacity(isEnabled ? 1 : 0.5)
    }

    private func background(pressed: Bool) -> some View {
        let opacity: Double
        if !isEnabled {
            opacity = colorScheme == .dark ? 0.06 : 0.05
        } else if pressed {
            opacity = colorScheme == .dark ? 0.42 : 0.28
        } else {
            opacity = colorScheme == .dark ? 0.30 : 0.18
        }
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tint.opacity(opacity))
    }

    private var strokeColor: Color {
        if !isEnabled {
            return tint.opacity(colorScheme == .dark ? 0.18 : 0.20)
        }
        return tint.opacity(colorScheme == .dark ? 0.55 : 0.45)
    }
}

struct BookLoomProminentButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var tint: Color = BookLoomStyle.plum

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .lineLimit(3)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(background(pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
    }

    private func background(pressed: Bool) -> some View {
        let opacity: Double
        if !isEnabled {
            opacity = colorScheme == .dark ? 0.14 : 0.12
        } else if pressed {
            opacity = colorScheme == .dark ? 0.78 : 0.82
        } else {
            opacity = 1
        }
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tint.opacity(opacity))
    }
}

struct AdaptiveSegmentedControl<Option: Hashable & Identifiable, LabelContent: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> LabelContent

    init(
        _ title: String,
        selection: Binding<Option>,
        options: [Option],
        @ViewBuilder label: @escaping (Option) -> LabelContent
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        if dynamicTypeSize.prefersExpandedControlLayout {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        label(option)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(segmentBackground(isSelected: selection == option))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(segmentStroke(isSelected: selection == option), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        } else {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    label(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func segmentBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? BookLoomStyle.plum.opacity(colorScheme == .dark ? 0.32 : 0.18) : Color.secondary.opacity(0.10))
    }

    private func segmentStroke(isSelected: Bool) -> Color {
        isSelected ? BookLoomStyle.plum.opacity(0.55) : Color.secondary.opacity(0.18)
    }
}

private struct BookLoomActionWidthModifier: ViewModifier {
    let minWidth: CGFloat
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    func body(content: Content) -> some View {
        if shouldFillAvailableWidth {
            content.frame(maxWidth: .infinity)
        } else {
            content
                .frame(minWidth: minWidth)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var shouldFillAvailableWidth: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }
}

private struct BookLoomScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        BookLoomStyle.screenGradient(for: colorScheme)
    }
}

private struct BookLoomCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(cardFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            }
    }

    private var cardFill: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.36)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? .white.opacity(0.16) : .white.opacity(0.50)
    }
}

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

struct BookCoverTile: View {
    let title: String
    let author: String
    var coverURL: URL? = nil
    var width: CGFloat = 58
    var height: CGFloat = 78

    @State private var cachedCoverData: Data?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            coverArt

            if cachedCoverData == nil && coverURL == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(initials)
                        .font(.system(size: width > 80 ? 26 : 18, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if !author.isEmpty {
                        Text(author)
                            .font(.system(size: width > 80 ? 9 : 7, weight: .medium))
                            .lineLimit(2)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .padding(width > 80 ? 12 : 8)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: BookLoomStyle.ink.opacity(0.12), radius: 6, y: 3)
        .accessibilityLabel(title.isEmpty ? "Untitled book" : title)
        .task(id: coverURL?.absoluteString ?? "") {
            guard let coverURL else {
                cachedCoverData = nil
                return
            }
            cachedCoverData = await BookCoverCache.shared.data(for: coverURL)
        }
    }

    @ViewBuilder
    private var coverArt: some View {
        if let cachedCoverImage {
            cachedCoverImage
                .resizable()
                .scaledToFill()
        } else if let coverURL {
            AsyncImage(url: coverURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var cachedCoverImage: Image? {
        guard let coverData = cachedCoverData else { return nil }
        #if os(iOS)
        return UIImage(data: coverData).map { Image(uiImage: $0) }
        #elseif os(macOS)
        return NSImage(data: coverData).map { Image(nsImage: $0) }
        #else
        return nil
        #endif
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: coverColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.black.opacity(0.10))
                    .frame(width: 6)
            }
    }

    private var initials: String {
        let words = title
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let result = String(words).uppercased()
        return result.isEmpty ? "PL" : result
    }

    private var coverColors: [Color] {
        let palettes: [[Color]] = [
            [BookLoomStyle.indigo, BookLoomStyle.plum],
            [BookLoomStyle.sage, BookLoomStyle.indigo],
            [BookLoomStyle.coral, BookLoomStyle.gold],
            [BookLoomStyle.plum, BookLoomStyle.coral]
        ]
        let index = abs(title.hashValue) % palettes.count
        return palettes[index]
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
            .minimumScaleFactor(0.75)
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

struct StatusPill: View {
    let status: BookSubmissionStatus

    var body: some View {
        TintedCapsuleLabel(text: status.displayName, tint: tint, systemImage: systemImage)
    }

    private var systemImage: String {
        switch status {
        case .proposed: "tray.full.fill"
        case .current: "book.fill"
        case .completed: "checkmark.seal.fill"
        case .skipped: "forward.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .proposed: BookLoomStyle.plum
        case .current: BookLoomStyle.sage
        case .completed: BookLoomStyle.indigo
        case .skipped: BookLoomStyle.coral
        }
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
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
    }

    private var labelText: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.prefersExpandedControlLayout ? 2 : 1)
            .minimumScaleFactor(dynamicTypeSize.prefersExpandedControlLayout ? 0.85 : 0.55)
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
                .font(.system(size: 22, weight: .semibold))
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

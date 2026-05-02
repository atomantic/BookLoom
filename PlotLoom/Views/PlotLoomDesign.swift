import SwiftUI

enum PlotLoomStyle {
    static let ink = Color(red: 0.13, green: 0.12, blue: 0.15)
    static let paper = Color(red: 0.99, green: 0.96, blue: 0.89)
    static let parchment = Color(red: 0.95, green: 0.89, blue: 0.78)
    static let indigo = Color(red: 0.13, green: 0.18, blue: 0.38)
    static let plum = Color(red: 0.42, green: 0.25, blue: 0.53)
    static let sage = Color(red: 0.37, green: 0.49, blue: 0.34)
    static let coral = Color(red: 0.80, green: 0.31, blue: 0.21)
    static let gold = Color(red: 0.83, green: 0.60, blue: 0.24)

    static var screenGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.94, blue: 0.86),
                Color(red: 0.92, green: 0.96, blue: 0.92),
                Color(red: 0.94, green: 0.91, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    func plotLoomScreenBackground() -> some View {
        background(PlotLoomStyle.screenGradient.ignoresSafeArea())
    }

    func plotLoomCard(padding: CGFloat = 16, radius: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            }
    }

    func plotLoomListRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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

struct OnboardingHeroArtwork: View {
    var maxHeight: CGFloat = 260

    var body: some View {
        Image("OnboardingHero")
            .resizable()
            .scaledToFit()
            .frame(maxHeight: maxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: PlotLoomStyle.indigo.opacity(0.16), radius: 24, y: 12)
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
                        colors: [PlotLoomStyle.indigo, PlotLoomStyle.plum],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "books.vertical.fill")
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(PlotLoomStyle.paper)
        }
        .frame(width: size, height: size)
        .shadow(color: PlotLoomStyle.indigo.opacity(0.18), radius: size * 0.2, y: size * 0.1)
    }
}

struct BookCoverTile: View {
    let title: String
    let author: String
    var width: CGFloat = 58
    var height: CGFloat = 78

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                }

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
        .frame(width: width, height: height)
        .shadow(color: PlotLoomStyle.ink.opacity(0.16), radius: 10, y: 5)
        .accessibilityLabel(title.isEmpty ? "Untitled book" : title)
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
            [PlotLoomStyle.indigo, PlotLoomStyle.plum],
            [PlotLoomStyle.sage, PlotLoomStyle.indigo],
            [PlotLoomStyle.coral, PlotLoomStyle.gold],
            [PlotLoomStyle.plum, PlotLoomStyle.coral]
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
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
        case .proposed: PlotLoomStyle.plum
        case .current: PlotLoomStyle.sage
        case .completed: PlotLoomStyle.indigo
        case .skipped: PlotLoomStyle.coral
        }
    }
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
    let value: String
    let label: String
    let systemImage: String
    var tint: Color = PlotLoomStyle.indigo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(PlotLoomStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PlotLoomStyle.ink)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
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
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(PlotLoomStyle.plum)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .plotLoomCard(padding: 20)
    }
}

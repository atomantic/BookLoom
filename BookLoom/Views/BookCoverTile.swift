import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    if !author.isEmpty {
                        Text(author)
                            .font(.system(size: width > 80 ? 9 : 7, weight: .medium))
                            .minimumScaleFactor(0.8)
                            .lineLimit(2)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .padding(width > 80 ? 12 : 8)
                // The cover art is a fixed-size thumbnail; cap Dynamic Type so the
                // placeholder text can't overflow the frame at accessibility sizes.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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

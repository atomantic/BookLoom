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

struct BookCoverZoomView: View {
    let title: String
    let author: String
    var coverURL: URL? = nil
    let onDismiss: () -> Void

    @State private var cachedCoverData: Data?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    Spacer(minLength: 28)

                    enlargedCover(in: proxy.size)

                    VStack(spacing: 4) {
                        Text(title.isEmpty ? "Untitled book" : title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        if !author.isEmpty {
                            Text(author)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.74))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close cover")
                .padding(18)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
        .accessibilityLabel("Enlarged cover for \(title.isEmpty ? "Untitled book" : title)")
        .task(id: coverURL?.absoluteString ?? "") {
            guard let coverURL else {
                cachedCoverData = nil
                return
            }
            cachedCoverData = await BookCoverCache.shared.data(for: coverURL)
        }
    }

    @ViewBuilder
    private func enlargedCover(in size: CGSize) -> some View {
        let availableWidth = max(size.width - 48, 180)
        let availableHeight = max(size.height - 160, 240)
        let coverWidth = min(availableWidth, availableHeight * 0.68, 440)
        let coverHeight = min(availableHeight, coverWidth * 1.48)

        if let cachedCoverImage {
            coverFrame(
                cachedCoverImage
                    .resizable()
                    .scaledToFit(),
                width: coverWidth,
                height: coverHeight
            )
        } else if let coverURL {
            AsyncImage(url: coverURL) { phase in
                switch phase {
                case .success(let image):
                    coverFrame(
                        image
                            .resizable()
                            .scaledToFit(),
                        width: coverWidth,
                        height: coverHeight
                    )
                default:
                    placeholderCover(width: coverWidth, height: coverHeight)
                }
            }
        } else {
            placeholderCover(width: coverWidth, height: coverHeight)
        }
    }

    private func coverFrame<Content: View>(_ content: Content, width: CGFloat, height: CGFloat) -> some View {
        content
            .frame(maxWidth: width, maxHeight: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.46), radius: 24, y: 14)
            .accessibilityHidden(true)
    }

    private func placeholderCover(width: CGFloat, height: CGFloat) -> some View {
        BookCoverTile(
            title: title,
            author: author,
            coverURL: nil,
            width: width,
            height: height
        )
        .shadow(color: .black.opacity(0.46), radius: 24, y: 14)
        .accessibilityHidden(true)
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
}

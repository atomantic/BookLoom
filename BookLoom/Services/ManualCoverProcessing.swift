import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ManualCoverProcessing {
    /// Match `BookCoverCache.maxCoverBytes` so a successful encode is always
    /// storable.
    static let maxOutputBytes = 700 * 1024
    /// Refuse to even decode pathological inputs (e.g. a 200 MB TIFF).
    static let maxInputBytes = 25 * 1024 * 1024
    /// Long-edge pixel limit; covers don't need to be larger than this on
    /// any current device.
    static let thumbnailPixelSize: CGFloat = 800

    /// Downsample + JPEG-encode the picked image so it fits within
    /// `maxOutputBytes`. Returns nil if the input is too large to decode,
    /// the format is unsupported, or no quality step compresses small enough.
    static func compress(_ data: Data) -> Data? {
        guard data.count > 0, data.count <= maxInputBytes else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixelSize,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return encodeJPEG(thumbnail, targetBytes: maxOutputBytes)
    }

    private static func encodeJPEG(_ image: CGImage, targetBytes: Int) -> Data? {
        var quality = 0.85
        while quality >= 0.25 {
            let mutable = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(mutable as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            let result = mutable as Data
            if result.count <= targetBytes {
                return result
            }
            quality -= 0.1
        }
        return nil
    }
}

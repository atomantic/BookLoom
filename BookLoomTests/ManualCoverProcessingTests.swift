import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BookLoom

final class ManualCoverProcessingTests: XCTestCase {
    func test_compress_returnsNilForEmptyData() {
        XCTAssertNil(ManualCoverProcessing.compress(Data()))
    }

    func test_compress_returnsNilForNonImageData() {
        let bytes = Data("not an image".utf8)
        XCTAssertNil(ManualCoverProcessing.compress(bytes))
    }

    func test_compress_rejectsInputAboveCap() {
        let oversized = Data(repeating: 0xFF, count: ManualCoverProcessing.maxInputBytes + 1)
        XCTAssertNil(ManualCoverProcessing.compress(oversized))
    }

    func test_compress_downsamplesLargeImageWithinByteCap() throws {
        let original = try makeJPEG(pixelSize: 2400, quality: 0.95)
        XCTAssertGreaterThan(original.count, ManualCoverProcessing.maxOutputBytes,
                             "Test image should start above the byte cap to exercise downsampling")

        let compressed = try XCTUnwrap(ManualCoverProcessing.compress(original))
        XCTAssertLessThanOrEqual(compressed.count, ManualCoverProcessing.maxOutputBytes)

        let outSource = try XCTUnwrap(CGImageSourceCreateWithData(compressed as CFData, nil))
        let outImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(outSource, 0, nil))
        XCTAssertLessThanOrEqual(CGFloat(max(outImage.width, outImage.height)),
                                 ManualCoverProcessing.thumbnailPixelSize)
    }

    func test_compress_passesThroughSmallImage() throws {
        let bytes = try makeJPEG(pixelSize: 200, quality: 0.85)
        let compressed = try XCTUnwrap(ManualCoverProcessing.compress(bytes))
        XCTAssertLessThanOrEqual(compressed.count, ManualCoverProcessing.maxOutputBytes)
    }

    private func makeJPEG(pixelSize: Int, quality: Double) throws -> Data {
        let width = pixelSize
        let height = pixelSize
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        let bufferLength = bytesPerRow * height
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferLength)
        defer { buffer.deallocate() }

        // Pseudo-noise per pixel so the encoder cannot trivially compress it
        // away — that's the path that produces a > 700 KB JPEG at a moderate
        // pixel size and lets us exercise the downsample-and-recompress loop.
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                buffer[offset]     = UInt8((x &* 71 ^ y &* 137) & 0xFF)
                buffer[offset + 1] = UInt8((x &* 197 ^ y &* 53) & 0xFF)
                buffer[offset + 2] = UInt8((x &+ y) & 0xFF)
                buffer[offset + 3] = 255
            }
        }

        let context = try XCTUnwrap(CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let mutable = NSMutableData()
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithData(mutable as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return mutable as Data
    }
}

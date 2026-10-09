import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AstraStyle

final class ClosetImageThumbnailerTests: XCTestCase {
    func testJPEGVariantIsDownsampledAndMateriallySmaller() throws {
        let original = try makeImage(width: 2400, height: 3200, transparent: false, type: UTType.jpeg.identifier, quality: 0.92)
        let thumbnail = try ClosetImageThumbnailer.thumbnailData(from: original)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertLessThanOrEqual(max(width, height), ClosetImageThumbnailer.maxPixelSize)
        XCTAssertLessThan(thumbnail.count, original.count / 4)
        XCTAssertTrue(thumbnail.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    func testTransparentPNGVariantKeepsAlphaWhileReducingDimensionsAndBytes() throws {
        let original = try makeImage(width: 1800, height: 2400, transparent: true, type: UTType.png.identifier)
        let thumbnail = try ClosetImageThumbnailer.thumbnailData(from: original)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(max(image.width, image.height), ClosetImageThumbnailer.maxPixelSize)
        XCTAssertTrue([.premultipliedLast, .last, .premultipliedFirst, .first].contains(image.alphaInfo))
        XCTAssertLessThan(thumbnail.count, original.count)
        XCTAssertTrue(thumbnail.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
    }

    func testInvalidInputFailsInsteadOfCreatingUnreferencedOriginalOnlyUpload() {
        XCTAssertThrowsError(try ClosetImageThumbnailer.thumbnailData(from: Data([1, 2, 3])))
    }

    private func makeImage(
        width: Int,
        height: Int,
        transparent: Bool,
        type: String,
        quality: Double? = nil
    ) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmap = CGBitmapInfo.byteOrder32Big.rawValue |
            (transparent ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmap
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: width / 5, y: height / 8, width: width * 3 / 5, height: height * 3 / 4))
        if transparent {
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1))
            context.fill(CGRect(x: width / 5, y: height / 8, width: width * 3 / 5, height: height * 3 / 4))
        }
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

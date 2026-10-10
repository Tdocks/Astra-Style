import CoreGraphics
import Foundation
import UIKit

struct SnapshotDifference: Error, CustomStringConvertible {
    let expectedSize: CGSize
    let actualSize: CGSize
    let expectedPixelSize: CGSize
    let actualPixelSize: CGSize
    let differingPixels: Int
    let totalPixels: Int
    let channelTolerance: UInt8

    var description: String {
        guard expectedSize == actualSize else {
            return "Snapshot point dimensions differ: expected \(expectedSize), got \(actualSize)."
        }
        guard expectedPixelSize == actualPixelSize else {
            return "Snapshot pixel dimensions differ: expected \(expectedPixelSize), got \(actualPixelSize)."
        }
        guard totalPixels > 0 else {
            return "Snapshot pixel buffers could not be compared."
        }
        return "\(differingPixels) of \(totalPixels) pixels exceed channel tolerance \(channelTolerance)."
    }
}

enum VisualSnapshotComparator {
    static func assertMatches(
        _ actual: UIImage,
        expected: UIImage,
        channelTolerance: UInt8 = 2,
        allowedDifferentPixelFraction: Double = 0.0002
    ) throws {
        guard let actualCGImage = actual.cgImage,
              let expectedCGImage = expected.cgImage,
              actual.size == expected.size,
              actualCGImage.width == expectedCGImage.width,
              actualCGImage.height == expectedCGImage.height,
              let actualPixels = rgbaPixels(actual),
              let expectedPixels = rgbaPixels(expected),
              actualPixels.count == expectedPixels.count else {
            throw SnapshotDifference(
                expectedSize: expected.size,
                actualSize: actual.size,
                expectedPixelSize: pixelSize(expected),
                actualPixelSize: pixelSize(actual),
                differingPixels: 0,
                totalPixels: 0,
                channelTolerance: channelTolerance
            )
        }

        var different = 0
        for pixel in 0..<(actualPixels.count / 4) {
            let offset = pixel * 4
            let differs = (0..<4).contains { channel in
                abs(Int(actualPixels[offset + channel]) - Int(expectedPixels[offset + channel])) > Int(channelTolerance)
            }
            if differs { different += 1 }
        }

        let total = actualPixels.count / 4
        guard Double(different) / Double(max(total, 1)) <= allowedDifferentPixelFraction else {
            throw SnapshotDifference(
                expectedSize: expected.size,
                actualSize: actual.size,
                expectedPixelSize: pixelSize(expected),
                actualPixelSize: pixelSize(actual),
                differingPixels: different,
                totalPixels: total,
                channelTolerance: channelTolerance
            )
        }
    }

    private static func rgbaPixels(_ image: UIImage) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return didDraw ? pixels : nil
    }

    private static func pixelSize(_ image: UIImage) -> CGSize {
        guard let cgImage = image.cgImage else { return .zero }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }
}

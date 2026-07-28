//
//  ImageDownsampling.swift
//  AstraStyle
//
//  Thumbnail downsampling for grid rendering (spec §20 "Never render
//  full-resolution originals in grids"). Uses `ImageIO`'s
//  create-thumbnail-from-source path, which decodes directly at the target
//  size instead of decoding the full-resolution image into memory first —
//  the standard low-memory technique for scrolling image grids at 60fps
//  (spec §20 "Closet grid scrolling: 60 fps").
//

import Foundation
import ImageIO
import UIKit

public enum ImageDownsampling {
    /// Downsamples image data to a thumbnail no larger than
    /// `maxPixelSize` on its longest side, preserving aspect ratio.
    /// Returns `nil` if `data` isn't a decodable image.
    /// - Parameter scale: The display scale to downsample for. Pass the
    ///   value from SwiftUI's `@Environment(\.displayScale)` at the call
    ///   site rather than reading `UIScreen.main` — this function is meant
    ///   to run off the main thread (it's the expensive part of loading a
    ///   grid tile), and `UIScreen.main` is both main-thread-affine and
    ///   deprecated in favor of the per-window trait system. The default
    ///   of `3` is a safe upper bound for every current device class.
    public static func downsample(data: Data, to maxPixelSize: CGFloat, scale: CGFloat = 3) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let pixelSize = maxPixelSize * scale
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// Convenience for the two grid contexts in the app: Closet's
    /// "Editorial grid" tiles (spec §6.14) and outfit item strips
    /// (spec §6.12).
    public enum ThumbnailSize {
        case closetGridTile
        case outfitItemStripTile
        case listRowThumbnail

        var maxPixelSize: CGFloat {
            switch self {
            case .closetGridTile: 220
            case .outfitItemStripTile: 96
            case .listRowThumbnail: 56
            }
        }
    }

    public static func downsample(data: Data, for size: ThumbnailSize, scale: CGFloat = 3) -> UIImage? {
        downsample(data: data, to: size.maxPixelSize, scale: scale)
    }
}

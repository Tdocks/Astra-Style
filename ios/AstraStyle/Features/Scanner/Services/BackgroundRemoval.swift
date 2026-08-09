//
//  BackgroundRemoval.swift
//  AstraStyle
//
//  Spec §6.15's "Normalized cutout image", produced at last.
//
//  Every part of the display path for this already existed:
//  `closet_item_images.background_removed_path` is a column,
//  `ClosetItemImage.displayStoragePath` already prefers it over the raw
//  capture, `ClosetItemDetailViewModel.heroImage` already picks the image
//  that has one, and the closet grid already renders `displayStoragePath`.
//  Nothing had ever written one, so the whole preference was inert and every
//  garment rendered as the photograph it was shot as — a camera roll, not a
//  wardrobe.
//
//  ON DEVICE, NOT AT THE PROVIDER. `VisionAnalysisProvider.removeBackground`
//  exists in the protocol (`docs/08` §2, "fallback background removal when
//  the on-device pass is inadequate") and is still unimplemented — note the
//  word FALLBACK. Apple's Vision does this locally, for free, in a few
//  hundred milliseconds, on an image that is already in memory because we
//  just prepared it for upload. Sending it to a vendor instead would cost
//  money per garment and a round trip per garment to arrive at the same
//  cut-out. The provider hook stays where it is, for the images this pass
//  cannot handle.
//
//  WHAT IT REFUSES TO DO. A flat-lay on a white duvet has no crisp subject,
//  and a mask that swallows half the duvet produces a garment with a torn
//  edge — worse than the honest photograph, and worse in a way the user
//  cannot fix. So this returns nil rather than a bad cut-out whenever Vision
//  finds no instance, or the mask it returns is implausible as a garment
//  (see `plausibleCoverage`). `displayStoragePath` then falls back to the raw
//  capture on its own, which is exactly what that fallback is for.
//
//  Absent is honest. A confounded reading is not.
//

import CoreImage
import Foundation
import UIKit
import Vision

public enum BackgroundRemoval {

    /// Below this share of the frame the "garment" is a speck — a button, a
    /// logo, a shadow — and above it the mask has taken the surface the
    /// garment is lying on with it. Both produce a cut-out that looks broken
    /// rather than clean, so both fall back to the photograph.
    ///
    /// The band is deliberately generous: a flat-lay shot to fill the frame
    /// legitimately covers a lot of it. These are the bounds either side of
    /// "plausible garment", not a quality score.
    static let minimumCoverage = 0.04
    static let maximumCoverage = 0.92

    /// A garment cut out of its background, as PNG bytes with an alpha
    /// channel, or nil when this pass should not be trusted with the image.
    ///
    /// PNG rather than JPEG because JPEG has no alpha: encoding a cut-out as
    /// JPEG silently composites it onto black, which is not a cut-out, it is
    /// a photograph of a garment at night.
    ///
    /// Synchronous and CPU-bound. Call it off the main actor.
    public static func cutout(from data: Data) -> Data? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Vision refusing the image is a fact about the image, not an
            // error the user did anything about. The raw capture is still
            // perfectly good.
            return nil
        }

        guard
            let observation = request.results?.first,
            !observation.allInstances.isEmpty
        else { return nil }

        do {
            let masked = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                // NOT cropped to the instance extent. Cropping would make
                // every tile in the grid a different shape and scale, and a
                // grid of garments that do not share a frame reads as a
                // collage. The garment keeps the framing it was shot in.
                croppedToInstancesExtent: false
            )
            guard let cutoutImage = CIImage(cvPixelBuffer: masked).cgImageWithAlpha() else {
                return nil
            }
            guard plausibleCoverage(of: cutoutImage) else { return nil }
            return UIImage(cgImage: cutoutImage).pngData()
        } catch {
            return nil
        }
    }

    /// What share of the frame survived the mask.
    ///
    /// Measured on a downsampled copy: this is a sanity check, not a
    /// measurement, and counting eight million pixels to decide whether a
    /// number is between 0.04 and 0.92 would cost more than the mask did.
    static func plausibleCoverage(of image: CGImage) -> Bool {
        guard let opaqueShare = opaqueShare(of: image) else { return false }
        return opaqueShare >= minimumCoverage && opaqueShare <= maximumCoverage
    }

    private static func opaqueShare(of image: CGImage) -> Double? {
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        var opaque = 0
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] > 127 {
            opaque += 1
        }
        return Double(opaque) / Double(side * side)
    }
}

private extension CIImage {
    /// `CIContext` is expensive to build and cheap to reuse, and a cut-out
    /// per garment in a twenty-garment batch would otherwise build twenty.
    static let sharedContext = CIContext(options: [.useSoftwareRenderer: false])

    func cgImageWithAlpha() -> CGImage? {
        Self.sharedContext.createCGImage(self, from: extent, format: .RGBA8, colorSpace: colorSpace)
    }
}

//
//  ScannerBatchViewModel+Hints.swift
//  AstraStyle
//
//  The live device-hints seam, split out so `ScannerBatchViewModel` itself
//  needs no image-decoding imports and can be exercised in a test with
//  bytes that are not a JPEG — the same split reasoning as
//  `ScannerReviewViewModel+Pipeline.swift`.
//

import CoreGraphics
import Foundation
import ImageIO

extension ScannerBatchViewModel {

    /// P3-SCAN-06's on-device pass, run once per garment in a batch.
    ///
    /// Returns nil rather than empty hints when the prepared bytes will not
    /// re-decode. The two are not the same thing: empty hints tell the
    /// server "we looked and found no label text and no dominant colour",
    /// nil tells it "we did not look". `GarmentDeviceHints` being optional
    /// on the wire is what carries that distinction, and `docs/08` §2.5
    /// leans on the OCR prior specifically — a brand guess derived from a
    /// hint that was never taken is exactly the confident-wrong answer §2.1
    /// warns about.
    ///
    /// `public` because it is the default argument of a `public`
    /// initializer — Swift will not let one reference an internal symbol.
    ///
    /// `nonisolated` for the other half of the same reason. This is an
    /// extension on a `@MainActor` class, so without it the function inherits
    /// main-actor isolation and cannot be a default value in
    /// `Dependencies.init`, which is nonisolated because the nested struct is
    /// — "main actor-isolated default value in a nonisolated context". Nothing
    /// here touches main-actor state: both Vision adapters are `Sendable`
    /// structs and `DeviceHintsExtraction.extract` is a pure function over a
    /// `CGImage`.
    public nonisolated static func liveDeviceHints(from data: Data) -> GarmentDeviceHints? {
        guard let image = decode(data) else { return nil }
        return DeviceHintsExtraction.extract(
            from: image,
            regionDetector: LiveVisionGarmentRegionDetector(),
            textRecognizer: LiveVisionLabelTextRecognizer()
        )
    }

    private nonisolated static func decode(_ data: Data) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

//
//  DeviceHintsExtraction.swift
//  AstraStyle
//
//  Composes the device-side priors that seed `GarmentDeviceHints` for
//  `POST /closet/analyze-item` (docs/08 §2): dominant colours (optionally
//  restricted by a detected garment region) and OCR text lines.
//
//  WHY THIS FILE EXISTS. Colour extraction and OCR are independent pure/
//  protocol seams (`DominantColorExtraction`, `GarmentRegionDetecting`,
//  `LabelTextRecognizing`). The review / analyze call site needs one place
//  that turns a still `CGImage` into the wire DTO without re-implementing
//  that composition in a view model. Keeping the composition here means:
//
//  - Unit tests inject `MockGarmentRegionDetector` + `MockLabelTextRecognizer`
//    and prove region → colour and OCR → `detectedText` without Vision.
//  - The live Vision adapters stay thin and untested (honest Partial for
//    P3-SCAN-02 / P3-SCAN-03 manual criteria).
//
//  NOT WIRED INTO LIVE CAPTURE QUALITY. Running Vision on the ~10 Hz quality
//  stream would blow the capture budget and is not "safe" in the sense of
//  this ticket. CaptureQuality still measures the whole frame; region-
//  restricted quality is a future call-site change once review owns a still.
//  Dominant colour already accepts an optional `garmentRegion` — this file
//  is the injectable call site that supplies it.
//

import CoreGraphics
import Foundation

public enum DeviceHintsExtraction {

    /// Build device hints from a still image.
    ///
    /// - Parameters:
    ///   - image: Oriented upright capture / import (CGImage space).
    ///   - regionDetector: Optional. When nil, colour uses the centre-region
    ///     prior. When present, a detected region overrides that prior;
    ///     detection failure / nil region falls back to the prior (never
    ///     fails the whole extract).
    ///   - textRecognizer: Optional. When nil, `detectedText` is empty.
    ///     Recognition errors are swallowed into empty text so a bad OCR
    ///     pass cannot block colour hints from reaching the server.
    public static func extract(
        from image: CGImage,
        regionDetector: (any GarmentRegionDetecting)? = nil,
        textRecognizer: (any LabelTextRecognizing)? = nil
    ) -> GarmentDeviceHints {
        let region = detectRegion(in: image, using: regionDetector)
        let colors = DominantColorExtraction.extract(from: image, garmentRegion: region)
            .prefix(3)
            .map(\.hexRGB)
        let text = recognizeText(in: image, using: textRecognizer)
        return GarmentDeviceHints(
            dominantColorsRGB: Array(colors),
            detectedText: text
        )
    }
}

// MARK: - Private

extension DeviceHintsExtraction {

    private static func detectRegion(
        in image: CGImage,
        using detector: (any GarmentRegionDetecting)?
    ) -> GarmentRegion? {
        guard let detector else { return nil }
        do {
            return try detector.detectGarmentRegion(in: image)
        } catch {
            return nil
        }
    }

    private static func recognizeText(
        in image: CGImage,
        using recognizer: (any LabelTextRecognizing)?
    ) -> [String] {
        guard let recognizer else { return [] }
        do {
            return try recognizer.recognizeText(in: image)
        } catch {
            return []
        }
    }
}

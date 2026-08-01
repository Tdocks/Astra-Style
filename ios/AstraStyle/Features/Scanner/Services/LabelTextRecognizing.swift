//
//  LabelTextRecognizing.swift
//  AstraStyle
//
//  Spec §12 "COMPUTER VISION PIPELINE — Device-side", step 4, verbatim:
//
//      4. OCR label text.
//
//  THE SEAM, NOT A PARSER. This protocol returns readable text lines from a
//  care/brand label photo. It does not invent brand or size fields — that
//  inference is the server's job over `GarmentDeviceHints.detectedText`
//  (`docs/08-provider-abstraction.md` §2.5). Parsing brand/size on-device
//  from OCR would duplicate (and drift from) the server prior path.
//
//  The live adapter is a thin `VNRecognizeTextRequest` wrapper
//  (`LiveVisionLabelTextRecognizer`). Unit tests inject
//  `MockLabelTextRecognizer`. Manual acceptance ("OCR extracts readable
//  brand/size text from a clear label photo") remains on-device.
//

import CoreGraphics
import Foundation

/// Spec §12 step 4: extract readable text lines from a garment label image.
public protocol LabelTextRecognizing: Sendable {
    /// Ordered text lines as Vision reports them (typically top-to-bottom).
    /// Empty when nothing readable was found — a real outcome, not an error.
    func recognizeText(in image: CGImage) throws -> [String]
}

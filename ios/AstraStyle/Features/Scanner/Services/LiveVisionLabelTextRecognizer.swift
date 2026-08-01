//
//  LiveVisionLabelTextRecognizer.swift
//  AstraStyle
//
//  Live `LabelTextRecognizing` adapter (spec §12 step 4 / P3-SCAN-03 OCR
//  half). Thin `VNRecognizeTextRequest` wrapper — returns readable lines
//  only; no brand/size parsing (see `LabelTextRecognizing.swift`).
//

import CoreGraphics
import Foundation
import Vision

public struct LiveVisionLabelTextRecognizer: LabelTextRecognizing, Sendable {

    public var recognitionLevel: VNRequestTextRecognitionLevel
    /// Minimum per-candidate confidence to keep a line. Low enough to keep
    /// partially-garbled label text (still useful as a server prior) and
    /// high enough to drop pure noise.
    public var minimumConfidence: Float
    public var maximumLines: Int

    public init(
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        minimumConfidence: Float = 0.25,
        maximumLines: Int = 32
    ) {
        self.recognitionLevel = recognitionLevel
        self.minimumConfidence = minimumConfidence
        self.maximumLines = maximumLines
    }

    public func recognizeText(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            return []
        }

        // Vision returns observations roughly top-to-bottom in image space
        // after sorting by bounding-box midY (Vision coords: bottom-left).
        let sorted = observations.sorted {
            ($0.boundingBox.midY) > ($1.boundingBox.midY)
        }

        var lines: [String] = []
        lines.reserveCapacity(min(sorted.count, maximumLines))
        for observation in sorted {
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else {
                continue
            }
            let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lines.append(trimmed)
            if lines.count >= maximumLines { break }
        }
        return lines
    }
}

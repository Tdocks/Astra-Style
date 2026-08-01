//
//  LiveVisionGarmentRegionDetector.swift
//  AstraStyle
//
//  Live `GarmentRegionDetecting` adapter (spec §12 steps 2–3 / P3-SCAN-02
//  device half). Thin on purpose: every Vision call stays in this file so
//  DominantColorExtraction / CaptureQuality / DeviceHintsExtraction remain
//  unit-testable behind the protocol.
//
//  Strategy:
//  1. `VNGenerateForegroundInstanceMaskRequest` (class-agnostic subject
//     lifting) — best fit for a garment on a neutral background.
//  2. Attention-based saliency fallback when instance mask finds nothing —
//     still works on flat-lay photos where subject lifting is weak.
//
//  Person segmentation is deliberately NOT used: a shirt on a bed is not a
//  person, and that request would systematically return nil for the capture
//  framing the product actually uses (spec §6.16).
//
//  Coordinates: `GarmentRegion` is CGImage-space (origin top-left). Mask-
//  derived boxes are already in that space; Vision saliency rects are
//  flipped here.
//
//  Manual acceptance ("usable foreground mask on a neutral background") is
//  not claimed by unit tests — only by on-device inspection.
//

import CoreGraphics
import CoreVideo
import Foundation
import Vision

public struct LiveVisionGarmentRegionDetector: GarmentRegionDetecting, Sendable {

    /// Reject detections smaller than this fraction of the frame — a speck
    /// of lint is not a garment region worth overriding the centre prior.
    public var minimumCoverage: Double

    /// Confidence attached when the foreground-instance path succeeds.
    /// Instance mask observations do not expose a calibrated confidence;
    /// this is an honest fixed prior, not a model score.
    public var instanceMaskConfidence: Double

    public init(
        minimumCoverage: Double = 0.05,
        instanceMaskConfidence: Double = 0.85
    ) {
        self.minimumCoverage = minimumCoverage
        self.instanceMaskConfidence = instanceMaskConfidence
    }

    public func detectGarmentRegion(in image: CGImage) throws -> GarmentRegion? {
        if let region = try detectViaForegroundInstanceMask(image) {
            return region
        }
        return try detectViaSaliency(image)
    }
}

// MARK: - Foreground instance mask

extension LiveVisionGarmentRegionDetector {

    private func detectViaForegroundInstanceMask(_ image: CGImage) throws -> GarmentRegion? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            return nil
        }

        let mask = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances,
            from: handler
        )
        guard let box = Self.boundingBox(fromMask: mask),
              box.width * box.height >= minimumCoverage else {
            return nil
        }
        return GarmentRegion(boundingBox: box, confidence: instanceMaskConfidence)
    }
}

// MARK: - Saliency fallback

extension LiveVisionGarmentRegionDetector {

    private func detectViaSaliency(_ image: CGImage) throws -> GarmentRegion? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first,
              let objects = observation.salientObjects,
              let best = objects.max(by: { $0.confidence < $1.confidence }) else {
            return nil
        }

        let box = Self.cgImageRect(fromVisionNormalized: best.boundingBox)
        guard box.width * box.height >= minimumCoverage else { return nil }
        return GarmentRegion(boundingBox: box, confidence: Double(best.confidence))
    }
}

// MARK: - Geometry helpers

extension LiveVisionGarmentRegionDetector {

    /// Normalized CGImage-space box (origin top-left) covering non-zero mask pixels.
    static func boundingBox(fromMask mask: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        guard width > 0, height > 0,
              let base = CVPixelBufferGetBaseAddress(mask) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let format = CVPixelBufferGetPixelFormatType(mask)

        // Foreground masks from Vision are typically one-channel float32 or
        // one-channel uint8. Handle both; anything else is treated as absent.
        let extents: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
        if format == kCVPixelFormatType_OneComponent32Float {
            extents = maskExtents(
                width: width, height: height, bytesPerRow: bytesPerRow, base: base
            ) { row, x in
                row.assumingMemoryBound(to: Float32.self)[x] > 0.1
            }
        } else {
            extents = maskExtents(
                width: width, height: height, bytesPerRow: bytesPerRow, base: base
            ) { row, x in
                row.assumingMemoryBound(to: UInt8.self)[x] > 16
            }
        }

        guard let extents else { return nil }
        let pixelWidth = Double(extents.maxX - extents.minX + 1)
        let pixelHeight = Double(extents.maxY - extents.minY + 1)
        return CGRect(
            x: Double(extents.minX) / Double(width),
            y: Double(extents.minY) / Double(height),
            width: pixelWidth / Double(width),
            height: pixelHeight / Double(height)
        )
    }

    private static func maskExtents(
        width: Int,
        height: Int,
        bytesPerRow: Int,
        base: UnsafeMutableRawPointer,
        isForeground: (UnsafeRawPointer, Int) -> Bool
    ) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            let row = UnsafeRawPointer(base.advanced(by: y * bytesPerRow))
            for x in 0..<width where isForeground(row, x) {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minX, minY, maxX, maxY)
    }

    /// Vision normalized rect (origin bottom-left) → CGImage normalized (origin top-left).
    static func cgImageRect(fromVisionNormalized rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: 1 - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}

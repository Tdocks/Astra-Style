//
//  DominantColorExtraction.swift
//  AstraStyle
//
//  Spec §12 "COMPUTER VISION PIPELINE — Device-side", step 5, verbatim:
//
//      5. Extract dominant colors.
//
//  The other half of P3-SCAN-03 is step 4, "OCR label text". That lives
//  behind `LabelTextRecognizing` / `LiveVisionLabelTextRecognizer` and is
//  composed into `GarmentDeviceHints.detectedText` by
//  `DeviceHintsExtraction` — not here. Acceptance ("OCR extracts readable
//  brand/size text from a clear label photo in manual testing") remains
//  manual; unit tests cover the mock recognizer path only.
//
//  Colour extraction is the half that CAN be settled without hardware, and
//  P3-SCAN-03's second criterion — "Dominant color extraction returns a
//  color that matches human judgment for a set of 10 solid-color test
//  garments" — is close to a unit test already: ten solid colours are ten
//  synthesised images, and "matches human judgment" for a solid colour means
//  the returned value is that colour. What a synthesised image cannot settle
//  is whether it also matches human judgment on a real photograph of real
//  cloth under real light, which is a different and harder claim.
//
//  ---------------------------------------------------------------------
//  THE BACKGROUND PROBLEM, AND WHAT THIS DOES ABOUT IT HONESTLY.
//  ---------------------------------------------------------------------
//  A garment laid on a bed occupies maybe half the frame. Run a naive
//  whole-frame histogram over that and the most common colour in the image
//  is the duvet — so the "dominant colour" of a navy shirt comes back white,
//  and that wrong value is then sent to the server as a PRIOR
//  (`docs/08-provider-abstraction.md` §2's `deviceHints.dominantColorsRgb`),
//  where §2.2 says it gets promoted to a top-level field if the analysis
//  degrades. A wrong hint is worse than no hint.
//
//  The real fix is segmentation — mask the background out, extract from the
//  garment only — via `GarmentRegionDetecting` (`LiveVisionGarmentRegionDetector`).
//  `DeviceHintsExtraction` is the injectable call site that supplies a
//  detected region into `extract(from:garmentRegion:)`.
//
//  When no region is supplied, extraction still runs over a CENTRE REGION
//  of the frame, because the capture screen's framing guide (spec §6.16)
//  puts the garment in the middle. It is a prior and it is wrong sometimes.
//  Pixels that are not fully opaque are skipped, so a caller that already
//  HAS a mask can apply it to the `CGImage` and get true garment-only
//  extraction out of this same code path today.
//
//  ---------------------------------------------------------------------
//  COLOUR GEOMETRY IS BORROWED, NOT REWRITTEN.
//  ---------------------------------------------------------------------
//  `ClosetColorSpectrumOrder.HSL` (Features/Closet) already converts packed
//  RGB to hue/saturation/lightness plus the HSV saturation used to decide
//  whether a swatch is a neutral, and its arithmetic is covered by tested
//  textbook values in `ClosetColorSpectrumOrderTests`. A second conversion
//  here would be a second thing to get wrong. It is reused as-is.
//
//  That does make this a Scanner-to-Closet reference across feature
//  folders, which is worth noting rather than pretending away: `HSL` is
//  general colour arithmetic with no closet in it, and when a third caller
//  appears it should move to `Core/`. Two callers is not yet enough to
//  justify moving a tested file.
//

import CoreGraphics
import Foundation

/// One extracted colour and how much of the sampled region it accounts for.
public struct DominantColor: Sendable, Equatable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    /// Fraction of sampled opaque pixels this colour accounts for, 0...1.
    /// Present so a caller can tell "navy shirt with a small white label"
    /// (0.9 / 0.05) from "half navy, half white" (0.5 / 0.45) — the review
    /// screen wants the first as one colour and the second as two.
    public let coverage: Double

    public var packedRGB: UInt32 {
        UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
    }

    /// The string form written into `GarmentDeviceHints.dominantColorsRGB`.
    ///
    /// FORMAT DECISION: `#RRGGBB`, uppercase hex, always seven characters.
    /// The field is typed `[String]` on both sides of the wire
    /// (`docs/08-provider-abstraction.md` §2's `dominantColorsRgb:
    /// string[]`), so the format is a contract that exists nowhere else and
    /// has to be pinned somewhere. This one, because: it is the same
    /// notation `AstraGarmentColor`'s swatch table and `Color(hex:)` already
    /// use, so a value that crosses the wire and a value drawn on screen
    /// read identically in a debugger; it is unambiguous about channel order
    /// in a way `"12,34,56"` is not; and it is fixed-width, so a malformed
    /// entry is visible by length alone. Uppercase because a hex colour is
    /// conventionally written that way and a mixed-case list looks like two
    /// producers wrote it.
    public var hexRGB: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// Hue, saturation, lightness and the neutrality test, from the closet's
    /// existing conversion. Chiefly useful for `isNeutral`: a caller that
    /// gets a grey back should know that its hue is a placeholder rather
    /// than a measurement.
    public var geometry: ClosetColorSpectrumOrder.HSL {
        ClosetColorSpectrumOrder.HSL(hex: packedRGB)
    }

    public init(red: UInt8, green: UInt8, blue: UInt8, coverage: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.coverage = coverage
    }
}

public enum DominantColorExtraction {

    /// Longest edge the sampled region is reduced to before counting.
    ///
    /// 128 gives up to ~16k samples, which is far more than enough to rank
    /// colours by area (the ranking is stable long before this) and cheap
    /// enough to run on the capture path inside the §20 budget.
    public static let samplingLongestEdge = 128

    /// Bits dropped from each channel when binning. 4 bits → 16 levels per
    /// channel → 4096 bins, each 16 wide.
    ///
    /// Coarse enough that the shading across a single fold does not split
    /// one garment colour into a dozen bins; fine enough that 16 levels per
    /// channel still separates colours the eye separates — the app's own
    /// palette has navy at `0x1F2A44` and ink blue at `0x232E45`, which land
    /// in the same bin, and that is the correct outcome for a device hint
    /// whose consumer is a classifier, not a copywriter.
    public static let quantizationBits = 4

    /// Greedy merge radius, as Euclidean distance in 0...255 RGB.
    ///
    /// DERIVED FROM THE BIN SIZE, NOT PICKED BY EYE. What actually needs
    /// merging is the artefact this file creates: one flat garment colour
    /// straddling a bin boundary and appearing twice. Two colours in
    /// adjacent bins differ by at most one cell per channel, and a cell is
    /// `2^quantizationBits = 16` wide, so the worst-case separation of a
    /// split colour is the cell diagonal, `16 × √3 ≈ 27.7`. A radius of 28
    /// rejoins exactly that and nothing further.
    ///
    /// A PERCEPTUAL RULE WAS TRIED FIRST AND REJECTED ON EVIDENCE. The
    /// obvious alternative is to merge by hue/lightness distance using
    /// `ClosetColorSpectrumOrder.HSL`, with a threshold justified by the
    /// spacing of the app's own colour words. Measuring that spacing kills
    /// the idea: across the 35 chromatic entries in `AstraGarmentColor`'s
    /// table, navy and ink blue are 1.6° of hue and 0.010 of lightness
    /// apart, camel and tan 1.4° and 0.008, forest green and hunter green
    /// 0.7° and 0.006. Any hue threshold large enough to merge real shading
    /// variation collapses dozens of pairs the vocabulary treats as
    /// different words, so there is no perceptual threshold that both works
    /// and can be justified from this app's own palette. The quantization
    /// radius can be justified, so that is the one used.
    public static let mergeDistance: Double = 28

    /// Colours below this share of the region are dropped.
    ///
    /// 5% of a sampled garment is roughly a woven label, a button placket or
    /// a contrast cuff — real, but not something to send as a top-level
    /// prior. The first colour is always returned regardless (see `extract`)
    /// so a heavily patterned garment cannot come back with nothing.
    public static let minimumCoverage = 0.05

    /// Default number of colours returned. Three matches the shape the
    /// server expects — one primary plus a couple of secondaries
    /// (`docs/08` §2's `colorLch` and `secondaryColorsLch`) — without
    /// turning a pattern into a paint chart.
    public static let maximumColors = 3

    /// The region sampled when no garment region is known.
    ///
    /// Centre 60% × 70% of the frame, in normalized `CGImage` coordinates
    /// (origin top-left). This is a PRIOR standing in for segmentation, not
    /// a detection: it works because spec §6.16's capture screen frames the
    /// garment centrally, and it fails exactly where you would expect — a
    /// garment shot small in a large room still gets sampled mostly
    /// background. See this file's header.
    public static let defaultRegion = CGRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7)
}

// MARK: - Extraction

extension DominantColorExtraction {

    /// Dominant colours of `region`, most-covering first.
    ///
    /// Synchronous and nonisolated for the reason given in
    /// `CaptureQuality.swift`'s header: the `CGImage` stays in the caller's
    /// isolation domain and only `Sendable` values come back.
    ///
    /// Returns an empty array only when there is nothing to sample — a
    /// degenerate image, an empty region, or a region that is entirely
    /// transparent. Otherwise it always returns at least one colour, even if
    /// that colour covers less than `minimumCoverage`, because "this garment
    /// is too patterned to have a dominant colour" is a judgement for the
    /// review screen to make from the coverage numbers, not a reason to
    /// hand back nothing.
    public static func extract(
        from image: CGImage,
        region: CGRect = defaultRegion,
        limit: Int = maximumColors
    ) -> [DominantColor] {
        guard limit > 0, let pixels = sample(image, region: region) else { return [] }
        let clusters = cluster(pixels)
        let total = clusters.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }

        let colors: [DominantColor] = clusters.map { cluster in
            let coverage = Double(cluster.count) / Double(total)
            return DominantColor(red: cluster.red, green: cluster.green, blue: cluster.blue, coverage: coverage)
        }
        // Coverage descending, then packed value ascending. The tie-break is
        // not cosmetic: two equal halves of a two-colour garment would
        // otherwise come back in whatever order the bins happened to fall,
        // and the FIRST element is the one the server treats as primary.
        let ranked = colors.sorted { lhs, rhs in
            lhs.coverage == rhs.coverage ? lhs.packedRGB < rhs.packedRGB : lhs.coverage > rhs.coverage
        }

        guard let primary = ranked.first else { return [] }
        let rest = ranked.dropFirst().filter { $0.coverage >= minimumCoverage }
        return Array(([primary] + rest).prefix(limit))
    }

    /// The same, using a detected garment region when there is one and
    /// falling back to the centre prior when there is not.
    ///
    /// This overload is the whole point of the seam: when
    /// `GarmentRegionDetecting` is implemented, the call site changes from
    /// passing nothing to passing its result, and nothing in this file
    /// changes at all.
    public static func extract(
        from image: CGImage,
        garmentRegion: GarmentRegion?,
        limit: Int = maximumColors
    ) -> [DominantColor] {
        extract(from: image, region: garmentRegion?.boundingBox ?? defaultRegion, limit: limit)
    }

    /// Ready for `GarmentDeviceHints.dominantColorsRGB`.
    public static func dominantColorHexStrings(
        from image: CGImage,
        region: CGRect = defaultRegion,
        limit: Int = maximumColors
    ) -> [String] {
        extract(from: image, region: region, limit: limit).map(\.hexRGB)
    }
}

// MARK: - Sampling

extension DominantColorExtraction {

    /// One opaque pixel of the sampled region.
    struct Sample: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    /// Crops to `region` and reduces to at most `samplingLongestEdge`,
    /// returning the opaque pixels.
    ///
    /// INTERPOLATION IS `.none`, WHICH IS THE OPPOSITE OF THE CHOICE MADE IN
    /// `CaptureQuality.luminancePlane(from:)`, and the difference is the
    /// point. Area-averaging asks "what is the average of this
    /// neighbourhood", which is right for measuring texture energy and wrong
    /// for naming a colour: average a navy-and-white bengal stripe and you
    /// get a mid grey, a colour that appears nowhere on the shirt and that
    /// would be sent to the server as the garment's dominant colour. Point
    /// sampling can only ever return colours that are actually present. It
    /// aliases on fine patterns — a micro-check may sample unevenly — but an
    /// uneven ratio between two real colours is a far smaller error than one
    /// invented colour.
    ///
    /// PIXELS THAT ARE NOT FULLY OPAQUE ARE SKIPPED. Today that only matters
    /// for a PNG with transparency; tomorrow it is how a caller applies a
    /// segmentation mask — punch the background out to transparent and this
    /// function already ignores it.
    static func sample(_ image: CGImage, region: CGRect) -> [Sample]? {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let clamped = region.intersection(unit)
        guard !clamped.isNull, !clamped.isEmpty else { return nil }

        let pixelRect = CGRect(
            x: clamped.minX * Double(sourceWidth),
            y: clamped.minY * Double(sourceHeight),
            width: clamped.width * Double(sourceWidth),
            height: clamped.height * Double(sourceHeight)
        ).integral
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = image.cropping(to: pixelRect) else { return nil }

        let scale = min(1, Double(samplingLongestEdge) / Double(max(cropped.width, cropped.height)))
        let width = max(1, Int((Double(cropped.width) * scale).rounded()))
        let height = max(1, Int((Double(cropped.height) * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .none
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let base = context.data else { return nil }

        let bytesPerRow = context.bytesPerRow
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var samples: [Sample] = []
        samples.reserveCapacity(width * height)
        for row in 0..<height {
            let rowStart = row * bytesPerRow
            for column in 0..<width {
                let index = rowStart + column * 4
                // Alpha is premultiplied, so anything short of fully opaque
                // has darkened colour channels. Rather than un-premultiply a
                // mask edge — a blend of garment and background that is
                // neither — those pixels are dropped.
                guard bytes[index + 3] == 255 else { continue }
                samples.append(Sample(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2]))
            }
        }
        return samples.isEmpty ? nil : samples
    }
}

// MARK: - Clustering

extension DominantColorExtraction {

    /// A merged group of bins: the mean colour, rounded, and how many
    /// pixels landed in it.
    struct Cluster: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let count: Int
    }

    /// Bins the samples, then greedily merges bins within `mergeDistance`.
    ///
    /// TWO STAGES, BECAUSE THEY DO TWO DIFFERENT JOBS. Binning collapses the
    /// shading variation inside one flat colour — a fold, a shadow, sensor
    /// noise — into a countable group. Merging repairs binning's own
    /// artefact, where one colour sitting on a cell boundary is split
    /// between two neighbouring bins and each half then looks like a minor
    /// colour. Without the merge, a plain navy shirt can report navy at 55%
    /// and a second, indistinguishable navy at 40%, which reads to the
    /// server as a two-tone garment.
    ///
    /// The mean is taken over the ACTUAL sample values, not the bin centre.
    /// A bin centre is up to 8 levels off in every channel, which is a
    /// visible shift on a mid-tone — and this value is what gets sent as the
    /// garment's colour, so it should be a measurement rather than a
    /// rounding of one.
    ///
    /// Greedy from the largest bin down, which is what makes the result
    /// deterministic: bins are visited in descending count with the bin
    /// index as tie-break, so the same image always produces the same
    /// clusters in the same order.
    static func cluster(_ samples: [Sample]) -> [Cluster] {
        let shift = quantizationBits
        let levels = 1 << (8 - shift)
        let binCount = levels * levels * levels
        var counts = [Int](repeating: 0, count: binCount)
        var sumRed = [Int](repeating: 0, count: binCount)
        var sumGreen = [Int](repeating: 0, count: binCount)
        var sumBlue = [Int](repeating: 0, count: binCount)

        for sample in samples {
            let key = (Int(sample.red) >> shift) * levels * levels
                + (Int(sample.green) >> shift) * levels
                + (Int(sample.blue) >> shift)
            counts[key] += 1
            sumRed[key] += Int(sample.red)
            sumGreen[key] += Int(sample.green)
            sumBlue[key] += Int(sample.blue)
        }

        let occupied = (0..<binCount)
            .filter { counts[$0] > 0 }
            .sorted { counts[$0] == counts[$1] ? $0 < $1 : counts[$0] > counts[$1] }

        var merged: [Accumulator] = []
        for key in occupied {
            let candidate = Accumulator(
                red: Double(sumRed[key]) / Double(counts[key]),
                green: Double(sumGreen[key]) / Double(counts[key]),
                blue: Double(sumBlue[key]) / Double(counts[key]),
                count: counts[key]
            )
            if let index = merged.firstIndex(where: { $0.distance(to: candidate) <= mergeDistance }) {
                merged[index].absorb(candidate)
            } else {
                merged.append(candidate)
            }
        }

        return merged.map {
            Cluster(red: channel($0.red), green: channel($0.green), blue: channel($0.blue), count: $0.count)
        }
    }

    /// A cluster mid-merge, in full precision.
    ///
    /// A named type rather than a tuple because the four members are three
    /// channels and a weight — a positional tuple of four numbers where
    /// three of them are interchangeable `Double`s is exactly the shape a
    /// call site gets silently wrong.
    private struct Accumulator {
        var red: Double
        var green: Double
        var blue: Double
        var count: Int

        func distance(to other: Accumulator) -> Double {
            let deltaRed = red - other.red
            let deltaGreen = green - other.green
            let deltaBlue = blue - other.blue
            return (deltaRed * deltaRed + deltaGreen * deltaGreen + deltaBlue * deltaBlue).squareRoot()
        }

        /// Coverage-weighted mean, so a large cluster is not dragged off its
        /// own colour by a handful of pixels on its edge.
        mutating func absorb(_ other: Accumulator) {
            let total = count + other.count
            guard total > 0 else { return }
            red = (red * Double(count) + other.red * Double(other.count)) / Double(total)
            green = (green * Double(count) + other.green * Double(other.count)) / Double(total)
            blue = (blue * Double(count) + other.blue * Double(other.count)) / Double(total)
            count = total
        }
    }

    /// Rounds a channel mean back into 0...255 without wrapping. Clamped
    /// rather than truncated because a mean of 254.7 must become 255, and an
    /// unchecked `UInt8(_:)` conversion on anything at or above 255.5 traps.
    private static func channel(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, value.rounded())))
    }
}

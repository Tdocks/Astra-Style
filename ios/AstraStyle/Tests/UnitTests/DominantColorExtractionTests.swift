//
//  DominantColorExtractionTests.swift
//  AstraStyleTests
//
//  Spec §12 "Device-side" step 5, "Extract dominant colors", and the
//  automatable half of P3-SCAN-03's second acceptance criterion, verbatim:
//
//      - Dominant color extraction returns a color that matches human
//        judgment for a set of 10 solid-color test garments.
//
//  THE TEN SOLID COLOURS BELOW ARE THAT CRITERION, TAKEN LITERALLY. They are
//  ten of `AstraGarmentColor`'s own swatches — navy, charcoal, white, olive,
//  burgundy, camel, sky blue, forest green, rust, mustard — because those are
//  the colours this product actually talks about, and for a flat swatch
//  "matches human judgment" has an exact meaning: the extracted value is the
//  colour that was drawn. Every one of them comes back exactly.
//
//  WHAT THAT DOES NOT PROVE. A synthesised swatch has no light on it, no
//  fold in it, no white balance applied to it and no sensor noise. Ten real
//  garments under real light, judged by a person, is a different test and is
//  the one the criterion was written for — it remains manual and remains
//  unrun. The suites below add the cases a photograph brings that a swatch
//  does not (shading, a second colour, background contamination) so that
//  when the manual test is run, a failure can be attributed rather than
//  guessed at.
//
//  The OCR half of P3-SCAN-03 (§12 step 4) is not tested here because it is
//  not built here; see `DominantColorExtraction.swift`'s header.
//

import CoreGraphics
import Foundation
import Testing
@testable import AstraStyle

@Suite("DominantColorExtraction — ten solid garment colours (P3-SCAN-03)")
struct DominantColorSolidTests {

    /// The ten swatches, as `AstraGarmentColor` defines them.
    private static let garments: [(name: String, hex: UInt32)] = [
        ("navy", 0x1F2A44), ("charcoal", 0x36373A), ("white", 0xF2F0EB),
        ("olive", 0x5A5F3C), ("burgundy", 0x5E2233), ("camel", 0xC19A6B),
        ("sky blue", 0x8FB4D6), ("forest green", 0x2C4433), ("rust", 0xA4552B),
        ("mustard", 0xC9A227)
    ]

    @Test("Each of ten solid garment colours is returned exactly, as one colour covering the whole region", arguments: garments)
    func solidColorsAreReturnedExactly(garment: (name: String, hex: UInt32)) throws {
        let red = UInt8((garment.hex >> 16) & 0xFF)
        let green = UInt8((garment.hex >> 8) & 0xFF)
        let blue = UInt8(garment.hex & 0xFF)
        let image = try #require(ScannerImageFixtures.solid(width: 400, height: 400, red: red, green: green, blue: blue))

        let colors = DominantColorExtraction.extract(from: image)
        let primary = try #require(colors.first)
        #expect(primary.red == red)
        #expect(primary.green == green)
        #expect(primary.blue == blue)
        #expect(primary.packedRGB == garment.hex)
        #expect(colors.count == 1)
        #expect(abs(primary.coverage - 1) < 0.001)
    }

    @Test("The hex strings are the format GarmentDeviceHints.dominantColorsRGB is contracted to carry: a leading hash, uppercase, always seven characters")
    func hexStringFormatIsPinned() throws {
        let image = try #require(ScannerImageFixtures.solid(width: 200, height: 200, red: 0x1F, green: 0x2A, blue: 0x44))
        let strings = DominantColorExtraction.dominantColorHexStrings(from: image)
        #expect(strings == ["#1F2A44"])
        #expect(strings.allSatisfy { $0.count == 7 && $0.hasPrefix("#") })
    }

    @Test("A grey garment reports itself as a neutral through the closet's existing colour geometry, so a caller knows its hue is a convention rather than a measurement")
    func neutralsAreIdentifiableAsNeutral() throws {
        let image = try #require(ScannerImageFixtures.solid(width: 200, height: 200, red: 0x8A, green: 0x8A, blue: 0x8A))
        let primary = try #require(DominantColorExtraction.extract(from: image).first)
        #expect(primary.geometry.isNeutral)
        #expect(primary.hexRGB == "#8A8A8A")
    }
}

@Suite("DominantColorExtraction — what a photograph adds that a swatch does not")
struct DominantColorPhotographTests {

    private let wholeFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

    @Test("Shading across a flat-dyed garment stays ONE colour: a fold is a change in light, not a second garment colour, and reporting it as one would tell the server the shirt is two-tone")
    func shadingDoesNotSplitOneColour() throws {
        let image = try #require(ScannerImageFixtures.shadedSolid(
            width: 400, height: 400, red: 0x1F, green: 0x2A, blue: 0x44, variation: 0.18
        ))
        let colors = DominantColorExtraction.extract(from: image)
        #expect(colors.count == 1)
        let primary = try #require(colors.first)
        #expect(primary.geometry.hue > 200)
        #expect(primary.geometry.hue < 240)
    }

    @Test("Two colours the app's own vocabulary calls different words — navy and ink blue — merge into one hint, which is correct for a consumer that converts to LCh rather than to a word")
    func nearDuplicatesMerge() throws {
        let image = try #require(ScannerImageFixtures.verticalSplit(
            width: 400, height: 400,
            left: ScannerImageFixtures.RGB(0x1F, 0x2A, 0x44),
            right: ScannerImageFixtures.RGB(0x23, 0x2E, 0x45),
            leftFraction: 0.5
        ))
        let colors = DominantColorExtraction.extract(from: image, region: wholeFrame)
        #expect(colors.count == 1)
    }

    @Test("Two genuinely different colours stay separate and come back in coverage order, because the FIRST entry is the one the server treats as the garment's primary colour")
    func distinctColoursAreRankedByCoverage() throws {
        let image = try #require(ScannerImageFixtures.verticalSplit(
            width: 400, height: 400,
            left: ScannerImageFixtures.RGB(0x1F, 0x2A, 0x44),
            right: ScannerImageFixtures.RGB(0xC1, 0x9A, 0x6B),
            leftFraction: 0.7
        ))
        let colors = DominantColorExtraction.extract(from: image, region: wholeFrame)
        #expect(colors.count == 2)
        #expect(colors[0].hexRGB == "#1F2A44")
        #expect(colors[1].hexRGB == "#C19A6B")
        #expect(colors[0].coverage > colors[1].coverage)
        #expect(abs(colors[0].coverage - 0.7) < 0.02)
    }

    @Test("An exactly even split still produces a stable order rather than whichever colour the bins happened to fall in first, since an unstable primary would make the same photograph analyse differently twice")
    func tiesAreBrokenDeterministically() throws {
        let image = try #require(ScannerImageFixtures.verticalSplit(
            width: 400, height: 400,
            left: ScannerImageFixtures.RGB(0xC1, 0x9A, 0x6B),
            right: ScannerImageFixtures.RGB(0x1F, 0x2A, 0x44),
            leftFraction: 0.5
        ))
        let first = DominantColorExtraction.extract(from: image, region: wholeFrame)
        let second = DominantColorExtraction.extract(from: image, region: wholeFrame)
        #expect(first == second)
        #expect(first.first?.hexRGB == "#1F2A44")
    }

    @Test("A woven label on a plain garment is dropped rather than reported as a secondary colour, so a hint list is about the garment and not about its trim")
    func tinyMinorityColoursAreDropped() throws {
        var canvas = ScannerImageFixtures.Canvas(width: 400, height: 400)
        for y in 0..<400 {
            for x in 0..<400 {
                let isLabel = x > 390 && y > 390
                canvas.set(
                    x: x, y: y,
                    red: isLabel ? 0xF2 : 0x1F,
                    green: isLabel ? 0xF0 : 0x2A,
                    blue: isLabel ? 0xEB : 0x44
                )
            }
        }
        let image = try #require(ScannerImageFixtures.image(from: canvas))
        let colors = DominantColorExtraction.extract(from: image, region: wholeFrame)
        #expect(colors.count == 1)
        #expect(colors[0].coverage > 0.99)
    }

    @Test("At most the requested number of colours comes back, ranked, so a patterned garment cannot flood the hint list")
    func limitIsHonoured() throws {
        var canvas = ScannerImageFixtures.Canvas(width: 400, height: 400)
        for y in 0..<400 {
            for x in 0..<400 {
                if x < 240 {
                    canvas.set(x: x, y: y, red: 0x1F, green: 0x2A, blue: 0x44)
                } else if x < 340 {
                    canvas.set(x: x, y: y, red: 0xC1, green: 0x9A, blue: 0x6B)
                } else {
                    canvas.set(x: x, y: y, red: 0xF2, green: 0xF0, blue: 0xEB)
                }
            }
        }
        let image = try #require(ScannerImageFixtures.image(from: canvas))
        #expect(DominantColorExtraction.extract(from: image, region: wholeFrame).count == 3)
        #expect(DominantColorExtraction.extract(from: image, region: wholeFrame, limit: 2).count == 2)
        #expect(DominantColorExtraction.extract(from: image, region: wholeFrame, limit: 1).count == 1)
    }
}

@Suite("DominantColorExtraction — the region, and the segmentation seam")
struct DominantColorRegionTests {

    /// A garment occupying the middle of the frame on a background that
    /// covers more of it than the garment does. This is the shape of the
    /// problem: photograph a shirt on a duvet and the commonest colour in
    /// the frame is the duvet.
    private func garmentOnBackground() throws -> CGImage {
        var canvas = ScannerImageFixtures.Canvas(width: 400, height: 400)
        for y in 0..<400 {
            for x in 0..<400 {
                let isGarment = (100..<300).contains(x) && (80..<320).contains(y)
                canvas.set(
                    x: x, y: y,
                    red: isGarment ? 0x1F : 0xEC,
                    green: isGarment ? 0x2A : 0xEC,
                    blue: isGarment ? 0x44 : 0xEA
                )
            }
        }
        return try #require(ScannerImageFixtures.image(from: canvas))
    }

    @Test("Sampling the whole frame returns the BACKGROUND as the garment's dominant colour — the failure this file's centre-region default exists to avoid, asserted so it stays visible rather than becoming folklore")
    func wholeFrameIsContaminatedByBackground() throws {
        let colors = DominantColorExtraction.extract(
            from: try garmentOnBackground(),
            region: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        #expect(colors.first?.hexRGB == "#ECECEA")
    }

    @Test("The centre-region default gets the garment instead, which is the honest interim behaviour until segmentation exists: a framing prior, not a detection")
    func centreRegionFindsTheGarment() throws {
        let colors = DominantColorExtraction.extract(from: try garmentOnBackground())
        #expect(colors.first?.hexRGB == "#1F2A44")
        // The garment goes from 30% of the frame to 72% of the sampled
        // region — enough to flip the answer, and nowhere near clean. The
        // background is still 28% of the sample and still comes back as a
        // secondary colour, which is precisely the limitation the centre
        // prior has and segmentation does not.
        #expect(colors.first?.coverage ?? 0 > 0.7)
        #expect(colors.count == 2)
    }

    @Test("A detected garment region is used when one is supplied, so the day the Vision adapter behind GarmentRegionDetecting lands, only the call site changes")
    func detectedRegionOverridesThePrior() throws {
        let region = GarmentRegion(boundingBox: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6), confidence: 0.9)
        let colors = DominantColorExtraction.extract(from: try garmentOnBackground(), garmentRegion: region)
        #expect(colors.first?.hexRGB == "#1F2A44")
        #expect(colors.count == 1)
    }

    @Test("A nil region falls back to the centre prior rather than to the whole frame, so an absent detection degrades to the interim behaviour instead of to the known-wrong one")
    func nilRegionFallsBackToThePrior() throws {
        let image = try garmentOnBackground()
        let fallback = DominantColorExtraction.extract(from: image, garmentRegion: nil)
        #expect(fallback == DominantColorExtraction.extract(from: image))
    }

    @Test("Masked-out pixels are excluded, which is how a caller that already has a segmentation mask gets true garment-only extraction from this code path today")
    func transparentPixelsAreExcluded() throws {
        let image = try #require(ScannerImageFixtures.halfTransparent(
            width: 400, height: 400, red: 0x1F, green: 0x2A, blue: 0x44, opaqueFraction: 0.5
        ))
        let colors = DominantColorExtraction.extract(from: image, region: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(colors.count == 1)
        #expect(colors[0].hexRGB == "#1F2A44")
        // Coverage is over SAMPLED pixels, not over the frame: half the
        // image was masked away and the garment fills what is left.
        #expect(abs(colors[0].coverage - 1) < 0.001)
    }

    @Test("A region with nothing in it returns nothing rather than a colour invented from an empty sample")
    func emptyRegionReturnsNothing() throws {
        let image = try #require(ScannerImageFixtures.solid(width: 200, height: 200, red: 10, green: 20, blue: 30))
        #expect(DominantColorExtraction.extract(from: image, region: CGRect(x: 2, y: 2, width: 1, height: 1)).isEmpty)
        #expect(DominantColorExtraction.extract(from: image, limit: 0).isEmpty)
    }

    @Test("A fully transparent region returns nothing, so a mask that excluded everything cannot report the background it was meant to remove")
    func fullyMaskedRegionReturnsNothing() throws {
        let image = try #require(ScannerImageFixtures.halfTransparent(
            width: 400, height: 400, red: 0x1F, green: 0x2A, blue: 0x44, opaqueFraction: 0.5
        ))
        let colors = DominantColorExtraction.extract(from: image, region: CGRect(x: 0.6, y: 0, width: 0.4, height: 1))
        #expect(colors.isEmpty)
    }
}

//
//  BackgroundRemovalTests.swift
//  AstraStyleTests
//
//  These test the CONTRACT, not the quality of Apple's segmentation.
//
//  The valuable property here is not "the cut-out is good" — that is Vision's
//  job and not something a unit test can assert about a synthetic fixture.
//  It is "a cut-out this pass should not be trusted with never reaches the
//  closet", because a garment with a bitten edge is worse than the honest
//  photograph and the user cannot tell which he is looking at.
//

import CoreGraphics
import Foundation
import Testing
@testable import AstraStyle

@Suite("Background removal — what it refuses to do")
struct BackgroundRemovalTests {

    @Test("Bytes that are not an image return nil rather than throwing")
    func nonImageBytesReturnNil() {
        // The save path calls this and discards nil. If it threw instead, a
        // man who had just corrected six fields would be told his garment
        // could not be saved because of a cosmetic pass on the photograph.
        #expect(BackgroundRemoval.cutout(from: Data([0x00, 0x01, 0x02, 0x03])) == nil)
        #expect(BackgroundRemoval.cutout(from: Data()) == nil)
    }

    @Test("A mask covering almost nothing is refused")
    func specksAreRefused() throws {
        // A few opaque pixels in a transparent frame is a button, a logo or a
        // shadow — not a garment. Cutting to it produces a tile that looks
        // broken, and "broken" is indistinguishable from "this app lost my
        // jacket" at a glance in a grid.
        let speck = try #require(image(opaqueFraction: 0.01))
        #expect(!BackgroundRemoval.plausibleCoverage(of: speck))
    }

    @Test("A mask that swallowed the whole frame is refused")
    func wholeFrameMasksAreRefused() throws {
        // The flat-lay-on-a-white-duvet case: Vision finds an instance, and
        // the instance is the duvet. Nothing was cut out, so nothing is
        // gained by storing it as though something had been.
        let everything = try #require(image(opaqueFraction: 1.0))
        #expect(!BackgroundRemoval.plausibleCoverage(of: everything))
    }

    @Test("A garment-sized mask is accepted across the plausible band")
    func garmentSizedMasksAreAccepted() throws {
        // Deliberately checked at both ends and the middle rather than one
        // happy value: the band is the whole decision this function makes.
        for fraction in [0.10, 0.45, 0.85] {
            let garment = try #require(image(opaqueFraction: fraction))
            #expect(
                BackgroundRemoval.plausibleCoverage(of: garment),
                "coverage \(fraction) should read as a garment"
            )
        }
    }

    @Test("The accepted band is the one the source states")
    func bandMatchesItsOwnConstants() {
        // Pins the numbers so a future widening is a deliberate edit with a
        // failing test in front of it, rather than a quiet loosening.
        #expect(BackgroundRemoval.minimumCoverage == 0.04)
        #expect(BackgroundRemoval.maximumCoverage == 0.92)
    }

    /// A square image whose bottom `opaqueFraction` of rows is opaque and
    /// whose remainder is fully transparent — the shape of a mask output,
    /// which is what `plausibleCoverage` measures.
    private func image(opaqueFraction: Double) -> CGImage? {
        let side = 128
        let opaqueRows = Int((Double(side) * opaqueFraction).rounded())
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for row in 0..<opaqueRows {
            for column in 0..<side {
                let offset = (row * side + column) * 4
                pixels[offset] = 200
                pixels[offset + 1] = 160
                pixels[offset + 2] = 120
                pixels[offset + 3] = 255
            }
        }
        return CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }
}

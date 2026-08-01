//
//  CapturePreparationTests.swift
//  AstraStyleTests
//
//  Spec §12 "Device-side" steps 6–7 ("Resize and compress", "Strip
//  unnecessary metadata"), and P3-SCAN-04's acceptance criteria, verbatim:
//
//      - Uploaded images have EXIF/location metadata stripped (verified by
//        inspecting the uploaded object).
//      - Compressed image size is reduced by a measurable factor from the
//        original capture without visible quality loss in the review screen.
//
//  THE FIRST CRITERION IS FULLY SETTLED HERE. "Inspecting the uploaded
//  object" is `CGImageSourceCopyPropertiesAtIndex` over the bytes this
//  pipeline produces, which is exactly what the tests below do — with a
//  fixture built to carry the metadata a real capture carries, including a
//  GPS block, because a photograph of a garment taken at home is a
//  photograph of where the user lives (spec §29).
//
//  THE SECOND IS SETTLED IN HALF. "Reduced by a measurable factor" is
//  measured below. "Without visible quality loss in the review screen" is a
//  human looking at a real photograph on a real display, and no assertion
//  here claims it.
//
//  THE ORIENTATION TESTS ARE THE ONES THAT WOULD CATCH THE WORST BUG. A
//  camera stores sideways pixels plus a tag saying which way up they go.
//  Step 7 removes tags. If the rotation is not baked into the pixels first,
//  every garment ships to the server and to the review screen on its side —
//  and it looks like a camera bug rather than a metadata bug, so it would be
//  hunted for in the wrong file.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AstraStyle

@Suite("CapturePreparation — metadata stripping (spec §12 step 7)")
struct CapturePreparationMetadataTests {

    /// A capture as a camera would hand it over: real pixels, EXIF, GPS,
    /// TIFF and an orientation tag.
    private func capture(orientation: CGImagePropertyOrientation = .up) throws -> Data {
        let image = try #require(ScannerImageFixtures.verticalSplit(
            width: 1200,
            height: 800,
            left: ScannerImageFixtures.RGB(0x1F, 0x2A, 0x44),
            right: ScannerImageFixtures.RGB(0xC1, 0x9A, 0x6B),
            leftFraction: 0.5
        ))
        return try #require(ScannerImageFixtures.jpegData(from: image, orientation: orientation))
    }

    @Test("The fixture really does carry the metadata this pipeline is supposed to remove — a stripping test whose input was already clean would pass forever while proving nothing")
    func fixtureCarriesMetadataToBeginWith() throws {
        let properties = try #require(ScannerImageFixtures.properties(of: try capture(orientation: .right)))
        #expect(properties[kCGImagePropertyExifDictionary] != nil)
        #expect(properties[kCGImagePropertyGPSDictionary] != nil)
        #expect(properties[kCGImagePropertyTIFFDictionary] != nil)
        #expect(properties[kCGImagePropertyOrientation] != nil)
    }

    @Test("The uploaded object carries no GPS block at all, which is the criterion's 'location metadata stripped' in the most literal form it can be asserted in")
    func locationIsGone() throws {
        let prepared = try CapturePreparation.prepareForUpload(try capture())
        let properties = try #require(ScannerImageFixtures.properties(of: prepared.data))
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test("The camera's own EXIF and TIFF identification is gone: no capture timestamp, no lens, no device make or model, no user comment")
    func cameraIdentificationIsGone() throws {
        let prepared = try CapturePreparation.prepareForUpload(try capture())
        let properties = try #require(ScannerImageFixtures.properties(of: prepared.data))
        #expect(properties[kCGImagePropertyTIFFDictionary] == nil)

        // ImageIO writes a small EXIF block of its own — ColorSpace and the
        // pixel dimensions — which is why this asserts on the KEYS rather
        // than on the block's absence. Asserting "no {Exif} at all" would
        // have failed against a dictionary that identifies nobody, and the
        // fix would have been to weaken the test rather than to state what
        // actually survives.
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(exif[kCGImagePropertyExifLensModel] == nil)
        #expect(exif[kCGImagePropertyExifUserComment] == nil)
        let surviving = Set(exif.keys.map { $0 as String })
        #expect(surviving.isSubset(of: ["ColorSpace", "PixelXDimension", "PixelYDimension"]))
    }

    @Test("A capture with no metadata to begin with comes through unchanged in that respect, so the pipeline is not itself adding anything")
    func cleanCaptureStaysClean() throws {
        let image = try #require(ScannerImageFixtures.solid(width: 600, height: 400, red: 90, green: 110, blue: 140))
        let data = try #require(ScannerImageFixtures.jpegData(from: image, includeMetadata: false))
        let prepared = try CapturePreparation.prepareForUpload(data)
        let properties = try #require(ScannerImageFixtures.properties(of: prepared.data))
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyTIFFDictionary] == nil)
    }
}

@Suite("CapturePreparation — orientation is baked in, not tagged")
struct CapturePreparationOrientationTests {

    /// Navy on the left half of the STORED pixels, camel on the right.
    private func landscapeSource() throws -> CGImage {
        try #require(ScannerImageFixtures.verticalSplit(
            width: 1200,
            height: 800,
            left: ScannerImageFixtures.RGB(0x1F, 0x2A, 0x44),
            right: ScannerImageFixtures.RGB(0xC1, 0x9A, 0x6B),
            leftFraction: 0.5
        ))
    }

    @Test("A capture tagged .right — landscape pixels that display as a portrait — comes out of the pipeline with its dimensions swapped, so the rotation happened to the pixels rather than to a tag that was about to be discarded")
    func rotationChangesTheDimensions() throws {
        let data = try #require(ScannerImageFixtures.jpegData(from: try landscapeSource(), orientation: .right))
        let prepared = try CapturePreparation.prepareForUpload(data)
        #expect(prepared.pixelHeight > prepared.pixelWidth)
        #expect(max(prepared.pixelWidth, prepared.pixelHeight) == CapturePreparation.uploadLongestEdge)
    }

    @Test("And the pixels themselves moved: the left half of the stored image becomes the top half of the upload, which is what .right means and what a tag-only rotation would have failed to do")
    func rotationMovesThePixels() throws {
        let data = try #require(ScannerImageFixtures.jpegData(from: try landscapeSource(), orientation: .right))
        let prepared = try CapturePreparation.prepareForUpload(data)
        let decoded = try #require(ScannerImageFixtures.decoded(prepared.data))

        let top = try #require(ScannerImageFixtures.pixel(in: decoded, x: decoded.width / 2, y: decoded.height / 4))
        let bottom = try #require(ScannerImageFixtures.pixel(in: decoded, x: decoded.width / 2, y: 3 * decoded.height / 4))
        // JPEG is lossy, so these compare by which colour is nearer rather
        // than by exact equality: navy is dark and blue-dominant, camel is
        // light and red-dominant, and no amount of quantisation swaps that.
        #expect(top.blue > top.red)
        #expect(bottom.red > bottom.blue)
    }

    @Test("The upload carries no orientation tag, so nothing downstream can rotate it a second time — an absent tag means 'up', and the pixels now genuinely are")
    func noOrientationTagSurvives() throws {
        let data = try #require(ScannerImageFixtures.jpegData(from: try landscapeSource(), orientation: .right))
        let prepared = try CapturePreparation.prepareForUpload(data)
        let properties = try #require(ScannerImageFixtures.properties(of: prepared.data))
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32
        #expect(orientation == nil || orientation == 1)
    }

    @Test("An already-upright capture is not rotated, which is the control that stops the previous test passing for the wrong reason")
    func uprightCaptureIsLeftAlone() throws {
        let data = try #require(ScannerImageFixtures.jpegData(from: try landscapeSource(), orientation: .up))
        let prepared = try CapturePreparation.prepareForUpload(data)
        #expect(prepared.pixelWidth > prepared.pixelHeight)

        let decoded = try #require(ScannerImageFixtures.decoded(prepared.data))
        let left = try #require(ScannerImageFixtures.pixel(in: decoded, x: decoded.width / 4, y: decoded.height / 2))
        let right = try #require(ScannerImageFixtures.pixel(in: decoded, x: 3 * decoded.width / 4, y: decoded.height / 2))
        #expect(left.blue > left.red)
        #expect(right.red > right.blue)
    }
}

@Suite("CapturePreparation — resize and compress (spec §12 step 6)")
struct CapturePreparationResizeTests {

    /// A photograph-like capture. 2048 × 1536 rather than a true 12 MP
    /// frame: the fixture is built a pixel at a time in Swift, and a 12 MP
    /// one costs several seconds in a debug build for a ratio that is
    /// already demonstrated at this size. The 12 MP measurement was taken
    /// out of test and is recorded on `CapturePreparation.jpegQuality`.
    private func capture(width: Int = 2048, height: Int = 1536, quality: Double = 0.92) throws -> Data {
        let image = try #require(ScannerImageFixtures.photographic(width: width, height: height))
        return try #require(ScannerImageFixtures.jpegData(from: image, quality: quality))
    }

    @Test("The upload is capped at the 1024px longest edge that docs/08 §2.3 mandates, which is simultaneously the cost control, the latency control and the accuracy tradeoff for the server leg")
    func longestEdgeIsCapped() throws {
        let prepared = try CapturePreparation.prepareForUpload(try capture())
        #expect(max(prepared.pixelWidth, prepared.pixelHeight) == CapturePreparation.uploadLongestEdge)
        #expect(prepared.pixelWidth == 1024)
        #expect(prepared.pixelHeight == 768)
    }

    @Test("Size is reduced by a measurable factor — P3-SCAN-04's second criterion, in the half of it a machine can settle")
    func sizeIsReducedByAMeasurableFactor() throws {
        let data = try capture()
        let prepared = try CapturePreparation.prepareForUpload(data)
        #expect(prepared.originalByteCount == data.count)
        #expect(prepared.byteCount < data.count)
        // Measured at this size: 4.5×. Asserted at 3× so an encoder change
        // that costs a little does not fail the build, while a pipeline that
        // silently stopped resizing would.
        #expect(prepared.sizeReductionFactor > 3)
        // And the number that matters to the §20 latency budget: an upload
        // this size is about a second on a poor connection.
        #expect(prepared.byteCount < 300_000)
    }

    @Test("An image already under the cap is not upscaled: manufacturing pixels would cost upload bytes and add no information the classifier can use")
    func smallCaptureIsNotUpscaled() throws {
        let prepared = try CapturePreparation.prepareForUpload(try capture(width: 320, height: 240))
        #expect(prepared.pixelWidth == 320)
        #expect(prepared.pixelHeight == 240)
    }

    @Test("The cap is a parameter rather than a constant in the code path, so the accuracy-versus-cost retuning docs/08 §2.3 asks for is a call-site change and not a rewrite")
    func capIsHonouredWhenOverridden() throws {
        let prepared = try CapturePreparation.prepareForUpload(try capture(), longestEdge: 512)
        #expect(max(prepared.pixelWidth, prepared.pixelHeight) == 512)
    }

    @Test("Lower quality really does produce fewer bytes, which is the knob the latency budget is spent with")
    func qualityMovesTheSize() throws {
        let data = try capture()
        let low = try CapturePreparation.prepareForUpload(data, quality: 0.5)
        let high = try CapturePreparation.prepareForUpload(data, quality: 0.9)
        #expect(low.byteCount < high.byteCount)
        #expect(low.pixelWidth == high.pixelWidth)
    }

    @Test("Bytes that are not an image are refused as undecodable rather than as a resize failure — the caller has to tell the user something, and 'that file is not a photo' and 'that photo could not be resized' are different sentences")
    func nonImageDataIsRefusedHonestly() {
        #expect(throws: CapturePreparation.Failure.undecodableImage) {
            _ = try CapturePreparation.prepareForUpload(Data("this is not a photograph".utf8))
        }
    }

    @Test("A nonsensical target size is refused up front instead of producing a one-pixel upload")
    func invalidTargetSizeIsRefused() throws {
        let data = try capture(width: 64, height: 64)
        #expect(throws: CapturePreparation.Failure.invalidTargetSize) {
            _ = try CapturePreparation.prepareForUpload(data, longestEdge: 0)
        }
    }
}

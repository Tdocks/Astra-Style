//
//  DeviceHintsExtractionTests.swift
//  AstraStyleTests
//
//  Proves the injectable composition for P3-SCAN-02 (region → colour) and
//  P3-SCAN-03 (OCR → detectedText) without touching Vision. Live adapters
//  are deliberately not constructed here.
//

import CoreGraphics
import Foundation
import Testing
@testable import AstraStyle

@Suite("DeviceHintsExtraction — garment region feeds dominant colour (P3-SCAN-02)")
struct DeviceHintsRegionTests {

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

    @Test("A mock detector's region is what DominantColorExtraction samples — the injectable seam for LiveVisionGarmentRegionDetector")
    func mockRegionDrivesDominantColour() throws {
        let region = GarmentRegion(
            boundingBox: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6),
            confidence: 0.9
        )
        let detector = MockGarmentRegionDetector(region: region)

        let hints = DeviceHintsExtraction.extract(
            from: try garmentOnBackground(),
            regionDetector: detector
        )

        #expect(hints.dominantColorsRGB.first == "#1F2A44")
        #expect(hints.dominantColorsRGB.count == 1)
        #expect(hints.detectedText.isEmpty)
    }

    @Test("Without a detector, colour falls back to the centre-region prior (same as DominantColorExtraction alone)")
    func nilDetectorUsesCentrePrior() throws {
        let image = try garmentOnBackground()
        let hints = DeviceHintsExtraction.extract(from: image)
        let direct = DominantColorExtraction.extract(from: image).map(\.hexRGB)
        #expect(hints.dominantColorsRGB == direct)
    }

    @Test("A detector that throws degrades to the centre prior rather than failing the extract")
    func detectorErrorFallsBack() throws {
        let image = try garmentOnBackground()
        let hints = DeviceHintsExtraction.extract(
            from: image,
            regionDetector: MockGarmentRegionDetector(error: MockGarmentRegionDetectorError())
        )
        let fallback = DominantColorExtraction.extract(from: image, garmentRegion: nil).map(\.hexRGB)
        #expect(hints.dominantColorsRGB == fallback)
    }
}

@Suite("DeviceHintsExtraction — OCR lines become detectedText (P3-SCAN-03)")
struct DeviceHintsOCRTests {

    @Test("Mock recognizer lines are copied into GarmentDeviceHints.detectedText with no brand/size parsing")
    func mockLinesPassThrough() throws {
        let image = try #require(ScannerImageFixtures.solid(
            width: 64, height: 64, red: 0x20, green: 0x20, blue: 0x20
        ))
        let recognizer = MockLabelTextRecognizer(lines: ["ACME", "SIZE M", "100% COTTON"])

        let hints = DeviceHintsExtraction.extract(
            from: image,
            textRecognizer: recognizer
        )

        #expect(hints.detectedText == ["ACME", "SIZE M", "100% COTTON"])
    }

    @Test("Nil recognizer yields empty detectedText rather than inventing label content")
    func nilRecognizerYieldsEmptyText() throws {
        let image = try #require(ScannerImageFixtures.solid(
            width: 64, height: 64, red: 0x20, green: 0x20, blue: 0x20
        ))
        let hints = DeviceHintsExtraction.extract(from: image)
        #expect(hints.detectedText.isEmpty)
    }

    @Test("A recognizer that throws yields empty detectedText so colour hints still ship")
    func recognizerErrorYieldsEmptyText() throws {
        let image = try #require(ScannerImageFixtures.solid(
            width: 64, height: 64, red: 0x1F, green: 0x2A, blue: 0x44
        ))
        let hints = DeviceHintsExtraction.extract(
            from: image,
            textRecognizer: MockLabelTextRecognizer(error: MockLabelTextRecognizerError())
        )
        #expect(hints.detectedText.isEmpty)
        #expect(hints.dominantColorsRGB.first == "#1F2A44")
    }

    @Test("Region detector and OCR compose independently into one GarmentDeviceHints")
    func regionAndOCRCompose() throws {
        var canvas = ScannerImageFixtures.Canvas(width: 200, height: 200)
        for y in 0..<200 {
            for x in 0..<200 {
                let isGarment = (40..<160).contains(x) && (30..<170).contains(y)
                canvas.set(
                    x: x, y: y,
                    red: isGarment ? 0x8B : 0xF0,
                    green: isGarment ? 0x45 : 0xF0,
                    blue: isGarment ? 0x13 : 0xF0
                )
            }
        }
        let image = try #require(ScannerImageFixtures.image(from: canvas))
        let region = GarmentRegion(
            boundingBox: CGRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7),
            confidence: 0.8
        )

        let hints = DeviceHintsExtraction.extract(
            from: image,
            regionDetector: MockGarmentRegionDetector(region: region),
            textRecognizer: MockLabelTextRecognizer(lines: ["EVERLANE", "M"])
        )

        #expect(hints.dominantColorsRGB.first == "#8B4513")
        #expect(hints.detectedText == ["EVERLANE", "M"])
    }
}

@Suite("LiveVisionGarmentRegionDetector — coordinate helpers")
struct LiveVisionGarmentRegionGeometryTests {

    @Test("Vision bottom-left normalized rects flip to CGImage top-left space")
    func visionRectFlipsToCGImageSpace() {
        // Vision: box sitting on the bottom edge → CGImage: top edge after flip.
        let vision = CGRect(x: 0.1, y: 0.0, width: 0.5, height: 0.25)
        let cg = LiveVisionGarmentRegionDetector.cgImageRect(fromVisionNormalized: vision)
        #expect(abs(cg.origin.x - 0.1) < 0.0001)
        #expect(abs(cg.origin.y - 0.75) < 0.0001)
        #expect(abs(cg.width - 0.5) < 0.0001)
        #expect(abs(cg.height - 0.25) < 0.0001)
    }
}

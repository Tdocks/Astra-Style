//
//  ScannerImageFixtures.swift
//  AstraStyleTests
//
//  Synthesised images for the three scanner-pipeline suites
//  (`CaptureQualityTests`, `CapturePreparationTests`,
//  `DominantColorExtractionTests`).
//
//  WHY THE FIXTURES ARE CODE AND NOT FILES. There is no test-asset bundle in
//  this repo and neither test target declares `resources:` in
//  `ios/project.yml`; nothing under `Tests/` has ever loaded an image. Adding
//  binary fixtures would mean committing photographs to git, wiring a
//  resource phase, and — the part that actually matters — a reviewer being
//  unable to tell from the diff what any given test is asserting about,
//  because the input would be an opaque blob. Every image here is described
//  by the arguments that build it, so "a checkerboard blurred by radius 3"
//  is legible in the test that uses it.
//
//  It also keeps the fixtures honest about what they are. A synthesised
//  checkerboard is NOT a garment photograph, and no test in these suites
//  should claim it is. The thresholds these fixtures exercise were calibrated
//  separately against real photographs; see `CaptureQuality`'s constants.
//
//  WHY THIS IS A SEVENTH FILE. Three suites need the same eight helpers.
//  The alternatives were duplicating them three times, or making one suite's
//  file the implicit home of the other two's fixtures — both worse than a
//  file whose name says exactly what it holds.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScannerImageFixtures {

    /// A raw RGBA8 buffer under construction. Every fixture below builds one
    /// of these and hands it to `image(from:)`, so there is exactly one place
    /// that knows about strides, colour spaces and bitmap layout.
    struct Canvas {
        let width: Int
        let height: Int
        var pixels: [UInt8]

        init(width: Int, height: Int) {
            self.width = max(1, width)
            self.height = max(1, height)
            self.pixels = [UInt8](repeating: 255, count: self.width * self.height * 4)
        }

        mutating func set(x: Int, y: Int, red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let index = (y * width + x) * 4
            pixels[index] = red
            pixels[index + 1] = green
            pixels[index + 2] = blue
            pixels[index + 3] = alpha
        }
    }

    /// Wraps a canvas into a `CGImage`. `nil` only if CoreGraphics refuses
    /// the buffer, which would be a bug in this file rather than in a test.
    static func image(from canvas: Canvas) -> CGImage? {
        let bytesPerRow = canvas.width * 4
        guard let provider = CGDataProvider(data: Data(canvas.pixels) as CFData) else { return nil }
        return CGImage(
            width: canvas.width,
            height: canvas.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// A flat colour. The solid-colour garment of P3-SCAN-03's acceptance
    /// criterion, and the black/blown frames of the exposure tests.
    static func solid(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CGImage? {
        var canvas = Canvas(width: width, height: height)
        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                canvas.set(x: x, y: y, red: red, green: green, blue: blue)
            }
        }
        return image(from: canvas)
    }

    /// A hard-edged checkerboard: the sharp end of the focus scale.
    ///
    /// `cell` is in pixels of the fixture, so a caller controls edge density
    /// directly — which is the property the focus measure actually responds
    /// to, and the reason the tests state the cell size rather than hiding it.
    static func checkerboard(
        width: Int,
        height: Int,
        cell: Int,
        light: UInt8 = 235,
        dark: UInt8 = 25
    ) -> CGImage? {
        var canvas = Canvas(width: width, height: height)
        let size = max(1, cell)
        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                let isLight = ((x / size) + (y / size)).isMultiple(of: 2)
                let value: UInt8 = isLight ? light : dark
                canvas.set(x: x, y: y, red: value, green: value, blue: value)
            }
        }
        return image(from: canvas)
    }
}

extension ScannerImageFixtures {

    /// An 8-bit colour. A named type rather than a `(UInt8, UInt8, UInt8)`
    /// tuple: three interchangeable channels in positional form is the shape
    /// a call site silently transposes, and a transposed fixture colour
    /// would make a colour-extraction test assert the wrong thing while
    /// still passing.
    struct RGB: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(hex: UInt32) {
            self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
        }
    }

    /// Two vertical bands, for the ordering and near-duplicate cases in
    /// dominant-colour extraction.
    ///
    /// - Parameter leftFraction: share of the width the left colour takes.
    static func verticalSplit(
        width: Int,
        height: Int,
        left: RGB,
        right: RGB,
        leftFraction: Double = 0.5
    ) -> CGImage? {
        var canvas = Canvas(width: width, height: height)
        let boundary = Int((Double(canvas.width) * min(max(leftFraction, 0), 1)).rounded())
        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                let colour = x < boundary ? left : right
                canvas.set(x: x, y: y, red: colour.red, green: colour.green, blue: colour.blue)
            }
        }
        return image(from: canvas)
    }

    /// A solid colour with a per-pixel brightness ramp across it, standing in
    /// for the shading a fold puts across flat-dyed cloth. Used to check that
    /// one physical colour does not come back as several.
    static func shadedSolid(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        variation: Double = 0.18
    ) -> CGImage? {
        var canvas = Canvas(width: width, height: height)
        for y in 0..<canvas.height {
            // -variation at the top edge to +variation at the bottom.
            let ramp = 1 + variation * (2 * Double(y) / Double(max(1, canvas.height - 1)) - 1)
            let scale = { (value: UInt8) -> UInt8 in
                UInt8(max(0, min(255, (Double(value) * ramp).rounded())))
            }
            for x in 0..<canvas.width {
                canvas.set(x: x, y: y, red: scale(red), green: scale(green), blue: scale(blue))
            }
        }
        return image(from: canvas)
    }

    /// Blurs by `radius` using three passes of a separable box blur.
    ///
    /// WHY A BOX BLUR AND NOT `CIGaussianBlur`. This has to produce the same
    /// number on every machine and every OS version for the focus assertions
    /// to mean anything; a Core Image filter is a moving target across
    /// releases and is tile-scheduled, and it would also drag a `CIContext`
    /// into a suite that otherwise touches nothing but buffers.
    ///
    /// Three box passes approximate a Gaussian well (the central limit
    /// theorem argument every real-time blur implementation uses). The
    /// equivalent sigma is `sqrt((2r+1)^2 - 1) / 2`, i.e. about 1.4 at
    /// radius 1, 2.4 at radius 2, 3.5 at radius 3 and 4.5 at radius 4 —
    /// those are the numbers the focus thresholds are quoted against.
    static func blurred(_ source: CGImage, radius: Int) -> CGImage? {
        guard radius > 0 else { return source }
        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let base = context.data else { return nil }

        let bytesPerRow = context.bytesPerRow
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var canvas = Canvas(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * bytesPerRow + x * 4
                canvas.set(x: x, y: y, red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2])
            }
        }

        for _ in 0..<3 {
            canvas = boxBlurPass(canvas, radius: radius, horizontal: true)
            canvas = boxBlurPass(canvas, radius: radius, horizontal: false)
        }
        return image(from: canvas)
    }

    /// One separable pass. Edges clamp rather than wrap, so the border does
    /// not acquire an artificial hard edge that the focus measure would then
    /// read as detail.
    private static func boxBlurPass(_ canvas: Canvas, radius: Int, horizontal: Bool) -> Canvas {
        var output = Canvas(width: canvas.width, height: canvas.height)
        let window = Double(radius * 2 + 1)
        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                var totals = [0.0, 0.0, 0.0]
                for offset in -radius...radius {
                    let sampleX = horizontal ? min(max(x + offset, 0), canvas.width - 1) : x
                    let sampleY = horizontal ? y : min(max(y + offset, 0), canvas.height - 1)
                    let index = (sampleY * canvas.width + sampleX) * 4
                    totals[0] += Double(canvas.pixels[index])
                    totals[1] += Double(canvas.pixels[index + 1])
                    totals[2] += Double(canvas.pixels[index + 2])
                }
                output.set(
                    x: x,
                    y: y,
                    red: UInt8(max(0, min(255, (totals[0] / window).rounded()))),
                    green: UInt8(max(0, min(255, (totals[1] / window).rounded()))),
                    blue: UInt8(max(0, min(255, (totals[2] / window).rounded())))
                )
            }
        }
        return output
    }
}

extension ScannerImageFixtures {

    /// Encodes `source` as JPEG, optionally with the metadata a real capture
    /// carries and an orientation tag the pixels have NOT been rotated by.
    ///
    /// That last part is the whole point of the fixture: a camera stores the
    /// sensor's pixels plus an orientation tag saying which way up they go,
    /// so an image that is "portrait" is landscape pixels with a `6` tag on
    /// it. `CapturePreparation` has to bake that rotation into the pixels
    /// BEFORE it drops the tag, and a fixture that arrived pre-rotated could
    /// not tell whether it had.
    ///
    /// The GPS block is not decoration either — P3-SCAN-04's criterion names
    /// location metadata specifically, and a garment photographed at home is
    /// a photograph of where the user lives (spec §29).
    static func jpegData(
        from source: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        includeMetadata: Bool = true,
        quality: Double = 0.95
    ) -> Data? {
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: orientation.rawValue
        ]
        if includeMetadata {
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifDateTimeOriginal: "2026:08:01 09:14:22",
                kCGImagePropertyExifLensModel: "Fixture 26 mm f/1.6",
                kCGImagePropertyExifUserComment: "scanner fixture"
            ] as CFDictionary
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 51.5072,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 0.1276,
                kCGImagePropertyGPSLongitudeRef: "W"
            ] as CFDictionary
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFMake: "Fixture",
                kCGImagePropertyTIFFModel: "Fixture Camera"
            ] as CFDictionary
        }

        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return encoded as Data
    }

    /// Every image property the encoded bytes carry, as ImageIO reads them
    /// back — the "inspecting the uploaded object" half of P3-SCAN-04's first
    /// acceptance criterion, done in-process.
    static func properties(of data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        return properties
    }

    /// Decodes `data` back to a `CGImage` so its pixels can be inspected.
    static func decoded(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// One pixel of an image, as 8-bit RGB.
    ///
    /// Goes through a 1×1 bitmap context rather than the image's own data
    /// provider so it works regardless of how the image was created — the
    /// negative translate is what places the requested pixel under the
    /// context's single sample.
    static func pixel(in image: CGImage, x: Int, y: Int) -> RGB? {
        guard x >= 0, x < image.width, y >= 0, y < image.height else { return nil }
        var buffer = [UInt8](repeating: 0, count: 4)
        let result: Bool = buffer.withUnsafeMutableBufferPointer { pointer -> Bool in
            guard let base = pointer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: 1,
                      height: 1,
                      bitsPerComponent: 8,
                      bytesPerRow: 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height)
            )
            return true
        }
        guard result else { return nil }
        return RGB(buffer[0], buffer[1], buffer[2])
    }
}

extension ScannerImageFixtures {

    /// Photograph-like content: smooth colour variation with a low-amplitude
    /// weave texture over it.
    ///
    /// WHY THIS EXISTS RATHER THAN REUSING `checkerboard`. JPEG's cost is
    /// dominated by high-frequency content, and a checkerboard is nothing
    /// but high frequency: re-encoding one at the size cap can produce MORE
    /// bytes than the capture it came from (measured: a 4032 × 3024
    /// checkerboard came out at 0.8× — larger). Using it to demonstrate the
    /// compression ratio would either report a nonsense number or invite
    /// someone to "fix" the pipeline to satisfy it. Real cloth is smooth
    /// gradients with fine texture on top, which is what this is.
    static func photographic(width: Int, height: Int) -> CGImage? {
        var canvas = Canvas(width: width, height: height)
        let lastX = Double(max(1, canvas.width - 1))
        let lastY = Double(max(1, canvas.height - 1))
        for y in 0..<canvas.height {
            let vertical = Double(y) / lastY
            for x in 0..<canvas.width {
                let horizontal = Double(x) / lastX
                // A gentle weave: two out-of-phase ripples of about ±8
                // levels, which is roughly the texture depth of a mid-weight
                // fabric at this scale and far below the amplitude that
                // would dominate the encode.
                let weave = 8 * sin(Double(x) * 0.7) + 6 * sin(Double(y) * 0.5)
                let red = 60 + 120 * horizontal + weave
                let green = 70 + 90 * vertical + weave
                let blue = 110 + 60 * (1 - horizontal * vertical) - weave
                canvas.set(
                    x: x,
                    y: y,
                    red: UInt8(max(0, min(255, red.rounded()))),
                    green: UInt8(max(0, min(255, green.rounded()))),
                    blue: UInt8(max(0, min(255, blue.rounded())))
                )
            }
        }
        return image(from: canvas)
    }

    /// A garment-coloured left band with a fully transparent right band, for
    /// the masked-input path in dominant-colour extraction.
    ///
    /// The transparent pixels are `(0, 0, 0, 0)` rather than a colour with
    /// zero alpha, because the buffer is premultiplied — a "red but
    /// invisible" pixel is not a representable value, and writing one would
    /// be testing against an image CoreGraphics does not believe in.
    static func halfTransparent(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        opaqueFraction: Double = 0.5
    ) -> CGImage? {
        var canvas = Canvas(width: width, height: height)
        let boundary = Int((Double(canvas.width) * min(max(opaqueFraction, 0), 1)).rounded())
        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                if x < boundary {
                    canvas.set(x: x, y: y, red: red, green: green, blue: blue)
                } else {
                    canvas.set(x: x, y: y, red: 0, green: 0, blue: 0, alpha: 0)
                }
            }
        }
        return image(from: canvas)
    }
}

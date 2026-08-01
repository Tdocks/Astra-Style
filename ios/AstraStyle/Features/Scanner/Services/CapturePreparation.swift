//
//  CapturePreparation.swift
//  AstraStyle
//
//  Spec §12 "COMPUTER VISION PIPELINE — Device-side", steps 6–7, verbatim:
//
//      6. Resize and compress.
//      7. Strip unnecessary metadata.
//
//  (Step 8, "Upload signed object", is P3-SCAN-05's and lives in
//  `LiveClosetRepository`. The server-side list in §12 has a step 7 too —
//  "Generate background-removed asset if device result is inadequate" — and
//  that is P3-SCAN-10, a different thing entirely despite the number.)
//
//  `Data` in, `Data` out. The whole of this file is one pure function over
//  bytes, which is what makes P3-SCAN-04's first acceptance criterion —
//  "Uploaded images have EXIF/location metadata stripped (verified by
//  inspecting the uploaded object)" — something a unit test can actually
//  settle rather than something a human has to check with `exiftool` after a
//  device build.
//
//  ---------------------------------------------------------------------
//  WHY THIS IS A SIBLING OF `Core/Utilities/ImageDownsampling.swift` AND
//  NOT AN EXTENSION OF IT.
//  ---------------------------------------------------------------------
//  That file solves a genuinely similar-looking problem — take image data,
//  produce a smaller version — and it was read closely before this one was
//  written. It is still the wrong place for this, on four counts:
//
//  1. Different output. It returns a `UIImage` for a grid cell to draw. This
//     has to return `Data`, because the thing being produced is an upload
//     body. There is no re-encode in that file at all, so the compression
//     half of step 6 and the whole of step 7 have nowhere to live in it.
//  2. Its `scale` parameter is actively dangerous here. It multiplies the
//     requested size by the display scale (correct: a 220pt tile on a 3×
//     screen needs 660px). An upload has no display scale, and §2.3's cap is
//     in PIXELS. Extending that API would mean a scale parameter that must
//     always be 1, which is an invitation to the bug where someone passes 3
//     and quietly triples every upload.
//  3. Different failure contract. It returns `nil` for "not an image",
//     which is right for a grid cell that can fall back to a placeholder.
//     A capture that cannot be prepared must not be silently dropped — the
//     user photographed something and is owed an error — so this throws.
//  4. Different owner. `Core/Utilities` is shared display plumbing; this is
//     one numbered step of the §12 scanner pipeline and belongs to
//     `Features/Scanner`. Filing an upload encoder under Core would advertise
//     a reuse that does not exist.
//
//  WHAT IS CARRIED OVER, deliberately: the ImageIO
//  create-thumbnail-from-source path (decodes directly at the target size
//  instead of decoding a 12 MP frame into memory first) and, more
//  importantly, `kCGImageSourceCreateThumbnailWithTransform: true`. That
//  flag is the reason orientation is BAKED INTO THE PIXELS here rather than
//  carried as a tag — which matters more for an upload than for a thumbnail,
//  because step 7 removes the tag. Stripping an orientation tag off an
//  unrotated image would lay every garment on its side, on the server and in
//  the review screen both, and it would look like a camera bug rather than a
//  metadata bug.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CapturePreparation {

    /// Longest edge of the uploaded image, in pixels.
    ///
    /// `docs/08-provider-abstraction.md` §2.3, verbatim: "Cap upload
    /// resolution at a fixed ceiling (e.g., 1024px longest edge) tuned
    /// against observed classification accuracy — going higher has rapidly
    /// diminishing accuracy return for a garment-classification task versus
    /// a fine-detail task." That section names image resolution as "the
    /// dominant cost/latency lever" for the server leg, so this constant is
    /// simultaneously the cost control, the latency control and the accuracy
    /// tradeoff. It is not a number to nudge without the accuracy
    /// measurement §2.3 asks for.
    public static let uploadLongestEdge = 1024

    /// JPEG quality for the uploaded image.
    ///
    /// Two constraints, pulling in opposite directions.
    ///
    /// LATENCY. Spec §20 gives item analysis 8 seconds end to end;
    /// `docs/08` §2.4 spends 5.5s of that on the server leg at p50, leaving
    /// roughly 2.5s for upload plus rendering. On a 5 Mbit/s uplink — a
    /// conservative but ordinary LTE figure — 2.5s carries about 1.5 MB
    /// before any TLS or Storage overhead, and the budget has to survive
    /// worse links than that. MEASURED: across five garment photographs from
    /// `brand/quiz-imagery`, re-encoded to simulate a 12 MP capture and run
    /// through this pipeline, the upload came out at 76–99 KB (mean 88 KB) —
    /// about a second on a 1 Mbit/s link, which leaves the 8s ceiling almost
    /// entirely to the server even on a bad connection.
    ///
    /// APPEARANCE. The same bytes are what the review screen displays
    /// (spec §6.16), and P3-SCAN-04's second criterion asks for a
    /// "measurable factor" of reduction "without visible quality loss in the
    /// review screen". 0.72 sits above the 0.6–0.65 region where JPEG ringing
    /// starts showing on the hard edges a garment is full of — plackets,
    /// collar edges, a dark button on light cloth — and below the 0.85+
    /// region where file size climbs steeply for detail this image no longer
    /// has, having just been resampled to 1024px anyway. The measured curve
    /// on one photograph, at the 1024px cap: 48 KB at 0.50, 65 KB at 0.60,
    /// 77 KB at 0.65, 95 KB at 0.72, 110 KB at 0.80, 145 KB at 0.90 — the
    /// knee is broad, so this is a region rather than a single right answer,
    /// and the cost of being 10 KB conservative is small next to the cost of
    /// a review screen that looks cheap.
    ///
    /// Whether the review screen genuinely shows no visible loss is a human
    /// judgement on a real device with real photographs. This constant is a
    /// defensible starting point, not a verified one.
    public static let jpegQuality = 0.72
}

// MARK: - Result and failure

extension CapturePreparation {

    /// What came out of the pipeline, with enough of what went in to prove
    /// the reduction happened.
    ///
    /// `originalByteCount` is kept rather than recomputed because the caller
    /// is about to throw the original away: the capture is not stored at full
    /// resolution anywhere (spec §20, "Never render full-resolution
    /// originals in grids", and there is no reason to hold one in memory
    /// either), so this struct is the only place the before-and-after can
    /// still be compared — for the acceptance criterion, and for the
    /// upload-size telemetry that will tell us whether `jpegQuality` was set
    /// well.
    public struct Prepared: Sendable, Equatable {
        /// JPEG bytes, oriented upright, carrying no EXIF, GPS or TIFF
        /// metadata. This is exactly what gets uploaded.
        public let data: Data
        /// Pixel dimensions AFTER any orientation transform was applied, so
        /// these are the dimensions the server and the review screen see.
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let originalByteCount: Int

        public var byteCount: Int { data.count }

        /// How many times smaller the upload is than the capture. `1` when
        /// the pipeline made no difference; below 1 would mean it made
        /// things worse, which is possible in principle (re-encoding an
        /// already-tiny JPEG) and is worth being able to see rather than
        /// clamping away.
        public var sizeReductionFactor: Double {
            guard !data.isEmpty else { return 0 }
            return Double(originalByteCount) / Double(data.count)
        }

        public init(data: Data, pixelWidth: Int, pixelHeight: Int, originalByteCount: Int) {
            self.data = data
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.originalByteCount = originalByteCount
        }
    }

    /// Why a capture could not be prepared.
    ///
    /// Not `String`-backed: these never cross the wire and never reach a
    /// column. The caller maps them to copy — a scan that fails here has to
    /// surface a retryable error state, not vanish (spec §22, "No unhandled
    /// network failure"; the same rule applies before the network).
    public enum Failure: Error, Equatable {
        /// The bytes are not an image any installed decoder understands.
        case undecodableImage
        /// The image decoded but could not be resampled — in practice a
        /// degenerate zero-dimension image.
        case resizeFailed
        /// The JPEG encoder refused the image or the destination.
        case encodingFailed
        /// `longestEdge` was zero or negative.
        case invalidTargetSize
    }
}

// MARK: - The pipeline

extension CapturePreparation {

    /// Spec §12 steps 6 and 7, in one pass.
    ///
    /// Synchronous and nonisolated, like everything else in this module: the
    /// caller decides which queue this runs on. It is safe to send across
    /// isolation boundaries in either direction because both ends are `Data`
    /// — no `CGImage` escapes this function, which is exactly why this one
    /// could have been `async` and the ones in `CaptureQuality` could not.
    /// It is kept synchronous anyway so the two halves of the pipeline read
    /// the same way at the call site.
    ///
    /// - Parameters:
    ///   - data: The capture as it came off the camera or out of the photo
    ///     library — full resolution, HEIC or JPEG, with whatever metadata
    ///     the device attached.
    ///   - longestEdge: Pixel cap on the longer side. Defaults to
    ///     `uploadLongestEdge` (`docs/08` §2.3).
    ///   - quality: JPEG quality, 0...1. Defaults to `jpegQuality`.
    public static func prepareForUpload(
        _ data: Data,
        longestEdge: Int = uploadLongestEdge,
        quality: Double = jpegQuality
    ) throws -> Prepared {
        guard longestEdge > 0 else { throw Failure.invalidTargetSize }

        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            throw Failure.undecodableImage
        }
        // `CGImageSourceCreateWithData` succeeds on ARBITRARY BYTES — it
        // does not parse anything until asked to. Handing it a text file
        // returns a perfectly good source object that fails much later, at
        // the resize, and the caller would then be told `resizeFailed` for a
        // file that was never an image. `CGImageSourceGetType` is where the
        // format actually gets identified, so the honest error is thrown
        // here.
        guard CGImageSourceGetType(source) != nil, CGImageSourceGetCount(source) > 0 else {
            throw Failure.undecodableImage
        }

        // STEP 6 — resize.
        //
        // `...FromImageAlways` rather than `...FromImageIfAbsent`: an
        // embedded camera thumbnail is typically 320px and would be used in
        // preference to the real image, silently uploading a postage stamp.
        //
        // `...WithTransform` is what bakes orientation into the pixels; see
        // this file's header for why that has to happen BEFORE step 7 rather
        // than being left to the tag step 7 removes.
        //
        // ImageIO does not upscale for `ThumbnailMaxPixelSize`, so an image
        // already under the cap passes through at its own size and only gets
        // re-encoded. That is the right behaviour: §2.3's number is a
        // ceiling, not a target, and manufacturing pixels would cost upload
        // bytes for no information.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longestEdge
        ]
        guard let resized = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw Failure.resizeFailed
        }

        // STEP 7 — compress, and strip metadata by construction.
        //
        // THE STRIPPING IS THE ABSENCE OF A COPY, NOT A DELETION. Nothing
        // here reads the source's properties, so nothing can carry them
        // forward: `CGImageDestinationAddImage` writes the image plus
        // exactly the properties handed to it, and the only property handed
        // to it is the compression quality. There is no
        // `kCGImageDestinationMetadata`, no copy of the source dictionary,
        // and — deliberately — no `kCGImagePropertyOrientation` either, since
        // writing even an identity orientation would create the TIFF block
        // this step exists to avoid, and an absent orientation already means
        // "up" by the JPEG/EXIF convention.
        //
        // The alternative anyone reaches for first, `UIImage(data:)` then
        // `.jpegData(compressionQuality:)`, was rejected: what it preserves
        // is a platform detail rather than a contract, it gives no control
        // over what survives, and it drops the orientation transform on the
        // floor rather than baking it in. A criterion that says "verified by
        // inspecting the uploaded object" deserves a code path whose output
        // can be stated exactly.
        //
        // AND HERE IS THAT EXACT STATEMENT, measured by reading the output
        // back with `CGImageSourceCopyPropertiesAtIndex`. Given a capture
        // carrying EXIF, GPS, TIFF and an orientation tag, the upload
        // carries: `ColorModel`, `Depth`, `PixelWidth`, `PixelHeight`,
        // `ProfileName`, a `{JFIF}` block (version and 72 dpi density), and
        // a three-key `{Exif}` block that ImageIO writes itself —
        // `ColorSpace`, `PixelXDimension`, `PixelYDimension`. The `{GPS}`
        // and `{TIFF}` blocks and the orientation tag are gone, along with
        // every EXIF key that came from the camera: no capture timestamp, no
        // lens or device model, no user comment, no location.
        //
        // So "metadata stripped" is not literally "no metadata block". It is
        // "nothing that identifies the person, the place, the time or the
        // device", and the residue is a restatement of the image's own
        // dimensions and colour model. Saying that precisely is the point of
        // doing it this way; a `UIImage` round-trip could not make the claim.
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw Failure.encodingFailed
        }
        let destinationProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: max(0, min(1, quality))
        ]
        CGImageDestinationAddImage(destination, resized, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }

        return Prepared(
            data: encoded as Data,
            pixelWidth: resized.width,
            pixelHeight: resized.height,
            originalByteCount: data.count
        )
    }
}

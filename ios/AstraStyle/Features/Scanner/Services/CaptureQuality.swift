//
//  CaptureQuality.swift
//  AstraStyle
//
//  Spec §12 "COMPUTER VISION PIPELINE — Device-side", steps 1–3, verbatim:
//
//      1. Detect blur and exposure.
//      2. Detect likely garment region.
//      3. Segment foreground where supported.
//
//  This file owns step 1 outright and the `GarmentRegionDetecting` protocol
//  for steps 2–3 (live Vision adapter is a sibling file). That split is
//  deliberate and is the central design decision of the scanner phase, so
//  it is written down here rather than left to be inferred:
//
//  THE SIMULATOR HAS NO CAMERA. CI runs on `macos-26` simulators, so no
//  assertion about `AVCaptureSession` can ever run there — P3-SCAN-01's own
//  acceptance criterion ("blur warning appears when the live preview is
//  detectably blurred, tested with a deliberately shaken capture") is a
//  device-only, human-run test and will stay one. The only defence against
//  that is to keep the untestable layer as thin as it can possibly be: the
//  camera session produces frames and does nothing else, and every judgement
//  made about a frame lives here, as synchronous functions over a pixel
//  buffer that a test can synthesise. Anything that migrates from here into
//  the capture controller becomes permanently unverifiable.
//
//  STEPS 2–3 LIVE ADAPTER. `GarmentRegionDetecting` (bottom of this file) is
//  implemented by `LiveVisionGarmentRegionDetector`. The protocol stays here
//  so quality / colour code depends on the seam, not on Vision. Label OCR
//  (step 4) is `LabelTextRecognizing` in its own files — see P3-SCAN-03.
//
//  ---------------------------------------------------------------------
//  CONCURRENCY — why nothing here is `async` and nothing is an actor.
//  ---------------------------------------------------------------------
//  `CGImage` and `CVPixelBuffer` are not `Sendable`, and the caller is a
//  capture-queue callback holding exactly those. Making these entry points
//  `async` would push the call onto the generic executor, which means the
//  arguments cross an isolation boundary, which means a strict-concurrency
//  error the caller can only silence with `@unchecked Sendable` — a lie
//  about a CoreGraphics object it does not own.
//
//  So every entry point is SYNCHRONOUS and nonisolated. A synchronous
//  nonisolated call runs in the caller's own isolation domain, so the
//  non-`Sendable` image never crosses anything, and the capture queue gets
//  its verdict without hopping. The values that DO travel — `LuminancePlane`
//  and the verdict types — are all `Sendable` value types, so a caller that
//  computes on the capture queue and updates a `@MainActor` view model can
//  send the result across without a warning.
//

import CoreGraphics
import Foundation

// MARK: - Verdict vocabulary

/// What is wrong with a frame. One case per problem the capture screen can
/// give the user a different instruction about — which is the whole reason
/// this is an enum and not a `Bool`: "unusable" tells a man nothing he can
/// act on, and the three cases below are three different physical actions.
public enum CaptureQualityIssue: String, CaseIterable, Sendable {
    case blurred
    case underexposed
    case overexposed
}

/// How bad a problem is.
///
/// Three levels rather than two because auto-capture and the warning label
/// are different decisions with different costs. Warning on a marginal frame
/// costs the user a glance; blocking auto-capture on one costs him the shot
/// he was trying to take. `.warning` says "this will probably analyse
/// badly", `.blocking` says "this will not analyse at all".
///
/// `Int`-backed and `Comparable` so severities from independent dimensions
/// combine with `max(_:_:)` rather than a hand-written ladder.
public enum CaptureQualitySeverity: Int, CaseIterable, Comparable, Sendable {
    case acceptable = 0
    case warning = 1
    case blocking = 2

    public static func < (lhs: CaptureQualitySeverity, rhs: CaptureQualitySeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The focus half of the verdict, with the measurement that produced it.
///
/// The raw number is public on purpose. A threshold that can only be
/// evaluated by watching a label appear is a threshold nobody will ever
/// retune; exposing the variance lets a device-side diagnostic build log
/// what real captures actually measure, which is the only way the numbers
/// below stop being estimates.
public struct BlurAssessment: Sendable, Equatable {
    /// Variance of the Laplacian response, on the 0...255 sample scale, at
    /// `CaptureQuality.analysisLongestEdge`. Higher is sharper.
    public let laplacianVariance: Double
    public let severity: CaptureQualitySeverity

    /// `false` when the frame is too dark for the focus measure to mean
    /// anything (see `CaptureQuality.blurMeasurementFloorLuminance`). A dark
    /// frame has almost no gradient to differentiate, so it scores as
    /// blurred whether or not it is — telling a man to hold steady when he
    /// is standing in the dark sends him to fix the wrong thing.
    public let isMeaningful: Bool
}

/// The light half of the verdict.
public struct ExposureAssessment: Sendable, Equatable {
    /// Mean sample value, 0...1, in the sRGB-ENCODED domain (not linear
    /// light). Every threshold in this file is stated in the same domain;
    /// see `CaptureQuality.midGreyEncoded` for the conversion and why.
    public let meanLuminance: Double
    /// Fraction of samples at or above `CaptureQuality.clippedSample` —
    /// pixels that carry no colour information at all.
    public let clippedHighlightFraction: Double
    /// Fraction of samples at or below `CaptureQuality.crushedSample`.
    public let crushedShadowFraction: Double
    public let severity: CaptureQualitySeverity
    /// `nil` when the exposure is acceptable.
    public let issue: CaptureQualityIssue?
}

/// The whole judgement about one frame.
///
/// PER-DIMENSION SEVERITY, NOT ONE OVERALL LEVEL. A single
/// acceptable/warn/block scalar was the first shape considered and it is
/// wrong: the screen has to name the problem for the warning to be worth
/// showing at all, and a scalar throws away which problem it was. It also
/// loses the case that matters most for auto-capture — dark AND soft, where
/// the softness is a consequence of the darkness and only one instruction is
/// worth giving.
public struct CaptureQualityVerdict: Sendable, Equatable {
    public let blur: BlurAssessment
    public let exposure: ExposureAssessment

    public init(blur: BlurAssessment, exposure: ExposureAssessment) {
        self.blur = blur
        self.exposure = exposure
    }

    /// The worse of the two dimensions.
    public var severity: CaptureQualitySeverity {
        max(exposure.severity, blur.severity)
    }

    /// Whether optional auto-capture (spec §6.16) may fire on this frame.
    /// Warnings do not block: the user still gets to take the photo he was
    /// pointing at, he is only told what it will cost him.
    public var allowsAutoCapture: Bool {
        severity < .blocking
    }

    /// The one problem to put on screen, or `nil` when the frame is fine.
    ///
    /// EXPOSURE WINS TIES, AND WINS OUTRIGHT WHEN THE BLUR MEASURE IS NOT
    /// MEANINGFUL. Bad light is upstream of camera shake — a dark scene
    /// forces a longer exposure, which is what produced the shake — so more
    /// light fixes both and holding still fixes neither. Showing both
    /// warnings at once is not an option worth having: a capture screen with
    /// two instructions on it is a screen the user reads neither half of.
    public var primaryIssue: CaptureQualityIssue? {
        if !blur.isMeaningful || exposure.severity >= blur.severity {
            return exposure.issue
        }
        return blur.severity == .acceptable ? nil : .blurred
    }

    /// User-facing instruction for `primaryIssue`, `nil` when acceptable.
    ///
    /// THE GARMENT IS THE SUBJECT OF EVERY ONE OF THESE SENTENCES, never the
    /// person holding the phone (spec §2, `docs/14-frame-fit.md` §4, enforced
    /// by `scripts/check_ui_conventions.py`). "Hold the phone steady" is an
    /// instruction about the phone; anything that reads as a comment on the
    /// person is not acceptable copy here.
    public var guidance: String? {
        switch primaryIssue {
        case .blurred:
            return String(localized: "Hold the phone steady — the garment is out of focus.",
                          comment: "Scanner capture guidance when the frame is too soft to analyse")
        case .underexposed:
            return String(localized: "Too dark. Move somewhere brighter so the colour reads true.",
                          comment: "Scanner capture guidance when the frame is underexposed")
        case .overexposed:
            return String(localized: "Too much glare. Step out of direct light so the fabric keeps its detail.",
                          comment: "Scanner capture guidance when the frame is overexposed")
        case nil:
            return nil
        }
    }
}

// MARK: - The frame, reduced to something testable

/// An 8-bit greyscale image: the only thing the quality pass actually needs.
///
/// WHY THIS TYPE EXISTS RATHER THAN PASSING `CGImage` ALL THE WAY DOWN.
/// Two reasons, both load-bearing.
///
/// 1. It is `Sendable`, and `CGImage`/`CVPixelBuffer` are not. The plane is
///    the value that can cross an isolation boundary if a caller ever needs
///    it to; the image never has to.
/// 2. It is the shape the camera already has. A 420f capture buffer's first
///    plane IS this — luma, 8-bit, row-major — so the live-preview path can
///    build one by copying the Y plane with no colour conversion and no
///    CoreGraphics at all, while the still-photo path comes in through
///    `luminancePlane(from:)`. One analysis, two sources, and the expensive
///    conversion is not forced on the path that does not need it.
public struct LuminancePlane: Sendable, Equatable {
    public let samples: [UInt8]
    public let width: Int
    public let height: Int

    /// `nil` unless `samples.count == width * height` and both dimensions are
    /// positive — a mis-sized buffer is a caller bug that would otherwise
    /// read past the end of the array on the first row.
    public init?(samples: [UInt8], width: Int, height: Int) {
        guard width > 0, height > 0, samples.count == width * height else { return nil }
        self.samples = samples
        self.width = width
        self.height = height
    }
}

// MARK: - The pass itself

public enum CaptureQuality {

    // ---------------------------------------------------------------
    // Working resolution.
    // ---------------------------------------------------------------

    /// Longest edge the frame is reduced to before anything is measured.
    ///
    /// THE THRESHOLDS BELOW ARE ONLY MEANINGFUL AT A FIXED SCALE. Variance
    /// of the Laplacian is a measure of high-frequency energy per pixel, and
    /// high-frequency energy per pixel depends on how many pixels the same
    /// scene is spread across. Measured on one garment photograph from
    /// `brand/quiz-imagery`, varying only this constant: 378 at 256px, 203
    /// at 512px, 154 at 1024px — nearly 2.5× across the range, which is
    /// larger than the entire gap between "sharp" and "blocked" below.
    /// Fixing the working size is what turns "variance > N" from a number
    /// that happens to work on one device into a number that means the same
    /// thing everywhere.
    ///
    /// 512 rather than 256 or 1024: 512 keeps roughly 0.25 MP of detail,
    /// enough that a garment's weave and seams still register as edges,
    /// while a full pass over it is ~260k samples — a few milliseconds, so
    /// it can run on live preview frames rather than only on the still
    /// (spec §20 "Scanner shutter feedback: immediate").
    public static let analysisLongestEdge = 512

    // ---------------------------------------------------------------
    // Focus.
    // ---------------------------------------------------------------

    /// Below this the frame is soft enough to warn about but still worth
    /// analysing.
    ///
    /// MEASURED, NOT GUESSED, and the measurement is repeatable: this exact
    /// code was run over the **34 garment / editorial photographs** in
    /// `brand/quiz-imagery` (non-`_` PNGs — axis-pair frames and bakeoff
    /// candidates; the directory also holds 2 auxiliaries,
    /// `_reference-figure.png` and `_astra-mark.png`, which are not part of
    /// this calibration set). 1024 × 1536 editorial shots of real menswear —
    /// the only corpus of clothing photography in this repo — then over the
    /// same photographs blurred by a separable box blur of known radius. At
    /// `analysisLongestEdge`, in variance units:
    ///
    ///     sharp                        122 … 309   (median 178)
    ///     radius 1  (σ ≈ 1.4)           44 …  73
    ///     radius 2  (σ ≈ 2.4)           16 …  26
    ///     radius 3  (σ ≈ 3.5)            8 …  13
    ///
    /// The two bands are the two gaps in that table, and they are clean
    /// gaps rather than judgement calls:
    ///
    /// - 90 sits between the sharpest blurred photo (73) and the softest
    ///   sharp one (122). Every one of the 34 photographs passes; every one
    ///   of them warns as soon as it is blurred at all.
    /// - 30 sits between the softest radius-1 photo (44) and the sharpest
    ///   radius-2 one (26). Radius 1 is visibly soft but still analysable —
    ///   it warns. Radius 2 is where a care label stops being legible, which
    ///   is where P3-SCAN-03's OCR stops working, so that is where
    ///   auto-capture stops.
    ///
    /// WHAT THE CORPUS IS NOT. Those photographs are editorial studio shots,
    /// not handheld phone captures of a shirt on a bed: they are evenly lit,
    /// shallow-depth-of-field, and free of sensor noise. A phone capture has
    /// more micro-texture and should measure at least as high, so 90 is if
    /// anything a conservative floor — but "should" is the honest word, and
    /// the 20-photo manual test set in P3-SCAN-02's acceptance criteria is
    /// what would settle it.
    public static let blurWarningVariance: Double = 90

    /// Below this, auto-capture is blocked outright. See
    /// `blurWarningVariance` for the measured derivation of both numbers.
    public static let blurBlockingVariance: Double = 30

    /// Mean luminance below which the focus measurement is reported as not
    /// meaningful.
    ///
    /// Laplacian variance scales with the square of local contrast, and
    /// local contrast in a frame this dark is nearly all sensor noise. The
    /// value is deliberately the same as `underexposureBlockingMean`: the
    /// point at which the frame is too dark to analyse is exactly the point
    /// at which its focus score stops carrying information, and having two
    /// separate numbers for one physical fact would let them drift apart.
    public static let blurMeasurementFloorLuminance: Double = 0.16

    // ---------------------------------------------------------------
    // Exposure.
    //
    // EVERY NUMBER BELOW IS IN THE sRGB-ENCODED DOMAIN, because that is what
    // the samples are. It matters: photographic exposure is reasoned about
    // in linear light against an 18% grey card, but 18% linear reflectance
    // encodes to 0.18^(1/2.2) ≈ 0.46, not 0.18. A threshold of "mean < 0.18"
    // written without noticing that would reject a frame roughly one and a
    // half stops BRIGHTER than a correct exposure. Each constant states the
    // stop offset it corresponds to so the arithmetic can be re-checked.
    //
    // CALIBRATED AGAINST THE SAME 34-PHOTOGRAPH GARMENT CORPUS as the focus
    // thresholds (`brand/quiz-imagery` non-`_` PNGs; see blur comments above —
    // not the 36-file directory total that includes two auxiliaries). Every
    // one of them measures a mean between 0.331 and 0.549, a clipped fraction
    // of at most 0.0001, and a crushed fraction of at most 0.014 — so the
    // acceptable band below (0.28 … 0.80 mean) contains the whole corpus with
    // margin at both ends, and no threshold here is set so tight that ordinary
    // garment photography trips it.
    // ---------------------------------------------------------------

    /// The 18% grey metering reference, sRGB-encoded: `0.18 ^ (1/2.2)`.
    /// Not used as a threshold — it is the anchor the thresholds are
    /// measured from, and is public so a test can assert the conversion
    /// rather than trusting a comment.
    public static let midGreyEncoded: Double = 0.4587

    /// Mean encoded luminance below which the frame is warned about.
    /// `0.28 ^ 2.2 = 0.061` linear, which is `log2(0.061 / 0.18) ≈ -1.6`
    /// stops under the metering reference. At about a stop and a half under,
    /// a mid-tone garment colour has lost roughly a third of its encoded
    /// range and the dominant-colour hint starts reading darker than the
    /// garment is.
    public static let underexposureWarningMean: Double = 0.28

    /// Mean encoded luminance below which auto-capture is blocked.
    /// `0.16 ^ 2.2 = 0.018` linear, `≈ -3.3` stops. Three stops under is
    /// past the point where the colour hint is wrong rather than merely
    /// dark, and it is also where the focus measurement stops meaning
    /// anything (see `blurMeasurementFloorLuminance`).
    public static let underexposureBlockingMean: Double = 0.16

    /// Fraction of crushed samples that warns on its own even when the mean
    /// looks acceptable. This is the backlit case: a garment held up against
    /// a window meters bright overall while the garment itself is a
    /// silhouette. A third of the frame at or below `crushedSample` is far
    /// more than any real shadow on an evenly-lit garment.
    public static let crushedShadowWarningFraction: Double = 0.35

    /// Fraction of crushed samples that blocks. At 60% of the frame carrying
    /// no shadow detail there is not enough garment left to analyse whatever
    /// the mean says.
    public static let crushedShadowBlockingFraction: Double = 0.60

    /// Mean encoded luminance above which the frame is warned about.
    /// `0.80 ^ 2.2 = 0.61` linear, `≈ +1.8` stops over the reference.
    public static let overexposureWarningMean: Double = 0.80

    /// Fraction of clipped samples that warns. A clipped pixel has no colour
    /// left in it at all, so this is the number that protects the
    /// dominant-colour hint: 12% of the frame is about what a specular band
    /// across a satin or leather surface covers.
    public static let clippedHighlightWarningFraction: Double = 0.12

    /// Blocking over-exposure requires BOTH a large clipped fraction AND a
    /// bright overall frame, and this is the most important qualification in
    /// this file.
    ///
    /// A garment photographed on a white duvet or against a white wall — the
    /// two most likely surfaces in a bedroom — legitimately puts a large
    /// fraction of near-white pixels in the frame while the garment itself
    /// is perfectly exposed. A histogram alone cannot tell that apart from a
    /// blown frame, because the difference is not in the histogram, it is in
    /// WHERE the bright pixels are. Blocking on the clipped fraction alone
    /// would refuse to photograph a black shirt on a white bed, which is a
    /// completely ordinary thing to do and a very bad first experience.
    ///
    /// So the blocking rule demands the whole frame be blown, not just the
    /// background. The honest fix is not a better threshold: it is measuring
    /// exposure over the garment region only, which is what
    /// `GarmentRegionDetecting` below exists to make possible.
    public static let clippedHighlightBlockingFraction: Double = 0.35

    /// Companion to `clippedHighlightBlockingFraction`. `0.75 ^ 2.2 = 0.53`
    /// linear, `≈ +1.6` stops: bright enough that the frame as a whole, not
    /// just its backdrop, is over.
    public static let overexposureBlockingMean: Double = 0.75

    /// A sample at or above this carries no usable colour. 250 rather than
    /// 255 because the ISP's tone curve and JPEG quantisation both round
    /// values near the ceiling — a genuinely clipped pixel routinely comes
    /// back as 251–254, and a test for exactly 255 would find almost none of
    /// them.
    public static let clippedSample: UInt8 = 250

    /// A sample at or below this carries no usable colour, for the same
    /// reason in the other direction (black level plus noise floor).
    public static let crushedSample: UInt8 = 5
}

// MARK: - Measurement

extension CaptureQuality {

    /// The whole of spec §12 step 1 for one frame.
    ///
    /// Order matters: exposure is measured first because the focus verdict
    /// depends on it (a frame below `blurMeasurementFloorLuminance` has no
    /// meaningful focus score, and saying so is more useful than reporting a
    /// number that is really a measurement of noise).
    public static func evaluate(_ plane: LuminancePlane) -> CaptureQualityVerdict {
        let exposure = measureExposure(plane)
        let blur = measureBlur(plane, meanLuminance: exposure.meanLuminance)
        return CaptureQualityVerdict(blur: blur, exposure: exposure)
    }

    /// Convenience for the still-photo path. `nil` only when the image
    /// cannot be rendered into a greyscale bitmap at all, which in practice
    /// means a zero-sized or otherwise degenerate `CGImage`.
    ///
    /// Synchronous and nonisolated on purpose — see the concurrency note in
    /// this file's header. The `CGImage` stays in the caller's isolation
    /// domain; only the `Sendable` verdict comes back out.
    public static func evaluate(_ image: CGImage) -> CaptureQualityVerdict? {
        guard let plane = luminancePlane(from: image) else { return nil }
        return evaluate(plane)
    }

    /// Renders a `CGImage` down to an 8-bit greyscale plane at
    /// `longestEdge`.
    ///
    /// NEVER UPSCALES. An image smaller than the target is measured at its
    /// own size: upsampling would interpolate new samples between real ones,
    /// which lowers Laplacian variance and would make a small sharp image
    /// read as a blurred one. A frame from the camera is always far larger
    /// than 512px, so this only affects synthesised inputs and tests — where
    /// getting it wrong would have silently invalidated every fixture.
    ///
    /// Interpolation is `.medium` (area-averaging) rather than `.none`.
    /// Point-sampling a 4032px frame down to 512 aliases high-frequency
    /// texture back into the low frequencies, which would make an
    /// out-of-focus but finely-textured garment measure as sharp — the exact
    /// failure this pass exists to catch.
    public static func luminancePlane(from image: CGImage, longestEdge: Int = analysisLongestEdge) -> LuminancePlane? {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0, longestEdge > 0 else { return nil }

        let scale = min(1, Double(longestEdge) / Double(max(sourceWidth, sourceHeight)))
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let base = context.data else { return nil }
        let bytesPerRow = context.bytesPerRow
        // Copied row by row against the context's OWN stride rather than the
        // requested one. CoreGraphics is free to pad rows for alignment, and
        // a padded buffer read as if it were tightly packed produces an
        // image that shears progressively down the frame — which looks like
        // a plausible measurement rather than an obvious bug.
        var samples = [UInt8](repeating: 0, count: width * height)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            let rowStart = bytes.advanced(by: row * bytesPerRow)
            samples.withUnsafeMutableBufferPointer { destination in
                guard let destinationBase = destination.baseAddress else { return }
                destinationBase.advanced(by: row * width).update(from: rowStart, count: width)
            }
        }
        return LuminancePlane(samples: samples, width: width, height: height)
    }
}

extension CaptureQuality {

    /// Variance of the Laplacian, the standard focus measure.
    ///
    /// The kernel is the 4-neighbour discrete Laplacian
    /// `[[0, 1, 0], [1, -4, 1], [0, 1, 0]]`: a second-derivative operator,
    /// so it responds to edges and not to flat areas or to smooth gradients
    /// (a first-derivative measure would score an evenly-lit wall as
    /// textured just for being brighter on one side). Blurring attenuates
    /// high spatial frequencies, the response collapses, and its variance
    /// collapses with it — that collapse is the measurement.
    ///
    /// WHAT THIS MEASURE CANNOT DO, stated plainly because a single global
    /// threshold is scene-dependent and pretending otherwise is how a
    /// capture screen ends up nagging about a photo that is fine:
    ///
    /// - Edge density is part of the score. A check shirt in soft focus can
    ///   out-score a plain jersey tee in perfect focus, because the check
    ///   simply has more edges. The threshold is set low enough to accept
    ///   the plain tee, which means the check shirt has to be quite badly
    ///   blurred before it trips.
    /// - It measures the WHOLE frame, so a sharp background behind a soft
    ///   garment scores as sharp. This is the single biggest weakness and it
    ///   is the one `GarmentRegionDetecting` fixes: restricting the
    ///   measurement to the garment region turns a whole-frame average into
    ///   a statement about the subject.
    /// - It cannot separate motion blur from focus error, which is fine —
    ///   the user's remedy ("hold steady, tap to focus") is the same either
    ///   way — but it also cannot separate either of those from a genuinely
    ///   soft, flat, low-texture fabric.
    ///
    /// The better long-term answer is comparative rather than absolute: the
    /// capture layer sees a stream, so it can keep the sharpest frame of the
    /// last N rather than judging each one against a constant. That belongs
    /// in the camera layer, which is why this returns the raw variance
    /// alongside the verdict instead of only a severity.
    static func measureBlur(_ plane: LuminancePlane, meanLuminance: Double) -> BlurAssessment {
        let width = plane.width
        let height = plane.height
        guard width >= 3, height >= 3 else {
            // Nothing to differentiate: an image narrower than the kernel has
            // no interior pixels at all. Reported as "not meaningful" rather
            // than as sharp or blurred, both of which would be inventions.
            return BlurAssessment(laplacianVariance: 0, severity: .acceptable, isMeaningful: false)
        }

        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0
        plane.samples.withUnsafeBufferPointer { samples in
            for row in 1..<(height - 1) {
                let rowStart = row * width
                for column in 1..<(width - 1) {
                    let index = rowStart + column
                    let response = 4 * Double(samples[index])
                        - Double(samples[index - 1])
                        - Double(samples[index + 1])
                        - Double(samples[index - width])
                        - Double(samples[index + width])
                    sum += response
                    sumOfSquares += response * response
                    count += 1
                }
            }
        }

        guard count > 0 else {
            return BlurAssessment(laplacianVariance: 0, severity: .acceptable, isMeaningful: false)
        }
        let mean = sum / Double(count)
        // Population variance, and `max(0,)` because the shift-free form
        // E[x²] - E[x]² can land a hair below zero on a perfectly flat frame
        // through floating-point cancellation alone.
        let variance = max(0, sumOfSquares / Double(count) - mean * mean)

        let isMeaningful = meanLuminance >= blurMeasurementFloorLuminance
        guard isMeaningful else {
            return BlurAssessment(laplacianVariance: variance, severity: .acceptable, isMeaningful: false)
        }

        let severity: CaptureQualitySeverity
        if variance < blurBlockingVariance {
            severity = .blocking
        } else if variance < blurWarningVariance {
            severity = .warning
        } else {
            severity = .acceptable
        }
        return BlurAssessment(laplacianVariance: variance, severity: severity, isMeaningful: true)
    }
}

extension CaptureQuality {

    /// Under- and over-exposure from the luminance histogram.
    ///
    /// Three statistics rather than one, because they fail independently:
    /// the mean catches a globally dark or globally blown frame, the crushed
    /// fraction catches a backlit garment that meters bright, and the
    /// clipped fraction catches a specular highlight burning a hole in an
    /// otherwise well-exposed one. A mean-only test misses the last two, and
    /// they are the two that damage the colour hint most.
    static func measureExposure(_ plane: LuminancePlane) -> ExposureAssessment {
        var total = 0
        var clipped = 0
        var crushed = 0
        for sample in plane.samples {
            total += Int(sample)
            if sample >= clippedSample { clipped += 1 }
            if sample <= crushedSample { crushed += 1 }
        }
        let sampleCount = Double(plane.samples.count)
        guard sampleCount > 0 else {
            return ExposureAssessment(
                meanLuminance: 0,
                clippedHighlightFraction: 0,
                crushedShadowFraction: 0,
                severity: .acceptable,
                issue: nil
            )
        }

        let mean = Double(total) / sampleCount / 255
        let clippedFraction = Double(clipped) / sampleCount
        let crushedFraction = Double(crushed) / sampleCount

        // UNDER BEATS OVER WHEN BOTH SOMEHOW TRIP. A frame cannot really be
        // both, but a high-contrast one can trip both fractions at once, and
        // darkness is the condition that also invalidates the focus
        // measurement — so it is the one worth naming.
        let severity: CaptureQualitySeverity
        let issue: CaptureQualityIssue?
        if mean < underexposureBlockingMean || crushedFraction > crushedShadowBlockingFraction {
            severity = .blocking
            issue = .underexposed
        } else if clippedFraction > clippedHighlightBlockingFraction && mean > overexposureBlockingMean {
            severity = .blocking
            issue = .overexposed
        } else if mean < underexposureWarningMean || crushedFraction > crushedShadowWarningFraction {
            severity = .warning
            issue = .underexposed
        } else if mean > overexposureWarningMean || clippedFraction > clippedHighlightWarningFraction {
            severity = .warning
            issue = .overexposed
        } else {
            severity = .acceptable
            issue = nil
        }

        return ExposureAssessment(
            meanLuminance: mean,
            clippedHighlightFraction: clippedFraction,
            crushedShadowFraction: crushedFraction,
            severity: severity,
            issue: issue
        )
    }
}

// MARK: - The segmentation seam (spec §12 steps 2–3)

/// Where the garment is in the frame, in normalized image coordinates.
///
/// Coordinates follow `CGImage`: origin top-left, y increasing downward,
/// both axes 0...1. Vision reports normalized rects with the origin at the
/// BOTTOM-left, so the adapter that wraps a Vision request owns that flip.
/// Saying which convention this is in the type's own documentation is not
/// pedantry — a silently flipped rect crops the hem instead of the collar
/// and every downstream number stays plausible.
public struct GarmentRegion: Sendable, Equatable {
    /// The garment's bounding box. Callers crop to this before extracting
    /// colour, and future work restricts the quality measurements above to
    /// it as well.
    public let boundingBox: CGRect
    /// 0...1. The camera layer decides what is good enough to act on; the
    /// server-side fallback (P3-SCAN-10) exists for when it is not.
    public let confidence: Double

    public init(boundingBox: CGRect, confidence: Double) {
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// Spec §12 steps 2–3: "Detect likely garment region" and "Segment
/// foreground where supported".
///
/// THIS IS A SEAM. The live Vision adapter is
/// `LiveVisionGarmentRegionDetector` (foreground instance mask, saliency
/// fallback). The untestable half stays there on purpose: Vision needs a
/// real garment photograph, and P3-SCAN-02's acceptance criterion
/// ("produces a usable foreground mask for a garment photographed on a
/// neutral background") is a human looking at a cutout. Unit tests inject
/// `MockGarmentRegionDetector` and assert the consumers
/// (`DeviceHintsExtraction` → `DominantColorExtraction`) honour the region.
///
/// What is deliberately NOT wired yet:
///
/// 1. **Live capture quality.** Restricting blur/exposure to the garment
///    would retire the white-duvet false positive that
///    `clippedHighlightBlockingFraction` is lenient about — but running
///    Vision on the ~10 Hz quality stream is not safe for the capture
///    budget. Whole-frame measurement stays until review owns a still.
/// 2. **Cutout preview** on the review screen (spec §6.16 / P3-SCAN-09).
///
/// What IS wired: `DeviceHintsExtraction` optionally takes a detector and
/// passes its region into `DominantColorExtraction.extract(from:garmentRegion:)`.
///
/// `Sendable` with a synchronous requirement, matching the rest of this
/// file: the implementation runs wherever the caller already is, so the
/// non-`Sendable` `CGImage` never crosses an isolation boundary.
public protocol GarmentRegionDetecting: Sendable {
    /// `nil` when nothing garment-shaped was found — which is a real
    /// outcome, not an error, and is distinct from a low-confidence region.
    func detectGarmentRegion(in image: CGImage) throws -> GarmentRegion?
}

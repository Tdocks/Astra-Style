//
//  CaptureQualityTests.swift
//  AstraStyleTests
//
//  Spec §12 "Device-side" step 1, "Detect blur and exposure", and the half
//  of P3-SCAN-02 that a machine can settle.
//
//  WHAT THESE TESTS DO NOT CLAIM. P3-SCAN-02's acceptance criteria are "a
//  clearly blurred photo is flagged before upload in ≥90% of a manual test
//  set of 20 sample photos" and "segmentation produces a usable foreground
//  mask". Neither is automatable: the first needs twenty real photographs
//  and a human to agree which are blurred, the second needs Vision and a
//  human to look at a cutout. Nothing below pretends otherwise. What is
//  asserted instead is everything the manual test would be worthless
//  without — that the measure responds monotonically to blur, that the
//  thresholds put sharp, soft and blurred frames in the bands the constants
//  say they do, that the exposure statistics are computed in the domain the
//  thresholds are stated in, and that the verdict names the problem the user
//  can actually act on.
//
//  THE FIXTURES ARE NOT PHOTOGRAPHS AND THE ABSOLUTE NUMBERS ARE NOT
//  COMPARABLE TO ONE. A synthesised checkerboard measures roughly fifteen
//  times the Laplacian variance of a real garment photograph at the same
//  size (2488 versus ~178 median), because every pixel of it is either on an
//  edge or next to one. The thresholds in `CaptureQuality` were calibrated
//  against the 34 real garment photographs in `brand/quiz-imagery`, not
//  against these fixtures; what these fixtures verify is that the code
//  applies those thresholds correctly and that blurring collapses the
//  measurement the way the theory says. The checkerboard's own blur ladder
//  happens to straddle all three bands, which is what makes it useful here.
//

import CoreGraphics
import Foundation
import Testing
@testable import AstraStyle

@Suite("CaptureQuality — focus (spec §12 step 1)")
struct CaptureQualityFocusTests {

    /// The ladder the band assertions below stand on. Values measured with
    /// this code: 2488, 50.5, 10.7, 4.0.
    private func checkerboard(blurRadius: Int) throws -> CGImage {
        let board = try #require(ScannerImageFixtures.checkerboard(width: 512, height: 512, cell: 64))
        return try #require(ScannerImageFixtures.blurred(board, radius: blurRadius))
    }

    @Test("Blurring an image strictly lowers its focus score at every step, which is the property the whole measure rests on — if it were not monotonic no single threshold could mean anything")
    func blurLowersTheScoreMonotonically() throws {
        var previous = Double.greatestFiniteMagnitude
        for radius in [0, 1, 2, 3] {
            let image = try checkerboard(blurRadius: radius)
            let verdict = try #require(CaptureQuality.evaluate(image))
            #expect(verdict.blur.laplacianVariance < previous)
            previous = verdict.blur.laplacianVariance
        }
    }

    @Test("A sharp frame is acceptable and lets auto-capture fire, because the cost of a false blur warning is the user losing the shot he was lining up")
    func sharpFrameIsAcceptable() throws {
        let verdict = try #require(CaptureQuality.evaluate(try checkerboard(blurRadius: 0)))
        #expect(verdict.blur.severity == .acceptable)
        #expect(verdict.blur.isMeaningful)
        #expect(verdict.blur.laplacianVariance > CaptureQuality.blurWarningVariance)
        #expect(verdict.primaryIssue == nil)
        #expect(verdict.guidance == nil)
        #expect(verdict.allowsAutoCapture)
    }

    @Test("A mildly soft frame warns but still allows capture — a warning is advice, and refusing to take a photograph that would analyse acceptably is worse than analysing it")
    func softFrameWarnsWithoutBlocking() throws {
        let verdict = try #require(CaptureQuality.evaluate(try checkerboard(blurRadius: 1)))
        #expect(verdict.blur.severity == .warning)
        #expect(verdict.primaryIssue == .blurred)
        #expect(verdict.guidance != nil)
        #expect(verdict.allowsAutoCapture)
    }

    @Test("A clearly blurred frame blocks auto-capture, because at this level a care label is no longer legible and the analysis it would feed is worth less than a retake")
    func blurredFrameBlocks() throws {
        let verdict = try #require(CaptureQuality.evaluate(try checkerboard(blurRadius: 2)))
        #expect(verdict.blur.severity == .blocking)
        #expect(verdict.blur.laplacianVariance < CaptureQuality.blurBlockingVariance)
        #expect(verdict.primaryIssue == .blurred)
        #expect(verdict.allowsAutoCapture == false)
    }

    @Test("The blocking threshold sits below the warning threshold, so the three bands cannot silently invert if either constant is retuned")
    func thresholdsAreOrdered() {
        #expect(CaptureQuality.blurBlockingVariance < CaptureQuality.blurWarningVariance)
        #expect(CaptureQuality.blurBlockingVariance > 0)
    }

    @Test("A flat frame with no detail at all scores zero rather than crashing or producing a negative variance, which floating-point cancellation makes a real possibility")
    func flatFrameScoresZero() throws {
        let image = try #require(ScannerImageFixtures.solid(width: 128, height: 128, red: 128, green: 128, blue: 128))
        let verdict = try #require(CaptureQuality.evaluate(image))
        #expect(verdict.blur.laplacianVariance >= 0)
        #expect(verdict.blur.laplacianVariance < 1)
        #expect(verdict.blur.severity == .blocking)
    }

    @Test("An image smaller than the analysis size is measured at its own size rather than upscaled, because interpolating new samples would lower the variance and make a small sharp image read as blurred")
    func smallImagesAreNotUpscaled() throws {
        let image = try #require(ScannerImageFixtures.checkerboard(width: 96, height: 64, cell: 8))
        let plane = try #require(CaptureQuality.luminancePlane(from: image))
        #expect(plane.width == 96)
        #expect(plane.height == 64)
    }

    @Test("A frame narrower than the convolution kernel reports no meaningful measurement instead of inventing one, since it has no interior pixels to differentiate")
    func degenerateFrameIsNotMeaningful() throws {
        let plane = try #require(LuminancePlane(samples: [10, 20, 30, 40], width: 2, height: 2))
        let assessment = CaptureQuality.measureBlur(plane, meanLuminance: 0.5)
        #expect(assessment.isMeaningful == false)
        #expect(assessment.severity == .acceptable)
    }
}

@Suite("CaptureQuality — exposure (spec §12 step 1)")
struct CaptureQualityExposureTests {

    private func flat(_ value: UInt8) throws -> CaptureQualityVerdict {
        let image = try #require(ScannerImageFixtures.solid(width: 256, height: 256, red: value, green: value, blue: value))
        return try #require(CaptureQuality.evaluate(image))
    }

    @Test("Mean luminance is reported in the sRGB-encoded domain the thresholds are written in — a mid-grey frame reads about 0.5, not the 0.22 linear light it corresponds to")
    func meanIsEncodedNotLinear() throws {
        let verdict = try flat(128)
        #expect(abs(verdict.exposure.meanLuminance - 0.502) < 0.01)
        #expect(verdict.exposure.severity == .acceptable)
        #expect(verdict.exposure.issue == nil)
    }

    @Test("The 18% grey anchor the exposure thresholds are measured from really is 0.18 encoded, so the stop offsets quoted on each constant can be checked rather than believed")
    func midGreyAnchorIsCorrect() {
        #expect(abs(CaptureQuality.midGreyEncoded - pow(0.18, 1.0 / 2.2)) < 0.001)
    }

    @Test("A frame about a stop and a half under warns: the garment is still visible but its colour is already reading darker than the cloth is, and colour is what the hint carries")
    func slightlyDarkFrameWarns() throws {
        let verdict = try flat(60)
        #expect(verdict.exposure.severity == .warning)
        #expect(verdict.exposure.issue == .underexposed)
    }

    @Test("A frame more than three stops under blocks, and its focus score is marked not meaningful — telling a man to hold steady in the dark sends him to fix the wrong thing")
    func darkFrameBlocksAndInvalidatesFocus() throws {
        let verdict = try flat(20)
        #expect(verdict.exposure.severity == .blocking)
        #expect(verdict.exposure.issue == .underexposed)
        #expect(verdict.blur.isMeaningful == false)
        #expect(verdict.primaryIssue == .underexposed)
        #expect(verdict.allowsAutoCapture == false)
    }

    @Test("A frame about two stops over warns on its mean alone, before anything has clipped")
    func brightFrameWarns() throws {
        let verdict = try flat(210)
        #expect(verdict.exposure.issue == .overexposed)
        #expect(verdict.exposure.severity == .warning)
        #expect(verdict.exposure.clippedHighlightFraction == 0)
    }

    @Test("A wholly blown frame blocks: every pixel is clipped, so there is no colour left in it for the dominant-colour hint to be about")
    func blownFrameBlocks() throws {
        let verdict = try flat(253)
        #expect(verdict.exposure.severity == .blocking)
        #expect(verdict.exposure.issue == .overexposed)
        #expect(verdict.exposure.clippedHighlightFraction > 0.99)
    }

    @Test("A dark garment on a bright white backdrop is ACCEPTABLE, which is the false positive this whole design is arranged around — photographing clothes on a white bed is the most ordinary thing a user will do")
    func darkGarmentOnWhiteBackdropIsAccepted() throws {
        let image = try #require(ScannerImageFixtures.verticalSplit(
            width: 512,
            height: 512,
            left: ScannerImageFixtures.RGB(240, 240, 240),
            right: ScannerImageFixtures.RGB(30, 34, 60),
            leftFraction: 0.5
        ))
        let verdict = try #require(CaptureQuality.evaluate(image))
        #expect(verdict.exposure.severity == .acceptable)
        #expect(verdict.exposure.issue == nil)
    }

    @Test("The same scene with a genuinely blown backdrop warns but still does not block, because the blocking rule additionally requires the frame as a whole to be over — half a frame of white is a bedspread, not a bad exposure")
    func blownBackdropWarnsButDoesNotBlock() throws {
        let image = try #require(ScannerImageFixtures.verticalSplit(
            width: 512,
            height: 512,
            left: ScannerImageFixtures.RGB(253, 253, 253),
            right: ScannerImageFixtures.RGB(30, 34, 60),
            leftFraction: 0.5
        ))
        let verdict = try #require(CaptureQuality.evaluate(image))
        #expect(verdict.exposure.clippedHighlightFraction > CaptureQuality.clippedHighlightWarningFraction)
        #expect(verdict.exposure.severity == .warning)
        #expect(verdict.allowsAutoCapture)
    }

    @Test("A backlit garment warns on its crushed fraction even though its mean is comfortably bright — a mean-only test would pass this frame, and the garment in it is a silhouette")
    func backlitGarmentWarnsDespiteBrightMean() throws {
        let image = try #require(ScannerImageFixtures.verticalSplit(
            width: 512,
            height: 512,
            left: ScannerImageFixtures.RGB(240, 240, 240),
            right: ScannerImageFixtures.RGB(3, 3, 3),
            leftFraction: 0.55
        ))
        let verdict = try #require(CaptureQuality.evaluate(image))
        #expect(verdict.exposure.meanLuminance > CaptureQuality.underexposureWarningMean)
        #expect(verdict.exposure.crushedShadowFraction > CaptureQuality.crushedShadowWarningFraction)
        #expect(verdict.exposure.severity == .warning)
        #expect(verdict.exposure.issue == .underexposed)
    }

    @Test("A garment that is mostly silhouette blocks on the crushed fraction alone, with a mean that is not itself blocking")
    func heavilyBacklitGarmentBlocks() throws {
        let image = try #require(ScannerImageFixtures.verticalSplit(
            width: 512,
            height: 512,
            left: ScannerImageFixtures.RGB(240, 240, 240),
            right: ScannerImageFixtures.RGB(3, 3, 3),
            leftFraction: 0.3
        ))
        let verdict = try #require(CaptureQuality.evaluate(image))
        #expect(verdict.exposure.meanLuminance > CaptureQuality.underexposureBlockingMean)
        #expect(verdict.exposure.crushedShadowFraction > CaptureQuality.crushedShadowBlockingFraction)
        #expect(verdict.exposure.severity == .blocking)
    }
}

@Suite("CaptureQuality — the verdict the capture screen reads")
struct CaptureQualityVerdictTests {

    private func verdict(blur: CaptureQualitySeverity, exposure: CaptureQualitySeverity,
                         issue: CaptureQualityIssue?, blurIsMeaningful: Bool = true) -> CaptureQualityVerdict {
        CaptureQualityVerdict(
            blur: BlurAssessment(laplacianVariance: 0, severity: blur, isMeaningful: blurIsMeaningful),
            exposure: ExposureAssessment(
                meanLuminance: 0.4,
                clippedHighlightFraction: 0,
                crushedShadowFraction: 0,
                severity: exposure,
                issue: issue
            )
        )
    }

    @Test("A dark AND soft frame reports the light, not the shake: bad light is what forced the long exposure that caused the shake, so 'move somewhere brighter' fixes both and 'hold still' fixes neither")
    func exposureIsReportedAheadOfBlurWhenBothTrip() {
        let both = verdict(blur: .blocking, exposure: .blocking, issue: .underexposed, blurIsMeaningful: false)
        #expect(both.primaryIssue == .underexposed)
    }

    @Test("When the focus measurement is not meaningful it cannot become the reported issue, even if its severity is higher — a number computed from noise must not drive the instruction on screen")
    func meaninglessBlurNeverWins() {
        let dark = verdict(blur: .blocking, exposure: .warning, issue: .underexposed, blurIsMeaningful: false)
        #expect(dark.primaryIssue == .underexposed)
        #expect(dark.severity == .blocking)
    }

    @Test("With acceptable light, a soft frame reports the softness")
    func blurIsReportedWhenLightIsFine() {
        let soft = verdict(blur: .warning, exposure: .acceptable, issue: nil)
        #expect(soft.primaryIssue == .blurred)
        #expect(soft.severity == .warning)
        #expect(soft.allowsAutoCapture)
    }

    @Test("A frame with nothing wrong with it has no issue and no guidance string, so the capture screen shows nothing rather than reassuring copy nobody asked for")
    func acceptableFrameSaysNothing() {
        let clean = verdict(blur: .acceptable, exposure: .acceptable, issue: nil)
        #expect(clean.primaryIssue == nil)
        #expect(clean.guidance == nil)
        #expect(clean.severity == .acceptable)
        #expect(clean.allowsAutoCapture)
    }

    @Test("Every issue the verdict can name has guidance to go with it — a warning state with no instruction is a dead indicator, which spec §22's acceptance bar rules out by name")
    func everyIssueHasGuidance() {
        for issue in CaptureQualityIssue.allCases {
            let subject = issue == .blurred
                ? verdict(blur: .warning, exposure: .acceptable, issue: nil)
                : verdict(blur: .acceptable, exposure: .warning, issue: issue)
            #expect(subject.primaryIssue == issue)
            #expect(subject.guidance?.isEmpty == false)
        }
    }

    @Test("Severity compares in the order the type declares, since the verdict combines two dimensions with max() and would silently invert if the ordering were wrong")
    func severityOrdering() {
        #expect(CaptureQualitySeverity.acceptable < .warning)
        #expect(CaptureQualitySeverity.warning < .blocking)
        #expect(max(CaptureQualitySeverity.warning, .blocking) == .blocking)
    }
}

@Suite("LuminancePlane — the Sendable frame")
struct LuminancePlaneTests {

    @Test("A plane whose sample count does not match its dimensions is refused at construction rather than read past the end of its own buffer later")
    func mismatchedBufferIsRejected() {
        #expect(LuminancePlane(samples: [1, 2, 3], width: 2, height: 2) == nil)
        #expect(LuminancePlane(samples: [], width: 0, height: 0) == nil)
        #expect(LuminancePlane(samples: [1, 2, 3, 4], width: 2, height: 2) != nil)
    }

    @Test("A rendered plane keeps the source aspect ratio and caps its longest edge, which is what makes the focus thresholds comparable between a portrait and a landscape capture")
    func renderedPlaneIsCappedAndProportional() throws {
        let image = try #require(ScannerImageFixtures.checkerboard(width: 2048, height: 1024, cell: 32))
        let plane = try #require(CaptureQuality.luminancePlane(from: image))
        #expect(plane.width == CaptureQuality.analysisLongestEdge)
        #expect(plane.height == CaptureQuality.analysisLongestEdge / 2)
        #expect(plane.samples.count == plane.width * plane.height)
    }
}

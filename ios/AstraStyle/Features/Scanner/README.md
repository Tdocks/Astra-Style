# Scanner

Owns garment capture and the device-side half of the computer vision pipeline (spec §6.16, §12).

> **Status:** groundwork only. This directory has **no** `Views/` or `ViewModels/`. Camera UI, capture modes, guidance overlays, and the review screen are **not built**. Trust `docs/03-progress.md` (`P3-SCAN-*`) for ticket status.

## What this module will own (when built)

- Camera capture UI for the modes in §6.16: single item, batch closet scan, receipt/label, full outfit mirror photo.
- Camera guidance: edge detection, lighting indicator, background quality, blur warning, optional auto capture.
- The review screen: segmented cutout, suggested metadata with per-field confidence indicators, user correction — every inferred field must remain editable and low-confidence fields must be visibly marked (§12 "User verification").
- Device-side preprocessing before upload: blur/exposure detection, garment region detection, on-device segmentation where supported, OCR of label text, dominant color extraction, resize/compress, metadata stripping (§12 "Device-side").

## Governing spec sections

§6.16 (screen spec), §12 (full CV pipeline, device- and server-side), §7 (camera permission requested only when scanning; new scans can be captured and queued offline), §14 (`POST /closet/analyze-item`, `POST /closet/batch-analyze`), §20 (target: item analysis under 8 seconds).

## What already exists

**In this module (`Services/` only):**

- `CaptureQuality.swift` — blur + exposure verdicts; thresholds measured against `brand/quiz-imagery` garment photographs.
- `CapturePreparation.swift` — resize to the §12 / `docs/08` upload cap, JPEG re-encode, metadata stripped by construction.
- `DominantColorExtraction.swift` — centre-region prior + quantised palette.
- `GarmentRegionDetecting` protocol seam — deliberately unimplemented (needs a live Vision request against a real garment photo).

**Elsewhere to build against:**

- `Domain/Repositories/ClosetRepository.swift` — `analyzeItem` / `batchAnalyzeItems`.
- `Domain/Models/ClosetItemAnalysisResult.swift` — confidence-scored suggestions the future review screen binds to.
- `Core/Networking/Live/LiveClosetRepository.swift` — upload-then-analyze flow (Storage path, then Edge Function). The `closet` Edge Function is not deployed yet.
- `Core/Mocks/MockClosetRepository.swift` — believable suggestions for previewing a review screen without a camera.
- Guest mode: `analyzeItem` / `batchAnalyzeItems` throw a validation error with zero network I/O; the scan entry point is gated before the modal opens for guests.

## Tickets

Filled in by the **P3-SCAN** tickets in `docs/02-task-breakdown.md`. Recommended next server slice: `POST /closet/analyze-item` (see `HANDOFF.md` §12.2).

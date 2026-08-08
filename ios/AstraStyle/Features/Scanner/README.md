# Scanner

Owns garment capture and the device-side half of the computer vision pipeline (spec §6.16, §12).

> **Status:** single-item capture + review + upload/analyze/save ship. Vision garment-region + OCR adapters exist behind protocols (Partial — manual criteria unrun). **Batch closet scan now has a UI** (`ScannerBatchCaptureView` + `ScannerBatchViewModel`, multi-select import → one batch analysis → the existing review screen walked one garment at a time); receipt/mirror modes are still **not** built. Trust `docs/03-progress.md` (`P3-SCAN-*`).

## What this module owns today

- Single-item capture UI: preview, framing guide, quality guidance, shutter, Photos import.
- Review UI: editable suggestions, low-confidence footnotes, save to closet.
- Upload → analyze orchestration (`ScannerReviewViewModel`) via `ClosetRepository.uploadCapturedImage` + `analyzeItem`.
- Protocol-fronted camera session (`CaptureSessionControlling`) with live + mock adapters.
- Device-side preprocessing as pure / protocol-fronted services:
  - blur/exposure (`CaptureQuality`)
  - resize/compress/metadata-strip (`CapturePreparation`)
  - dominant color (`DominantColorExtraction`)
  - garment region seam + live Vision adapter (`GarmentRegionDetecting` / `LiveVisionGarmentRegionDetector` / `MockGarmentRegionDetector`)
  - label OCR seam + live Vision adapter (`LabelTextRecognizing` / `LiveVisionLabelTextRecognizer` / `MockLabelTextRecognizer`)
  - composition into `GarmentDeviceHints` (`DeviceHintsExtraction`)
- `CaptureDraftStore` for capture→review handoff by UUID.

## What is deliberately not here yet

- Region-restricted live capture quality on the ~10 Hz preview path (not safe for the capture budget — documented Partial on `P3-SCAN-02`).
- On-device manual verification of segmentation / OCR acceptance criteria.
- Receipt / mirror capture modes (`P3-SCAN-12`).
- Batch capture from the *camera*. `ScannerRoute.batchCloset` is import-only by design: a phone camera used twenty times in a row is a worse tool for "sit down with a pile of clothes" than a roll the user has already shot, and skipping the live session means the batch route never asks for camera permission.
- Server background-removal cutout (`P3-SCAN-10`).

## Governing spec sections

§6.16, §12, §7 (permissions in context), §14 (`closet` Edge Function), §20.

## Elsewhere to build against

- `Domain/Repositories/ClosetRepository.swift` — `uploadCapturedImage` / `analyzeItem` / `batchAnalyzeItems`.
- `Domain/Models/ClosetItemAnalysisResult.swift` — confidence-scored suggestions the review screen binds to; `GarmentDeviceHints` for on-device priors.
- `Core/Networking/Live/LiveClosetRepository.swift` — upload-then-analyze flow.
- `Core/Mocks/MockClosetRepository.swift` — believable suggestions without a camera.
- ~~Guest mode: scan entry is gated before the modal opens for guests.~~ Withdrawn — ADR 0014 removed guest mode, and with it the gate.

**Server (outside this module):** `supabase/functions/closet/` — see that directory's README and `docs/08` §2.5 for the optional OpenAI vision pilot.

## Tickets

`P3-SCAN-*` in `docs/02-task-breakdown.md`. Next: wire `DeviceHintsExtraction` into review analyze, then live OpenAI pilot.

# Scanner

Owns garment capture and the device-side half of the computer vision pipeline (spec §6.16, §12).

> **Status:** capture screen ships for single-item mode (camera + Photos import). Review, Vision segmentation, OCR, and analyze-on-capture are **not** built. Trust `docs/03-progress.md` (`P3-SCAN-*`) for ticket status.

## What this module owns today

- Single-item capture UI: full-bleed preview, framing guide, quality guidance banner, shutter, Photos import (`Views/ScannerCaptureView.swift`).
- Capture view model + modal routing (`ViewModels/`, `Routing/ScannerDestinationView.swift`).
- Protocol-fronted camera session (`CaptureSessionControlling`) with live AVFoundation and mock adapters — quality judgement stays in pure functions.
- Device-side preprocessing already shipped as pure services: blur/exposure (`CaptureQuality`), resize/compress/metadata-strip (`CapturePreparation`), dominant color (`DominantColorExtraction`).

## What is deliberately not here yet

- Review screen with confidence chips and corrections (`P3-SCAN-09`).
- Vision garment-region / foreground mask (`P3-SCAN-02` device half — seam only).
- Label OCR (`P3-SCAN-03`).
- Batch / receipt / mirror capture modes (`P3-SCAN-12`) — modal routes answer honestly.
- Upload + analyze from the capture screen (`P3-SCAN-05` / wiring to `-07`).

## Governing spec sections

§6.16 (screen spec), §12 (full CV pipeline, device- and server-side), §7 (camera permission only when scanning; Photos only when importing), §14 (`POST /closet/analyze-item`, `POST /closet/batch-analyze`), §20 (target: item analysis under 8 seconds).

## Elsewhere to build against

- `Domain/Repositories/ClosetRepository.swift` — `analyzeItem` / `batchAnalyzeItems`.
- `Domain/Models/ClosetItemAnalysisResult.swift` — confidence-scored suggestions the future review screen binds to.
- `Core/Networking/Live/LiveClosetRepository.swift` — upload-then-analyze flow (Storage path, then Edge Function). Single-item calls send `Idempotency-Key`; batch calls enqueue then poll `GET /closet/batch-status/:id`.
- `Core/Mocks/MockClosetRepository.swift` — believable suggestions for previewing a review screen without a camera.
- Guest mode: `analyzeItem` / `batchAnalyzeItems` throw a validation error with zero network I/O; the scan entry point is gated before the modal opens for guests.

**Server (outside this module):** `supabase/functions/closet/` implements `POST /analyze-item`, `POST /batch-analyze` (job enqueue), and `GET /batch-status/:id` behind a mock `VisionAnalysisProvider` (live OpenAI adapter optional via env). See `docs/03-progress.md` for `P3-SCAN-07` / `P3-SCAN-08`.

## Tickets

`P3-SCAN-*` in `docs/02-task-breakdown.md`. Capture UI: `P3-SCAN-01` / `P3-SCAN-06`. Next: review (`P3-SCAN-09`) and upload wiring (`P3-SCAN-05`).

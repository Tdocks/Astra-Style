# Scanner

Owns garment capture and the device-side half of the computer vision pipeline (spec §6.16, §12).

> **Status:** single-item capture + review + upload/analyze/save ship. Vision garment-region, OCR, and batch/receipt/mirror modes are **not** built. Trust `docs/03-progress.md` (`P3-SCAN-*`).

## What this module owns today

- Single-item capture UI: preview, framing guide, quality guidance, shutter, Photos import.
- Review UI: editable suggestions, low-confidence footnotes, save to closet.
- Upload → analyze orchestration (`ScannerReviewViewModel`) via `ClosetRepository.uploadCapturedImage` + `analyzeItem`.
- Protocol-fronted camera session (`CaptureSessionControlling`) with live + mock adapters.
- Pure device services: `CaptureQuality`, `CapturePreparation`, `DominantColorExtraction`.
- `CaptureDraftStore` for capture→review handoff by UUID.

## What is deliberately not here yet

- Vision garment-region / foreground mask (`P3-SCAN-02` device half).
- Label OCR (`P3-SCAN-03`).
- Batch / receipt / mirror capture modes (`P3-SCAN-12`).
- Server background-removal cutout (`P3-SCAN-10`).

## Governing spec sections

§6.16, §12, §7 (permissions in context), §14 (`closet` Edge Function), §20.

## Tickets

`P3-SCAN-*` in `docs/02-task-breakdown.md`. Next: Vision adapter + OCR, then live OpenAI pilot.

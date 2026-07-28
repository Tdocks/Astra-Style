# Scanner

Owns garment capture and the device-side half of the computer vision pipeline (spec §6.16, §12).

## What this module owns

- Camera capture UI for all four modes: single item, batch closet scan, receipt/label, full outfit mirror photo.
- Camera guidance: edge detection, lighting indicator, background quality, blur warning, optional auto capture.
- The review screen: segmented cutout, suggested metadata with per-field confidence indicators, user correction — every inferred field must remain editable and low-confidence fields must be visibly marked (§12 "User verification").
- Device-side preprocessing before upload: blur/exposure detection, garment region detection, on-device segmentation where supported, OCR of label text, dominant color extraction, resize/compress, metadata stripping (§12 "Device-side").

## Governing spec sections

§6.16 (screen spec), §12 (full CV pipeline, device- and server-side), §7 (camera permission requested only when scanning; new scans can be captured and queued offline), §14 (`POST /closet/analyze-item`, `POST /closet/batch-analyze`), §20 (target: item analysis under 8 seconds).

## What already exists to build against

- `Domain/Repositories/ClosetRepository.swift` — `analyzeItem(imageData:imageType:)` and `batchAnalyzeItems(imageDataList:)`.
- `Domain/Models/ClosetItemAnalysisResult.swift` — `FieldSuggestion<Value>` is the confidence-scored suggestion type the review screen should bind to directly (`isLowConfidence` is already computed).
- `Core/Networking/Live/LiveClosetRepository.swift` — shows the intended upload-then-analyze flow (Storage upload to `users/{id}/closet/...`, then the Edge Function call with the storage path, never raw bytes).
- `Core/Mocks/MockClosetRepository.swift` — `analyzeItem`/`batchAnalyzeItems` return a believable suggestion for previewing the review screen without a camera.

## Tickets

Filled in by the **P3-SCAN** tickets in `docs/02-task-breakdown.md`.

# Studio

Owns Style Studio: visual try-on / outfit visualization (spec §6.17, §13).

## What this module owns

- Reference image selection/capture with explicit ownership/permission consent (§6.17 Safety).
- Outfit/item/theme selection controls, prompt presets, and the advanced controls (preserve face/body/hair, background, pose, formality, season, color palette).
- The generation viewport: before/after compare, generated-image labeling (never implying exact fit/body outcome — §6.17 Safety, §11 guardrails), and the queued/generating/complete/failed states with retry.
- The results gallery / lookbook and per-generation deletion controls.

## Governing spec sections

§6.17 (screen spec), §13 (generation pipeline, prompt template, cost controls), §9 (`studio_generations`), §14 (`POST /studio/generate`, `GET /studio/status/:id`), §16 (Style Studio quota is a premium differentiator), §21 ("Studio failed: preserve prompt and allow retry without consuming another credit when failure is provider-side" — see `StudioGeneration.isRetryableWithoutCharge`), §29 (deletion controls, generated-image disclaimer).

## What already exists to build against

- `Domain/Repositories/StudioRepository.swift` — start/poll/retry/delete.
- `Domain/Models/StudioGenerationRequest.swift` — `StudioPromptPreset`, `StudioBackground`, `StudioPose`, and the `hasUserConsent` flag the repository is expected to enforce.
- `Domain/Models/StudioGeneration.swift` — `isRetryableWithoutCharge`.
- `Core/Mocks/MockStudioRepository.swift` — simulates the queued → generating → complete lifecycle on repeated `fetchStatus` polls, so a polling UI can be built and previewed without a real provider.

## Tickets

Filled in by the **P6-STUDIO** tickets in `docs/02-task-breakdown.md`.

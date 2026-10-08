# ADR 0021: Contextual inspiration on Home

Date: 2026-10-08
Status: Accepted; implemented; live image acceptance pending

## Context

The owner requested two Home image flows: inspiration informed by quiz preferences, weather and calendar, and a look made only from owned closet items. They must work without requiring a personal reference photo, support rerolls and edits, and preserve privacy.

## Decision

Extend Studio's existing job orchestration with explicit `inspiration` and `closet_inspiration` modes. Reference-photo Studio remains unchanged and continues to require consent. Inspiration produces a flat lay without people. Text-to-image uses the existing pinned OpenAI image model and server credential; no additional SDK or client key is introduced.

New renders use the generations API. Edits resolve a completed, owner-scoped inspiration's result path server-side and use the edits API. Clients cannot supply an arbitrary source image path. Modes cannot cross from personal reference jobs. Closet mode resolves garments from owned rows and rejects partially unresolved selections. It does not imply exact photo reconstruction: every result is a visual estimate.

The view model reads quiz preferences, fresh authorized WeatherKit conditions, and calendar timing/dress codes. Event titles, locations and descriptions remain on device. Unavailable context is identified in the UI and never invented. Closet selections are editable before rendering; adjustments cannot authorize adding unowned garments.

Use existing private `user-content` storage paths, Studio history, deletion/retention, status polling, premium allowance and free trial. Rerolls/edits create new jobs and use allowance; retries of failed jobs retain existing behavior. No schema migration is required.

## Tradeoffs and follow-up

The existing polling infrastructure still advances synchronous image calls, with a bounded client deadline. Jobs are recoverable from Studio. The initial simulator build was blocked by Xcode setup; setup completed during implementation and the build and targeted Swift tests then passed. This Mac now runs Xcode 27.0 with the iOS 26.5 simulator, rather than the earlier release's 26.6 toolchain. Authenticated live image quality and fidelity must be checked before release. This change does not certify the app for outside users.

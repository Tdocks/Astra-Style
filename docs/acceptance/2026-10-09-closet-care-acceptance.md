# Closet care and outfit-count acceptance

The optional owner-entered `closet_items.care_instructions` field was deployed
as migration `20261009084819_add_closet_care_instructions` on 2026-10-09.
Production readback confirmed nullable text. Existing owner policies and grants
are unchanged; care notes are never inferred from material.

The full scratch migration/RLS run passed, including
`53_closet_care_instructions.sql`: owner save/clear, peer isolation and legacy
NULL compatibility. The full backend suite passed 1,044 tests, including care
export and saved-outfit insights fixtures. Swift schema and column drift checks
passed, and strict SwiftLint reported zero violations across 595 files.

## Completed native acceptance

On 2026-10-09 the focused simulator run passed 45 tests across
`ClosetItemDetailViewModelTests`, `ClosetItemFormViewModelTests` and
`ClosetCareInstructionsPersistenceTests`. Coverage includes populated detail
fields, owner-derived saved-outfit counts, unavailable counts staying unavailable,
edit persistence, care-note clear, migration of a V5 store without losing rows,
reopen and owner isolation. The real database maintains wear count and last worn
through the `outfit_wears` trigger; the native model consumes those fields.

Result: `/tmp/astra-inspiration-build/Logs/Test/Test-AstraStyle-2026.10.09_18-03-00--0400.xcresult`.

`ClosetItemCareInstructionsUITests.testCareInstructionsCanBeSavedAndClearedFromItemDetail`
then passed the visible save-and-clear path (65.116 seconds). The same focused
UI run also passed Studio's light AX5 image-description edit (29.146 seconds).
Log: `/tmp/astra-priority-care-studio-ui.log`. These tests use deterministic
mock simulator fixtures; the separate hosted save/clear and owner-isolation
checks are recorded in `2026-10-09-outfit-builder-backend-acceptance.md`.
This closes P3-CLOSET-06's item-detail criteria, not the broader physical-device
scanner journey or external-user readiness.

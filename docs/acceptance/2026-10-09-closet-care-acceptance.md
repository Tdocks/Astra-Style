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

Native persistence migration, save/clear UI and complete-suite acceptance are
still pending the combined simulator run. This document does not claim a
successful native migration or first-user readiness before that result.

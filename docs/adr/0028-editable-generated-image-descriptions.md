# ADR 0028 — Editable generated-image descriptions

Status: Accepted, 2026-10-08.

Spec §19 requires editable descriptions for generated images. Completed Studio
estimates expose an image-description editor, including restoring the automatic
description. Defaults use the structured garment titles and colors already
stored with the prompt and explicitly retain visual-estimate uncertainty.
Descriptions do not alter provider prompts or consume an image allowance.

The nullable alt_description column stores only the user's override. A column
UPDATE grant and owner/completed/not-deleted RLS policy allow that single field
to change; status, source, ownership, leases and allowance fields remain
server-only. Descriptions are limited to 1,000 characters. Clearing resets to
null, using explicit JSON null rather than Optional encoding that omits nil.

Detail, gallery, saved collections and generated comparison images read the
description. Home inspiration now uses GeneratedImageContainer for consistent
visible generated-image disclosure. Status responses and safe data export carry
the saved description; private lease tokens remain excluded.

Verification: nine Swift description/export tests, 111 Studio/Profile backend
tests, the complete SQL isolation suite plus owner/reset/length/peer/active-row
and server-status-write checks passed. Dark and light Accessibility XXXL editor
flows saved, reopened and reset descriptions successfully. Live disposable-user
checks passed owned save/reset, peer denial, status/export round trips and
status-write denial. Both QA accounts and their synthetic generation were
erased and confirmed absent. Physical-device VoiceOver and the app-wide Reduce
Motion acceptance remain separate work. The source audit found two unconditional
animations in scanner guidance and onboarding quiz updates; both now use the
Reduce Motion-aware modifier. Kyra orb/thinking loops now react to environment
changes and stop when their views disappear. Other explicit animation call sites
already route through the motion helper; no matched geometry or spring paging
call sites exist outside the unused design token.

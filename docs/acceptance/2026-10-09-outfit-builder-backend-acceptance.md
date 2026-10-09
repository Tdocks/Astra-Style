# Outfit builder backend acceptance

The full backend suite passed 1,048 tests on 2026-10-09. Builder-mode Kyra
requests are additive: legacy chat omits the new fields. Builder completion
uses owned active garments, preserves locked IDs and requires a reason.

The full scratch migration/RLS suite passed, including
`54_outfit_edit_rpc.sql`: same-ID replacement, retained historical wear,
stale edit rejection, blank-name rejection, and peer/archived/mismatched-role
item rejection. Initial test-only SQL argument/composite-row issues were
corrected before the passing run.

Migration `20261009090643_replace_outfit_items` was applied to production.
Independent catalog readback confirms SECURITY INVOKER, empty search_path,
no anon execute privilege and authenticated execute privilege. The Kyra Edge
Function deployment completed successfully with its existing JWT setting.

## Hosted owner/peer acceptance

A bounded metadata-only hosted run passed after two follow-up migrations:
`20261009091633` returns PT409 for a stale editor instead of retryable 40001;
`20261009091819` returns PT404 for hidden/missing outfits instead of a server
error. Both follow-up migrations passed the complete scratch RLS suite.

The final hosted harness verified owner edit 200 with unchanged outfit UUID,
three replacement items, and original wear ID/date retained; stale 409 left
all rows unchanged; peer-item 403 left rows unchanged; a peer outfit returned
404 and remained invisible. Owner care text save and explicit-null clear both
returned 200; a peer PATCH matched zero rows and could not alter the value.

Fixture owners `404ada2e-7484-4ff2-bf87-2cf38c39d456` and
`fe9c8454-ac35-4c20-9fea-941bfe96c8db` were deleted normally. Root independently
confirmed zero remaining Auth, closet, outfit and wear rows. No media or
provider requests were made. Harness:
`supabase/functions/outfits/hosted_replace_outfit_items_acceptance.ts`.

Native full-suite verification passed 1,136 Swift Testing tests on 2026-10-09.
The subsequent focused run passed 25 builder view-model tests and both builder
UI tests (43.160 seconds combined). Long-press locks without opening the picker;
Kyra preserves the locked top; same-outfit edits retain their identity. Additional
regressions cover Kyra-assisted edits keeping their original backing ID, mutually
exclusive mutations and clearing stale explanations after manual changes.

A bounded live request returned HTTP 200 from gpt-5.6-luna, no fallback or
escalation, and exactly one create_outfit call. Outfit
c97912ef-00d3-4bd0-99ff-8b1edc4f7140 persisted with owned top, bottom, shoes and
accessory, no product candidates, and locked top
9bdbe769-7c42-42e0-b6fb-e30f6dbb084d preserved. Card and persisted reasons were
nonempty paraphrases, not identical strings; the native builder reads the persisted
reason. Fixture owner ed10e7be-042d-4312-9af5-bdb6edbdc8ba was deleted normally
(202, receipt fc679c54-bfcc-4dd8-906d-edb38fc3ac52). Independent SQL confirmed
zero remaining Auth, closet, outfit, thread and assistant-message rows. The prior
fixture owner was also independently confirmed deleted. Harness:
`supabase/functions/kyra/hosted_builder_completion_acceptance.ts`.

This verifies the builder ticket acceptance, not overall outside-user readiness.

## Internal TestFlight release

Version 1.0.0 (32), build e95031d0-f90b-4247-8ea7-a47f90df240f, archived,
exported and uploaded successfully. Apple reports VALID and IN_BETA_TESTING.
Internal group membership and saved en-US testing notes were verified by API
readback. This is an Internal release; external review remains unsubmitted.

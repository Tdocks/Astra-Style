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
Outfit-builder UI acceptance is still in progress. This does not establish a
live Kyra builder-provider response or readiness for outside users.

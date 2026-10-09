# Account deletion and child-key index acceptance — 2026-10-09

## Failure and fix

Live normal account deletion failed at `auth_identity_delete_failed` for a synthetic
closet/cache fixture. Database logs identified SQLSTATE 42501: Supabase Auth's
managed role deleted auth.users, then the cascading closet DELETE trigger attempted
an unauthorized profiles UPDATE.

Migration 20261009043644 makes only the internal scoring-version trigger SECURITY
DEFINER, owned by postgres, with empty search_path and fully qualified table names.
Affected owner IDs come from trigger rows. A cascaded DELETE skips work if the
profile has already disappeared. PUBLIC, anon, authenticated, service_role, and
Auth have no direct function execution; Auth still cannot directly update profiles.
The independent live privilege query confirmed these restrictions.

## Normal deletion acceptance

Disposable synthetic owner: beac5eed-14b4-4294-b7f0-64a3ac9d99da.
Deletion receipt: 2043fe00-7c09-453e-90ad-017d35cacb72.
A normal DELETE /account returned 202 and the receipt reached completed.
Independent root SQL readback confirmed zero auth.users, profiles, closet_items,
and outfit_unlock_count_cache rows for this owner. This fixture used no provider
request, photograph, or real user's data.

The scratch RLS suite includes a limited role that can delete auth.users but cannot
update profiles, proving the cascade no longer depends on broad managed-role grants.
It also retains the direct scoring-version forgery rejection assertion.
Saved suite log: /tmp/astra-fk-indexes-rls.log (all assertions passed).

## Index audit

Migration 20261009043932 adds the three genuinely absent child-key indexes:
- kyra_studio_confirmations(thread_id, user_id)
- kyra_studio_confirmations(prompt_message_id, thread_id, user_id)
- studio_submission_requests(generation_id, user_id)

Root independently queried the live pg_indexes definitions and confirmed all three.
The remaining advisor FK finding has an existing full index with leading
(user_id, lookbook_id); an equality query on both keys selected an index-only scan.
No redundant index was added and no unused index was removed without measurements.

## Limits

This proves the reproduced Auth cascade failure is fixed, not every account-deletion
scenario or physical-device logout/erase acceptance. Existing advisor findings remain:
server-only RLS tables without client policies, anonymous-role policy warnings,
pg_net in public, and the equivalent-order FK index finding. Live provider, purchase,
real-device, and legal launch gates are not established by this acceptance.

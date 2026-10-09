# P4-TEST-03 Daily Brief live acceptance

The production-path tests, JSONB comparison fix, and guarded hosted harness are integrated. The fixed Daily Brief handler was deployed before the successful live run. The combined backend suite passed 1,034 tests; the focused Daily Brief suite passed 25 tests.

## Production path test

`supabase/functions/daily-brief/production_integration_test.ts` calls the actual `handleGenerateDailyBrief` and `CompatibilityOutfitScorer` implementation. It uses distinct caller and peer garment fixtures and a repository fixture that persists generated outfit rows and outfit-item references in memory. It covers populated and empty closets, scorer weather/calendar context, owned garment references, idempotency, and regeneration. `handler_test.ts` also reproduces PostgreSQL `jsonb` returning schedule-object keys in a different order and proves a same-day replay does not create outfits again.

## Hosted acceptance

`supabase/functions/daily-brief/hosted_acceptance.ts` creates two disposable anonymous accounts in the configured project. It inserts synthetic garment and closet-image metadata (no Storage bytes), calls the deployed Daily Brief and profile export endpoints with a synthetic device weather/calendar snapshot, and verifies the primary and alternatives reference only the caller's seeded garments. It checks same-day idempotency, explicit regeneration, profile export `no-store`, caller-owned source/cutout/thumbnail manifest paths, and peer RLS denial for owner image metadata. It then requests normal account deletion and waits for completed status, zero owned fixture rows, and Auth identity deletion.

The run used the production Supabase project with temporary anonymous fixtures, not a separate staging project. It made no paid provider calls and uploaded no images. The manifest assertions prove that the export lists database-referenced paths; they do not prove that Storage objects exist, that object downloads work, or that the manifest lists every bucket object.

The script is gated by `ASTRA_ALLOW_DISPOSABLE_DAILY_BRIEF_ACCEPTANCE=YES`, reads anon/service keys from a protected CLI JSON file, and never prints credentials. It accepts `SUPABASE_URL` and `SUPABASE_KEYS_FILE`.

Hosted result on 2026-10-09: the first request generated owned outfits; replay returned the same brief and outfit without adding rows; regeneration updated the same brief with a fresh outfit; the owner export returned HTTP 200 with `Cache-Control: no-store` and included source, cutout, and both thumbnail paths; peer image metadata returned no rows. Both disposable account deletions reached `completed`, fixture table counts were zero, and Auth no longer recognized either account.

Root independently queried Auth, daily briefs, outfits, and closet image metadata for both exact fixture owners after cleanup; every count was zero. The previous disabled native placeholder was removed in favor of these real integration tests.

# Astra Style — Supabase

This directory holds the Postgres schema (`migrations/`) and, eventually, Edge
Functions (`functions/`) for Astra Style. See `docs/00-master-spec.md` for the
product spec and `docs/04-data-model.md` for the schema design rationale.

## Prerequisites

- [Supabase CLI](https://supabase.com/docs/guides/cli) v1.200+ (`brew install
  supabase/tap/supabase`, or see the CLI docs for other platforms).
- Docker Desktop (or another Docker-compatible engine) running locally — the
  CLI's `supabase start` boots the full local stack (Postgres + pgvector,
  Auth, Storage, Realtime, Studio) in containers.
- A Supabase hosted project (dashboard-created) if you intend to deploy past
  local development.

## Directory layout

```text
supabase/
  migrations/     Numbered, ordered SQL migrations — see below.
  functions/      Edge Functions (Deno/TypeScript). `outfits` (serving
                   POST /outfits/generate) is the first one, built as the
                   vertical slice from docs/01-build-roadmap.md; functions
                   are named after the FIRST path segment of the spec S14
                   endpoints they serve and route internally on the rest
                   (docs/adr/0013-edge-function-routing.md). See
                   functions/README.md for how to run, test, and deploy.
  config.toml     Supabase CLI project config (created by `supabase init`,
                   not checked in yet as of this migration set).
```

Migrations are named `YYYYMMDDHHMMSS_description.sql` per the Supabase CLI
convention and are applied strictly in filename (timestamp) order:

| # | File | Contents |
|---|---|---|
| 1 | `20260728100000_enable_extensions.sql` | pgvector, pgcrypto, pg_trgm, unaccent |
| 2 | `20260728100100_core_enums.sql` | Every enum type (category, laundry/availability state, verdicts, etc.) |
| 3 | `20260728100200_profiles_and_identity.sql` | `profiles`, `style_profiles`, `body_profiles`, `lifestyle_profiles` |
| 4 | `20260728100300_closet.sql` | `closet_items`, `closet_item_images` |
| 5 | `20260728100400_outfits.sql` | `outfits`, `outfit_items`, `outfit_wears` |
| 6 | `20260728100500_feedback_and_memory.sql` | `kyra_threads`, `kyra_messages`, `style_feedback`, `style_memories` |
| 7 | `20260728100600_commerce.sql` | `product_candidates`, `user_product_evaluations` |
| 8 | `20260728100700_planning.sql` | `occasions`, `daily_briefs` |
| 9 | `20260728100800_studio_and_subscriptions.sql` | `studio_generations`, `subscriptions` |
| 10 | `20260728100900_rls_policies.sql` | Row Level Security on every user-owned table |
| 11 | `20260728101000_storage_buckets.sql` | The `user-content` private bucket + storage RLS |
| 12 | `20260728101100_indexes_and_search.sql` | btree/GIN/HNSW indexes |
| 13 | `20260728101200_functions_and_triggers.sql` | `updated_at` triggers, `handle_new_user`, soft-delete RPCs |
| 14 | `20260728101300_account_deletion.sql` | The account-deletion job (table + functions) |

Every migration is written to be safe to re-run (`create table/index if not
exists`, `do $$ ... exception when duplicate_object` guards around enum/role
creation, `pg_policies`/`pg_constraint` existence checks before `create
policy`/`alter table ... add constraint`) — this was verified directly (see
"Verification performed" below), not just intended.

## Local development

```bash
# One-time: link this repo to a Supabase project (creates supabase/config.toml
# if it doesn't already exist). Skip if config.toml is already checked in.
supabase init

# Start the full local stack (Postgres 15+ with pgvector already installed,
# Auth, Storage, Realtime, Studio) in Docker.
supabase start

# Apply every migration in supabase/migrations/, in order, to the local
# database. Also runs on `supabase start` automatically for a fresh stack;
# run this explicitly after adding a new migration file.
supabase migration up

# Or, equivalently, wipe the local database back to empty and replay every
# migration from scratch — use this whenever you want a guaranteed-clean
# state (e.g. after editing an already-applied local migration file, or to
# confirm the full migration set still applies cleanly end to end).
supabase db reset
```

`supabase start` prints local connection details, including the local Studio
URL (usually `http://localhost:54323`) for browsing the schema, running ad
hoc SQL, and inspecting RLS policies visually.

### Generating a new migration

```bash
supabase migration new some_description
# -> supabase/migrations/<timestamp>_some_description.sql
```

Follow the existing files' conventions: `set search_path = public,
extensions;` at the top if the migration references `extensions.*` types/
functions unqualified anywhere convenient, `create ... if not exists` /
`do $$ ... exception when duplicate_object then null; end $$;` for anything
that isn't naturally idempotent, `comment on table/column` for anything
non-obvious, and an explicit `on delete` behavior on every foreign key.

## Applying to a hosted project

```bash
# One-time: authenticate the CLI and link this repo to your hosted project.
supabase login
supabase link --project-ref <your-project-ref>

# Review what would change, then push.
supabase db diff --linked
supabase db push
```

`supabase db push` applies every migration in `supabase/migrations/` that
hasn't already been recorded as applied on the linked project (tracked in the
`supabase_migrations.schema_migrations` table on the remote database). It
does not run migrations out of order and does not skip ahead — a new
migration file must sort after every already-applied one.

**Before pushing to a project with real user data**, read
`supabase/migrations/20260728101300_account_deletion.sql`'s header comment in
full — it documents the exact Edge Function orchestration
(`supabase/functions/account-delete`, not yet written) required around the
`request_account_deletion` / `finalize_account_deletion` /
`mark_account_deletion_complete` SQL functions this migration set creates.
The SQL alone does not delete a user's auth identity or Storage blobs; an
Edge Function using the service-role key must drive those two API calls.

## Resetting

- **Local:** `supabase db reset` (destroys and rebuilds the local Postgres
  container's database from `migrations/` plus any `supabase/seed.sql`, if
  one is added later).
- **Hosted:** there is no destructive "reset" for a hosted project via the
  CLI, by design. To roll back a specific change, write a new forward
  migration that undoes it (see "migrations are append-only" convention
  referenced in `docs/adr/0002-supabase-as-backend.md`) rather than editing
  or deleting an already-pushed migration file.

## Environment variables (§25 of the master spec)

**Edge Functions only** (set via `supabase secrets set` for hosted, or
`supabase/functions/.env` — gitignored — for local `supabase functions
serve`). None of these are ever sent to the iOS client:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
STYLIST_PROVIDER_API_KEY
VISION_PROVIDER_API_KEY
IMAGE_PROVIDER_API_KEY
EMBEDDING_PROVIDER_API_KEY
WEATHER_PROVIDER_KEY_IF_USED
AFFILIATE_PROVIDER_KEYS
APP_STORE_SHARED_CONFIGURATION
```

### Open item — `IMAGE_PROVIDER_API_KEY` is not set, and the key is in the wrong place

Recorded here rather than in a decision document because it is a setup problem, and this is
where someone setting the project up will look.

The image provider is decided: **OpenAI, called directly, and it is the only image provider**
(`docs/08` §3.5, `docs/15` §5, `docs/16` §4). One key covers two models — `gpt-image-1.5` for
Style Studio, `gpt-image-2` for quiz imagery and reference generation — so this is a single
secret regardless. A working OpenAI key exists and has been
verified against `gpt-image-1`, `gpt-image-1-mini`, `gpt-image-1.5`, `gpt-image-2` and
`chatgpt-image-latest`. **It is not on this project:** `supabase secrets list` shows no
`OPENAI_API_KEY` and no `IMAGE_PROVIDER_API_KEY`. What exists instead is a pair of local env
files sitting in the repo's *parent* directory, left over from the `docs/15`/`docs/16`
evaluations. They are outside the repo and therefore uncommitted, which is the half of this that
is fine; the other half is not, because spec §25 and `docs/adr/0004-provider-neutral-ai-layer.md`
allow a provider key to exist in exactly one place — an Edge Function environment variable — and
a key in a developer's working directory is not that place. Set it properly before any Edge
Function needs it:

```bash
supabase secrets set IMAGE_PROVIDER_API_KEY=...   # OpenAI key; never in .xcconfig, never in iOS
```

Two credentials in those same files are now **dead and should be revoked, not kept**:
`XAI_API_KEY` and `GEMINI_API_KEY`, from the three-vendor bake-off in `docs/15`. With OpenAI as
the only image provider they have no remaining use, and an unused API key sitting in plaintext is
a pure liability — it cannot help anyone and it can be leaked, committed by accident, or billed
against. Revoke them at the provider first, then delete the local copies; deleting the file alone
leaves a live credential in the wild.

**iOS app only** (via `.xcconfig`, per §25 — never hardcoded, never the
service-role key):

```text
SUPABASE_URL
SUPABASE_ANON_KEY
```

Get these values for a given project with:

```bash
supabase status                 # local stack: prints local URL + anon/service keys
# or, for a hosted project, via the dashboard: Project Settings -> API
```

## Verification performed on this migration set

Because this environment doesn't have the Supabase CLI's Docker-based local
stack available, verification used a plain Postgres 16 install with the
`postgresql-16-pgvector` package (pgvector 0.6.0) instead, plus a small,
non-shipped SQL shim standing in for the parts of a Supabase project that
exist before any user migration runs (the `auth`/`storage` schemas and their
core tables/functions, the `authenticated`/`anon`/`service_role` roles, and
the platform's default-privilege grants). All 14 migrations were applied in
order against a clean database with zero errors, re-applied a second time end
to end to confirm idempotency, and exercised functionally (signup trigger,
RLS isolation between two simulated users, the `outfit_items` exactly-one-of
constraint, the vector dimension constraint, the wear-count trigger, storage
path RLS, and the full account-deletion sequence). Full detail, including one
real privilege-grant bug this process found and fixed, is in
`docs/04-data-model.md` §7.

This is a stand-in for, not a replacement of, running the real Supabase CLI
local stack (`supabase start` + `supabase db reset`) before deploying to a
hosted project — do that too as part of normal development, since it exercises
the actual Supabase Postgres image/extension versions and the real `auth`/
`storage` schemas rather than the shim's approximation of them.

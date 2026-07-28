# Astra Style — Supabase Edge Functions

This directory holds the Deno/TypeScript Edge Functions for Astra Style.
`outfits-generate` (deployed as `POST /outfits/generate`) is the first one,
built as the template the other 15 endpoints in spec §14 will be copied
from. Read `docs/01-build-roadmap.md`'s "Vertical slice first" section and
`docs/00-master-spec.md` §14/§15 before adding a second function — the
conventions below exist to satisfy those sections, not as arbitrary style.

## Layout

```text
supabase/functions/
  deno.json              Shared Deno config (strict TS, import map, fmt/lint/test settings)
  _shared/                Code every function reuses — see below
    cors.ts                CORS preflight handling
    errors.ts               Typed AppError + the ResponseEnvelope wire shape
    jwt.ts                   JWT validation against Supabase Auth
    logger.ts                Structured JSON logging with a content denylist
    rateLimit.ts             In-memory rate limiter (see its header comment for limitations)
    requestId.ts             Request ID resolution (header -> body -> generated)
    supabaseClient.ts        Caller-scoped (never service-role) Supabase client factory
    validation.ts            Small schema-validation helpers (UUID, string, int range, ...)
  outfits-generate/       POST /outfits/generate
    index.ts                Deployment entrypoint (Deno.serve + real Supabase wiring)
    handler.ts               Testable request handler (all deps injected)
    schema.ts                Request/response DTOs + body validation
    scorer.ts                 THE DETERMINISTIC SLICE SCORER — see its header comment
    *_test.ts                 Deno.test suites, one per module
```

Every future endpoint (`profile/complete-onboarding`, `closet/analyze-item`,
`kyra/respond`, etc.) should follow the same shape: a thin `index.ts` for
wiring, a `handler.ts` with injected dependencies for testability, a
`schema.ts` for request validation, and reuse of everything in `_shared/`
rather than reimplementing JWT validation, error envelopes, logging, CORS,
or rate limiting per function.

## Why no service-role key in `outfits-generate`

Spec §15: "Service role keys exist only in Edge Functions. Never ship them
in the app." That's a necessary condition, not a license to use the
service-role key by default *inside* an Edge Function. `outfits-generate`
only ever needs to read the *caller's own* `closet_items` rows, which
`closet_items_select_own` (`supabase/migrations/20260728100900_rls_policies.sql`)
already grants to any `authenticated` user for their own `user_id`. So this
function builds its Supabase client scoped to the caller's own JWT
(`_shared/supabaseClient.ts::createUserScopedClient`) and lets Postgres Row
Level Security — not application code — be the thing that actually prevents
cross-user reads. **This function contains no service-role client
anywhere.** A future endpoint that genuinely needs service-role (e.g.
`DELETE /account` calling the Auth Admin API to delete the `auth.users`
identity, which RLS cannot express) should say so explicitly in a comment
next to where it's constructed, the same way this README does for the
negative case.

## Rate limiting — stated honestly

`_shared/rateLimit.ts` is an in-memory, per-isolate fixed-window limiter.
There is no durable store (Redis/Upstash, a dedicated Postgres rate-limit
table) provisioned for this vertical slice — see
`docs/01-build-roadmap.md`'s exclusion list, which does not include
abuse-resistance infrastructure in scope. That means:

- It resets to zero on every cold start / isolate recycle.
- A caller whose requests land on different isolates (different regions, or
  after scale-to-zero) can exceed the nominal limit.

It still does real, useful work (catching a single hot isolate being
hammered, or a runaway client-side retry loop) and costs nothing to deploy,
but it is explicitly **not** a security boundary. See the file's header
comment for the migration path to a durable limiter behind the same
`RateLimiter` interface.

## The scoring seam — where the real `CompatibilityScorer` plugs in

`outfits-generate/scorer.ts` implements `OutfitScorer`, an interface with
one method: `generate(items, options) -> ScoredOutfit[]`. The only
implementation today, `LeastRecentlyWornScorer`, is the deterministic
placeholder named explicitly in `docs/01-build-roadmap.md`'s vertical slice
section: pick one top + one bottom + one pair of shoes, preferring
least-recently-worn items. It does **not** compute color harmony,
formality alignment, silhouette compatibility, weather fit, user
preference, historical co-wear, or occasion relevance — see
`docs/05-wardrobe-graph.md` §2 for what the real 8-component weighted
formula looks like, and `SLICE_PLACEHOLDER_COMPATIBILITY_SCORE`/the
`reason` string in `scorer.ts` for how the response makes this obvious to
anyone reading it, not just anyone reading this README.

When the real `CompatibilityScorer` is built (Phase 4), it should implement
`OutfitScorer` and be handed to `handler.ts` via `HandlerDeps.scorer` (see
`index.ts`, where `LeastRecentlyWornScorer` is currently instantiated) — no
other change to `handler.ts` should be required. `docs/05-wardrobe-graph.md`'s
own header notes the scoring core should eventually be shared between
`/outfits/generate`, `/outfits/rank`, and `/products/evaluate`; at that
point, move `OutfitScorer` and its implementation into `_shared/scoring/`.

## Prerequisites

- [Supabase CLI](https://supabase.com/docs/guides/cli) v1.200+.
- [Deno](https://deno.com) 2.x (`deno --version`; this project was built
  and verified against `deno 2.9.4`).
- Docker Desktop (or another Docker-compatible engine) for `supabase start`.

## Local development

```bash
# From the repo root, or supabase/ — start the full local stack (Postgres +
# pgvector, Auth, Storage, Realtime, Studio) in Docker. Also applies every
# migration in supabase/migrations/.
supabase start

# Serve every function in supabase/functions/ locally, hot-reloading on save.
# SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected
# automatically from the local stack `supabase start` just printed.
supabase functions serve

# Or serve just this one function:
supabase functions serve outfits-generate
```

`supabase functions serve` prints the local URL, typically
`http://localhost:54321/functions/v1/outfits-generate`.

### Getting a real JWT to test with

The endpoint requires a real Supabase Auth JWT — there is no bypass. Against
the local stack, the fastest way to get one for a test user:

```bash
# Sign up (or sign in) a test user against the local Auth server and
# extract the access token. `supabase status` prints ANON_KEY/local URL.
curl -sS -X POST 'http://localhost:54321/auth/v1/signup' \
  -H "apikey: <ANON_KEY from `supabase status`>" \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "password": "correct-horse-battery-staple"}' \
  | tee /tmp/signup.json | jq -r '.access_token' > /tmp/access_token.txt

# (If the user already exists, use /auth/v1/token?grant_type=password instead.)
```

You'll also want at least one closet item for that user (top/bottom/shoes)
before `outfits/generate` can return anything — insert directly via
Supabase Studio (`http://localhost:54323`) or `psql`, since there is no
`closet/analyze-item` endpoint in this vertical slice yet (manual entry
only, per `docs/01-build-roadmap.md`).

### Exercising the endpoint

```bash
ACCESS_TOKEN=$(cat /tmp/access_token.txt)
ANON_KEY="<ANON_KEY from \`supabase status\`>"

curl -sS -X POST 'http://localhost:54321/functions/v1/outfits-generate' \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "apikey: ${ANON_KEY}" \
  -H "Content-Type: application/json" \
  -H "X-Request-Id: $(uuidgen)" \
  -d '{
    "request_id": "'"$(uuidgen)"'",
    "client_version": "curl/manual-test",
    "body": {
      "desired_count": 3
    }
  }' | jq .
```

Expected success shape (matches `AstraResponseEnvelope<[OutfitRecommendation]>`
in `ios/AstraStyle/Core/Networking/AstraRequestEnvelope.swift`):

```json
{
  "data": [
    {
      "id": "…",
      "name": "Today's Outfit",
      "reason": "Picked from your least-recently-worn top, bottom, and shoes — a deterministic vertical-slice placeholder, not the real compatibility scorer (docs/05-wardrobe-graph.md §2).",
      "compatibility_score": 65,
      "item_ids": ["…", "…", "…"],
      "missing_product_ids": []
    }
  ],
  "error": null,
  "request_id": "…"
}
```

Try it again with no `Authorization` header, or a garbage Bearer token, to
see the 401 path; with `"body": {"desired_count": 999}` to see the 400
schema-validation path.

## Type checking, tests, formatting, linting

Run these from `supabase/functions/` (a `deno.json` there defines the
import map and strict compiler options every file below it inherits):

```bash
cd supabase/functions

deno check _shared/*.ts outfits-generate/*.ts   # or: deno task check
deno test --allow-env _shared/ outfits-generate/  # or: deno task test
deno fmt --check _shared/ outfits-generate/       # or: deno task fmt-check
deno lint _shared/ outfits-generate/              # or: deno task lint
```

`deno test` needs `--allow-env` only because `_shared/supabaseClient.ts`
reads `Deno.env.get(...)` at module scope in a code path some tests import
transitively for type purposes; no test in this suite makes a network call
or touches a real Supabase project — every Supabase/Auth interaction is
mocked at the `AuthClient`/`ClosetRepository` interface boundary (see
`outfits-generate/handler_test.ts`'s header comment).

`outfits-generate/index.ts` (the `Deno.serve` wiring) is intentionally
*not* covered by a unit test — it's pure wiring with no branching logic of
its own, and the parts worth testing (does a real JWT get accepted? does
RLS actually block another user's rows?) require a real Supabase Auth +
Postgres to mean anything, which is what the `curl` walkthrough above and
`supabase functions serve` are for. `deno check` does still type-check it.

## Deploying

```bash
supabase login
supabase link --project-ref <your-project-ref>

# Set every provider/config secret an Edge Function needs (SUPABASE_URL and
# SUPABASE_ANON_KEY are provided automatically for deployed functions; do
# NOT set SUPABASE_SERVICE_ROLE_KEY here unless a function actually needs
# it — outfits-generate does not).
supabase secrets set STYLIST_PROVIDER_API_KEY=... # only when a function needs it

supabase functions deploy outfits-generate
```

After deploying, repeat the `curl` invocation above against
`https://<project-ref>.supabase.co/functions/v1/outfits-generate` with a
real project JWT and anon key (`supabase status` for local, the dashboard's
Project Settings -> API for hosted).

## Verification performed on this function (and what was not verified)

Verified in this environment (no live Supabase project or Docker available
here):

- `deno check` passes with zero errors across every `_shared/` and
  `outfits-generate/` file, including `index.ts`, under `strict: true` (no
  `any` anywhere in this function's own code).
- `deno test --allow-env _shared/ outfits-generate/` passes: **65 tests, 0
  failures**, covering (among others) a missing JWT, a malformed JWT, a JWT
  Supabase Auth itself rejects, schema-invalid bodies (out-of-range
  `desired_count`, a non-UUID in `locked_closet_item_ids`, a missing `body`
  field, unparsable JSON), a well-formed successful response, rate-limit
  enforcement, and — the most important case — that a request carrying a
  different/attacker-supplied `user_id` in the body still only ever reads
  and returns the JWT-authenticated user's own closet items, verified by
  asserting both the exact `userId` the mocked repository was called with
  and that no fixture item belonging to a different mocked user ever
  appears in the response.
- `deno fmt --check` and `deno lint` both pass cleanly.

**Not verified, and not claimed to be:**

- This has **not** been run against a live Supabase project or the
  Supabase CLI's local Docker stack (`supabase start` / `supabase functions
  serve`) — Docker isn't available in this environment. The `curl`
  walkthrough above is written to be run by a developer who does have
  Docker, not something this exercise executed itself.
- Row Level Security actually blocking a second real user's JWT from
  reading the first user's `closet_items` was verified for the *schema* in
  `supabase/migrations/` (see that directory's own README/verification
  notes) but not re-verified end-to-end through this specific Edge
  Function against a running Postgres — the handler-level test above
  verifies the function's own logic never *attempts* to read anything but
  the caller's own scope; it cannot, by itself, prove Postgres RLS is
  correctly configured on a real deployed database.
- No load/latency testing against spec §20 targets.

Do not treat "the tests pass" as equivalent to "this is deployed and
working" — run the `curl` walkthrough above against a real local or hosted
Supabase stack before considering this endpoint done.

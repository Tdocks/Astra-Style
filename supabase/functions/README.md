# Astra Style — Supabase Edge Functions

This directory holds the Deno/TypeScript Edge Functions for Astra Style.
Supabase routes `/functions/v1/{slug}/{rest}` by the FIRST path segment
only, so each function here is named after the first segment of the spec
§14 endpoint paths it serves and routes internally on the remainder via
`_shared/routing.ts` — `outfits/` serves `POST /outfits/generate` today and
`POST /outfits/rank` when Phase 4 builds it. Twelve grouped functions will
serve all 16 §14 endpoints; see `docs/adr/0013-edge-function-routing.md`
for the full slug table and why the obvious alternative (one hyphenated
function per endpoint) was rejected. `outfits` is the first one, built as
the template the other eleven will be copied from. Read
`docs/01-build-roadmap.md`'s "Vertical slice first" section and
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
    routing.ts               In-function path routing for grouped functions (ADR 0013)
    supabaseClient.ts        Caller-scoped (never service-role) Supabase client factory
    time.ts                  ISO-8601 normalization for timestamps on the wire
    validation.ts            Small schema-validation helpers (UUID, string, int range, ...)
    providers/               Spec §8's provider protocols — interfaces + adapters
      types.ts                 Shared request envelope, error taxonomy, model tiers
      stylistReasoning.ts      StylistReasoningProvider (docs/08 §1)
      visionAnalysis.ts        VisionAnalysisProvider (docs/08 §2)
      mockVisionAnalysis.ts    Deterministic mock used by default
      openaiVisionAnalysis.ts  Optional live adapter (env-gated; wired only in closet/index.ts)
  closet/                 POST /closet/analyze-item, POST /batch-analyze, GET /batch-status/:id
    README.md               Env gate for VISION_ANALYSIS_PROVIDER=openai + §2.5 pilot checklist
    index.ts                Deployment entrypoint — THE ONE LINE THAT PICKS THE VISION PROVIDER
    handler.ts               analyze-item (idempotent) + batch enqueue/poll (never sync fan-out)
    schema.ts / mapper.ts    Wire DTOs matching ClosetItemAnalysisResult + provider→wire map
  outfits/                POST /outfits/generate (and, in Phase 4, POST /outfits/rank)
    index.ts                Deployment entrypoint (Deno.serve + createRouter + wiring)
    handler.ts               Testable request handler for /generate (all deps injected)
    schema.ts                Request/response DTOs + body validation
    scorer.ts                 THE DETERMINISTIC SLICE SCORER — see its header comment
    *_test.ts                 Deno.test suites, one per module
  profile/                POST /profile/complete-onboarding (P2-ONBOARD-12)
    index.ts                 Wiring; calls the complete_onboarding() RPC
    handler.ts               Auth, rate limit, validation, logging
    schema.ts                The §6.9 preference vector's absent-vs-zero round trip
  style-dna/              POST /style-dna/generate (P2-CORE-02)
    index.ts                 Wiring — AND THE ONE LINE THAT PICKS THE PROVIDER
    handler.ts               Builds the StylistCompletionRequest; validates the output
    context.ts               Retrieval -> context packet (carries nothing identifying)
    deterministicStylist.ts  The mock StylistReasoningProvider + the composer
    identityPlaybook.ts      Per-identity palettes, silhouettes, signature pieces
    schema.ts                Response DTO + the validator every provider must pass
  account/                DELETE /account (P7-PRIVACY-01) — cascading account deletion
    index.ts                 Wiring, incl. the two Supabase clients (caller-scoped +
                              service-role) and the recursive Storage sweep
    handler.ts               Orchestrates the migration's documented deletion sequence
    schema.ts                Why this endpoint's request body has nothing to validate
```

## Why `POST /profile/complete-onboarding` writes through a Postgres function

Four `upsert` calls are four transactions, and a failure between the second and
the third leaves a half-written profile that every downstream consumer reads as
complete but thin. The client keeps its local draft until the server accepts, so
a *failed* call costs one retry tap and loses nothing — a *partially succeeded*
one is silent and permanent. `complete_onboarding()`
(`supabase/migrations/20260730190000_complete_onboarding_rpc.sql`) does all four
writes in one plpgsql body, i.e. one transaction, and takes no user-id parameter
at all: `auth.uid()` is the only identity source, so the ownership requirement
has no code path to be violated through. It is `SECURITY INVOKER`, so RLS is
still the boundary.

## The provider seam in `style-dna`

`style-dna/index.ts` constructs a `StylistReasoningProvider` (spec §8,
`docs/08-provider-abstraction.md` §1) and hands it to the handler. Today that is
`DeterministicStylistProvider` — no model call, no key, ten distinct identity
playbooks, and output that gets shorter rather than vaguer as input thins out.
Replacing it with a live vendor adapter is that one expression; nothing else in
this repo, and nothing at all in `ios/`, changes. `style-dna/handler_test.ts`
asserts exactly that by running one request through two unrelated providers and
comparing everything except the content and the reported model id.

What a live adapter still needs, so nobody assumes it is a small job: a vendor
account under API-tier terms with training opted out (spec §29 is a hard legal
gate), its key set via `supabase secrets set`, an adapter that keeps every
vendor concept inside itself, the shared retry/circuit-breaker baseline
(`docs/08` §0.1), the escalation router (`docs/09` §2), and the golden-set and
guardrail evals (`docs/06` §7.1–7.2) run against
`STYLE_DNA_SYSTEM_PROMPT_VERSION` before it ships.

Every future endpoint (`closet/analyze-item`,
`kyra/respond`, etc.) should follow the same shape: a function directory
named after the endpoint path's first segment, a thin `index.ts` that
builds its route table with `_shared/routing.ts`'s `createRouter` and does
the wiring, one `handler.ts` per endpoint with injected dependencies for
testability, a `schema.ts` for request validation, and reuse of everything
in `_shared/` rather than reimplementing routing, JWT validation, error
envelopes, logging, CORS, or rate limiting per function. An endpoint whose
first segment already has a function (`outfits/rank` -> `outfits/`) is a
new route in that function's `index.ts`, NOT a new function — and the
mapping test in
`ios/AstraStyle/Tests/UnitTests/EndpointDeploymentMappingTests.swift` will
fail the build if a directory appears here whose name isn't a first
segment the client actually uses.

## Why no service-role key in `outfits`

Spec §15: "Service role keys exist only in Edge Functions. Never ship them
in the app." That's a necessary condition, not a license to use the
service-role key by default *inside* an Edge Function. `outfits`
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

`outfits/scorer.ts` implements `OutfitScorer`, an interface with
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
supabase functions serve outfits
```

`supabase functions serve` prints the local URL, typically
`http://localhost:54321/functions/v1/outfits` — the endpoint itself lives
at `/functions/v1/outfits/generate`, the same shape the iOS client builds
(the platform routes on the `outfits` segment; `_shared/routing.ts`
dispatches on `/generate`).

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

curl -sS -X POST 'http://localhost:54321/functions/v1/outfits/generate' \
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

deno check _shared/*.ts outfits/*.ts   # or: deno task check
deno test --allow-env _shared/ outfits/  # or: deno task test
deno fmt --check _shared/ outfits/       # or: deno task fmt-check
deno lint _shared/ outfits/              # or: deno task lint
```

`deno test` needs `--allow-env` only because `_shared/supabaseClient.ts`
reads `Deno.env.get(...)` at module scope in a code path some tests import
transitively for type purposes; no test in this suite makes a network call
or touches a real Supabase project — every Supabase/Auth interaction is
mocked at the `AuthClient`/`ClosetRepository` interface boundary (see
`outfits/handler_test.ts`'s header comment).

`outfits/index.ts` (the `Deno.serve` wiring) is intentionally *not*
covered by a unit test — it's wiring plus a route table, and the dispatch
behavior it delegates to is covered by `_shared/routing_test.ts`, while the
parts worth testing beyond that (does a real JWT get accepted? does RLS
actually block another user's rows?) require a real Supabase Auth +
Postgres to mean anything, which is what the `curl` walkthrough above and
`supabase functions serve` are for. `deno check` does still type-check it.

## Deploying

```bash
supabase login
supabase link --project-ref <your-project-ref>

# Set every provider/config secret an Edge Function needs (SUPABASE_URL and
# SUPABASE_ANON_KEY are provided automatically for deployed functions; do
# NOT set SUPABASE_SERVICE_ROLE_KEY here unless a function actually needs
# it — outfits does not).
supabase secrets set STYLIST_PROVIDER_API_KEY=... # only when a function needs it

# Optional: live VisionAnalysisProvider for closet/analyze-item (docs/08 §2.5).
# Default is mock. Both vars required or the function stays on the mock.
# Completing this opt-in does NOT close the §2.5 menswear-subcategory pilot
# gate — see closet/README.md and docs/08 §2.5 / §2.5.1 before real users.
# supabase secrets set VISION_ANALYSIS_PROVIDER=openai VISION_PROVIDER_API_KEY=...
# (spec §25's per-capability name. It was `OPENAI_API_KEY` here until
#  2026-08-07, which is a name nothing ever set — see closet/README.md.)

supabase functions deploy outfits
supabase functions deploy closet
```

After deploying, repeat the `curl` invocation above against
`https://<project-ref>.supabase.co/functions/v1/outfits/generate` with a
real project JWT and anon key (`supabase status` for local, the dashboard's
Project Settings -> API for hosted).

## Verification performed on this function (and what was not verified)

Verified in this environment (no live Supabase project or Docker available
here):

- `deno check` passes with zero errors across every `_shared/` and
  `outfits/` file, including `index.ts`, under `strict: true` (no
  `any` anywhere in this function's own code).
- `deno test --allow-env _shared/ outfits/` passes: **83 tests, 0
  failures** (65 from the original slice, 15 for `_shared/routing.ts`'s
  dispatch/404/405/preflight behavior, plus subsequent additions), covering
  (among others) a missing JWT, a malformed JWT, a JWT
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

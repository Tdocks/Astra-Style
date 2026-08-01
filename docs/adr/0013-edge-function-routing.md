# 0013. Edge Function routing: grouped slugs with in-function path routing

## Status

Accepted

## Context

Spec §14 defines 16 endpoints with slash-shaped paths — `POST /outfits/generate`,
`POST /profile/complete-onboarding`, `GET /studio/status/:id`, `DELETE /account`,
and so on — and the iOS client builds exactly those URLs: `AstraEndpoint.path`
returns the §14 path verbatim and `AstraAPIClient` appends it to
`{SUPABASE_URL}/functions/v1/`.

Supabase, however, routes `/functions/v1/{slug}/{rest}` to a deployed Edge
Function by the **first path segment only** — the function's slug. Everything after
the slug is passed through to the function untouched, and it is the function's own
job to interpret it. There is no platform-level way to alias `/outfits/generate`
to a function named `outfits-generate`.

The vertical slice shipped with exactly this mismatch: the one deployed function
was named `outfits-generate`, so its URL was `/functions/v1/outfits-generate`,
while the client called `/functions/v1/outfits/generate` — a URL whose first
segment (`outfits`) matched no deployed function at all. Verified live against the
production project:

```text
POST /functions/v1/outfits-generate  -> 401   (function exists; correctly demands a JWT)
POST /functions/v1/outfits/generate  -> 404   (the URL the app actually builds)
```

Every §14 endpoint has this shape, so without a decision here the same bug would
have been re-created 15 more times. It went unnoticed because every layer that
could have caught it was checking something other than the client's real URL: the
Deno tests exercise `handler.ts` directly (no URL involved), the Swift tests
mocked the repository layer, and `scripts/verify-deployment.sh` curled the
hyphenated slug the deploy used — green throughout, while the app could not
generate a single outfit against production.

## Decision

1. **§14's URL shapes are preserved verbatim.** The spec is the source of truth
   (CLAUDE.md's document hierarchy), it states these paths explicitly, and the
   client already implements them. The deployment layout bends to the spec, not
   the other way around.
2. **Edge Functions are named after the first path segment and group every
   endpoint sharing it**, doing internal routing on the path remainder:

   | Function slug   | §14 endpoints served                          |
   |-----------------|-----------------------------------------------|
   | `outfits`       | `POST /generate`, `POST /rank`                |
   | `profile`       | `POST /complete-onboarding`                   |
   | `style-dna`     | `POST /generate`                              |
   | `closet`        | `POST /analyze-item`, `POST /batch-analyze`, `GET /batch-status/:id` |
   | `daily-brief`   | `POST /generate`                              |
   | `kyra`          | `POST /respond`                               |
   | `products`      | `POST /extract`, `POST /evaluate`             |
   | `studio`        | `POST /generate`, `GET /status/:id`           |
   | `packing`       | `POST /generate`                              |
   | `subscriptions` | `POST /sync`                                  |
   | `app-store`     | `POST /webhook`                               |
   | `account`       | `DELETE /` (the function root)                |

   Twelve deployed functions serve the sixteen endpoints.
3. **Routing on the remainder is done by one shared helper**,
   `supabase/functions/_shared/routing.ts` (`createRouter(slug, routes)`), not
   per-function hand-rolled pathname parsing. It normalizes the
   environment-dependent path prefix, matches method + pattern (with `:param`
   capture), answers CORS preflight for any path, returns 405 for a known path
   with the wrong verb and 404 in the project's standard error envelope
   (`_shared/errors.ts`) for anything else. `outfits/index.ts` is the reference
   usage; the eleven functions that don't exist yet copy it.
4. **The gap that kept this invisible is closed in both directions.**
   `scripts/verify-deployment.sh` now derives its checked URL from
   `AstraEndpoint.swift` (the client's own path for `POST /outfits/generate`)
   instead of a hand-written slug, and
   `ios/AstraStyle/Tests/UnitTests/EndpointDeploymentMappingTests.swift` asserts
   that every `AstraEndpoint` path's first segment is a known function slug and
   that every directory under `supabase/functions/` is a slug the client actually
   uses — so a re-introduction of this mismatch fails in CI, not in production.

## Consequences

### Positive

- The client, the spec, and production agree on every URL, and two independent
  automated checks (the Swift mapping test, the verify script) now fail if they
  ever stop agreeing.
- **Adding an endpoint now usually means adding a route, not a function.** When
  `POST /outfits/rank` is built (Phase 4), it is a new `handler.ts` plus one line
  in `outfits/index.ts`'s route table — no new deploy target, no new slug, no new
  cold-start surface.
- Fewer, warmer isolates: 12 functions instead of 16 directly serves
  `docs/11-risk-register.md` §9b (Edge Function cold starts). Related endpoints
  (`outfits/generate` + `outfits/rank`; `products/extract` + `products/evaluate`)
  share an isolate, so traffic to one keeps the other warm — and those pairs also
  share dependencies (the scoring core, the product extraction stack), so the
  grouping matches the natural module boundaries anyway.
- One shared router means one place where trailing slashes, method mismatches,
  parameter decoding, and the 404 envelope shape are decided — not twelve
  slightly-different reimplementations to keep consistent.

### Negative (real costs, named)

- **Grouped functions share a fate at runtime.** A crash-looping deploy, a
  saturating traffic spike, or a memory blowout in one endpoint degrades every
  endpoint in its group; per-function metrics and limits in the Supabase
  dashboard are now per-*group*, and the in-memory rate limiter
  (`_shared/rateLimit.ts`) is likewise shared across a group's endpoints. For the
  current groupings (at most two closely-related endpoints per slug) this is
  acceptable; a future high-traffic split (e.g. `kyra` growing sub-endpoints)
  should revisit the grouping for that slug rather than abandon the pattern.
- **Grouped functions also deploy as a unit.** Shipping a fix to `outfits/rank`
  redeploys `outfits/generate` with it — a smaller blast radius than a monolith,
  but a larger one than one-function-per-endpoint. Append-only route tables and a
  handler-per-endpoint file layout keep the shared surface small, but the
  coupling is real.
- The in-function router is a small piece of infrastructure this project now
  owns: URL semantics (encoding, trailing slashes, prefix differences between
  `supabase functions serve` and production) are handled in our code rather than
  by the platform. It has its own test suite (`_shared/routing_test.ts`)
  precisely because getting these edge cases subtly wrong is the failure mode
  this ADR exists to prevent.
- Renaming the deployed slug (`outfits-generate` → `outfits`) orphans the old
  function on any project it was already deployed to; it must be deleted (or at
  minimum ignored) there. Nothing legitimate calls it — no released client ever
  successfully used it — so deletion is safe.

## Alternatives Considered

- **Flatten the client's paths into hyphenated slugs (one function per §14
  endpoint):** `AstraEndpoint.path` returns `outfits-generate`,
  `profile-complete-onboarding`, `studio-status/{id}`, etc., matching one
  deployed function per endpoint with no in-function routing. Rejected: it
  rewrites the spec's stated contract to fit a deployment detail, inverting the
  document hierarchy (CLAUDE.md: "if the spec and the code disagree, the spec
  wins"); §14's paths are load-bearing prose referenced across
  `docs/01-build-roadmap.md`, `docs/02-task-breakdown.md`,
  `docs/05-wardrobe-graph.md`, and the risk register, all of which would silently
  drift from reality; it maximizes isolate count (16), the direction risk §9b
  says to avoid; and `GET /studio/status/:id` still needs in-function path
  parsing for its `:id` anyway, so the alternative doesn't even fully eliminate
  routing — it just spreads it out.
- **One catch-all function serving all 16 endpoints** (slug `api` or similar,
  full internal router). Rejected: it would require changing the client's URLs
  anyway (`/functions/v1/api/outfits/generate`), so it shares the flattening
  alternative's spec-contradiction problem while also concentrating every
  endpoint into a single deploy/failure/metrics unit — the "shared fate" cost
  above at maximum size, plus one bundle carrying every provider dependency,
  which worsens the very cold-start behavior grouping is meant to help.
- **Keep hyphenated slugs but add a redirecting shim** (each slash path served by
  a tiny function that proxies to the hyphenated one). Rejected outright: twice
  the deployed surface, added latency on every request, and both other options
  solve the problem without any of that machinery.

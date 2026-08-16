# 17 — Completion plan: Phases 5, 6 and 7

Written 2026-08-16, against `d5a1c175`. This is the dependency-ordered route from
"the core loop works on a phone" to "submittable, chargeable product".

Owner's decision, recorded so nobody re-litigates it mid-way: **all of it, in
dependency order, with full Phase 5** — every server tool, not a voice-only
first cut. There is no intermediate public release baked into this plan.

Every factual claim below was checked against the repo by a separate agent
before this document was committed. Fourteen claims in the first draft were
wrong; §13 records the ones worth remembering, because two of them were
inherited from `docs/03-progress.md` and are still wrong *there*.

---

## 1. The number that matters is not 65

`docs/03-progress.md` reads 71 tickets Not started, 49 Partial for Phases 5–7.
That framing makes this look like 65 features to invent. It is not, and reading
it that way would produce a plan that is wrong about where the risk is.

**The data layer is already built and already RLS-tested for every remaining
phase.** So are most of the repositories:

| Already in production | Ticket |
|---|---|
| `kyra_threads`, `kyra_messages`, `style_memories` + embeddings + RLS | P5-KYRA-01 Done |
| `studio_generations` + RLS | P6-STUDIO-01 Done |
| `product_candidates`, `user_product_evaluations` + RLS | P6-SHOP-01 Done |
| `subscriptions` + RLS, both `AstraProductID`s defined | P7-SUB-01 Partial |
| `account_deletions` + `request_account_deletion()`, `finalize_account_deletion()`, `mark_account_deletion_complete()`, `mark_account_deletion_failed()` | P7-PRIVACY-01 Partial |

On the client, `LiveKyraRepository` fully implements its protocol,
`LiveStudioRepository` and `LiveSubscriptionRepository` conform, and
`LiveShoppingRepository` implements three of seven methods (though two of the
three call endpoints that are not deployed — only `fetchCuratedProducts`
reaches a table that exists).

On the server, `_shared/` holds the routing helper (ADR 0013), rate limiting,
JWT, CORS, the error envelope, the whole `scoring/` engine, and
`providers/stylistReasoning.ts` — the tool-calling **interface**, which already
has one working implementation behind it in `style-dna/deterministicStylist.ts`.
What Kyra needs is a live vendor adapter and the tool-calling loop, not a
provider abstraction from zero.

**What is actually missing is seven Edge Function groups and roughly twenty
screen-level tickets.** `EndpointDeploymentMappingTests` pins twelve expected
slugs; `supabase/functions/` contains five. The seven absent:

`kyra` · `studio` · `products` · `packing` · `subscriptions` · `app-store` · `account`

The spine exists; both ends are open. The corollary is where the risk sits.
This is not "will it work" risk — the hard modelling was done in `docs/06`,
`docs/09` and `docs/10`. It is volume risk, plus three external dependencies
(§11) that no amount of code closes.

---

## 2. Cross-cutting gates

These are not a wave. They block or bite everywhere, and each has a home below.

**G1 — `EndpointDeploymentMappingTests` pins `requiredNow`** (five slugs today).
Every new deployed function must be added, or the test lies about what
production serves. Update it in the same commit that deploys.

**G2 — rate limiting is already the house pattern; keep it that way.** All five
deployed functions call `deps.rateLimiter.check(...)` with a limit chosen for
that endpoint — outfits 20/min, closet 30, daily-brief 10, profile 6, style-dna
5. A new endpoint that ships without one is the exception, not the norm. Kyra's
per-tier limit (P5-KYRA-19) is the one that needs real design rather than a
number, because it is also a paid-tier boundary.

**G3 — `LiveAnalyticsClient.log()` is a DEBUG print and no `analytics_events`
table exists.** Nothing that ships from here is measurable until this is built.
It is scheduled in Wave 3 rather than Wave 8 for that reason — shipping Studio
and commerce blind and instrumenting afterwards wastes the only real usage data
this project will get.

**G4 — the annual price.** `$79.99/yr` against `$12.99/mo` is 48.7% off, and per
`docs/09` §5.6 leaves inference alone consuming 27.9–33.9% of net revenue on the
annual plan. Decide before Wave 4 writes it into App Store Connect; changing it
after anyone subscribes is not free. (Nothing in the repo indicates plan mix —
the assumption that annual dominates is an assumption.)

**G5 — commit discipline unchanged.** Short imperative subject, a body that says
WHY, a VERIFIED line. SwiftLint `--strict` clean, full suite green, and a device
build before every commit that touches iOS.

---

## 3. Wave 1 — Kyra, server side

**Tickets:** P5-CORE-01, P5-KYRA-03, -02, -04, -05, -06, -07, -08, -09, -10,
-11, -12, -19.
**Blocks:** Wave 2, P6-SHOP (via -11's stubs), P7-PRIVACY-07.
**Blocked by:** nothing.

Start with **P5-CORE-01**, out of numeric order and before any server code.
`KyraStructuredResponse`/`KyraIntent` use synthesized `Codable`, so an unknown
intent or a missing optional throws instead of degrading to `.general`.

**Widen that ticket to cover `KyraCard`.** `KyraResponse.swift`'s `CardType`
decoder has no fallback case either, and P5-KYRA-14's acceptance criterion
requires an unrecognized card type to degrade safely rather than crash — but the
plan-shaped reading of -14 is "build the view", so the decode-side defect sits
between two tickets and belongs to neither. It belongs here.

Then the packet before the endpoint: **P5-KYRA-03** (context-packet builder,
token budget and truncation order per `docs/06` §1), **P5-KYRA-02**
(`POST /kyra/respond`, grouped-slug routed like every other function).

Then the eight tools. Six are thin wrappers over engines that already exist and
are unit-tested — the cheapest part of the wave:

| Tool | Ticket | Sits on |
|---|---|---|
| `search_closet` | P5-KYRA-04 | `closetItemMapper.ts` |
| `rank_outfits` | P5-KYRA-05 | `compatibilityScorer.ts`, `outfitScorer.ts` |
| `create_outfit` | P5-KYRA-06 | `outfits/` save path |
| `get_weather` | P5-KYRA-07 | client-supplied snapshot, as `daily-brief` already does |
| `get_schedule` | P5-KYRA-08 | `occasions` table |
| `save_preference` | P5-KYRA-09 | `style_memories` |
| `mark_item_worn` | P5-KYRA-10 | `bump_closet_item_wear_stats()` trigger |
| Phase-6 stubs | P5-KYRA-11 | declared, returning "not built yet" honestly |

`get_weather` deserves care: there is no server-side weather provider by design,
so the tool reads what the client sent up. A tool that silently invents a
forecast is the confounded reading this repo keeps refusing.

Finish with **P5-KYRA-12** (guardrails — no sensitive-trait inference, no
medical advice, no fit certainty from imagery, affiliate disclosure, generated-
image labelling) and **P5-KYRA-19** (per-tier rate limiting, which hands Wave 4
something real to gate).

**Done when:** `POST /kyra/respond` is deployed, every tool has a Deno test, the
guardrail layer has a test per prohibited category, and G1 is satisfied.

---

## 4. Wave 2 — Kyra, client side

**Tickets:** P5-KYRA-18, -13, -14, -15, -17, -16, P5-TEST-01, P5-TEST-02.
**Blocked by:** Wave 1.

`LiveKyraRepository` already conforms; **P5-KYRA-18** is only its offline-cache
criterion, which `AstraModelContainer` currently declines by design. Resolve it
one way or the other and record which — a conversation cache is a real design
question, not an oversight, and "network-first" may be the right answer stated
properly.

Then **P5-KYRA-13** (conversation screen), **-14** (structured card renderer —
`KyraCard` exists as a model with no view; its decoder is Wave 1's problem),
**-15** (suggested prompts), **-17** (memory inspection and deletion, which is
also a privacy surface), **-16** (voice input, last because it is the only one
that needs a new permission).

**P5-TEST-01** covers one intent's happy path. It owes the other five and a
malformed-payload case — the test that proves P5-CORE-01. **P5-TEST-02** is an
`XCTSkip` that names the assertions it owes; make it real.

**Done when:** you can ask Kyra a question on the device, she can act on the
closet, and Home's "why this look" line comes from her rather than the scorer.

---

## 5. Wave 3 — Account, privacy, and instrumentation

**Tickets:** P7-PRIVACY-01, -02, -03, -06, plus G3's `analytics_events` table.
**Blocked by:** nothing that is not already satisfied — P7-PRIVACY-01 formally
depends on P7-SUB-01 and the Phase 1–6 migrations, all of which have landed.
**Blocks:** any external TestFlight.

Note that **P7-PRIVACY-07 is NOT in this wave**, despite being a privacy
ticket. It audits every Edge Function's logging for leakage, and it formally
depends on P5-KYRA-02 and P6-STUDIO-04 — two functions that do not exist until
Wave 5 is done. It moves to Wave 8.

Pulled the rest early deliberately: independent of Kyra, the App Store gate
(Guideline 5.1.1(v)), and the database side is already production-grade.
**P7-PRIVACY-01 is the most misleadingly advanced ticket in the repo** — the
cascade, the RLS and all four SQL functions exist and are hardened, and no
`DELETE /account` Edge Function exists, so no deletion can happen at all.

**Two traps in -01, both load-bearing:**

1. **The slug.** `AstraEndpoint.deleteAccount.path` is `"account"`, so
   `EndpointDeploymentMappingTests` requires `supabase/functions/account/`. The
   migration's own orchestration comment says to build it at
   `supabase/functions/account-delete`. Following the migration produces exactly
   the ADR-0013 404 that test exists to prevent. Build it at `account/`, and fix
   the migration comment in the same commit.
2. **`finalize_account_deletion(p_deletion_id uuid)` does not delete user
   rows.** It scrubs `storage.objects` under `users/{user_id}/` as defence in
   depth and sets the row to `processing`. The actual cascade happens through
   `auth.admin.deleteUser()` at orchestration step 5, and the endpoint must also
   call `mark_account_deletion_complete()` / `mark_account_deletion_failed()`.
   The row inventory is prose in the migration header, not code — so the
   endpoint's test has to assert emptiness table by table itself.

Order: the endpoint (**-01**), the UI (**-02**), export (**-03**, which shares
the cascade's inventory of what a user owns), training opt-out and ATT (**-06**).

**Done when:** a real account can be deleted from inside the app, and a test
asserts row counts are zero across every table the migration header names.

---

## 6. Wave 4 — Subscriptions

**Tickets:** P7-SUB-01…-07, P7-TEST-01, -03, -05.
**Blocked by:** G4 (the price), Wave 1 (Kyra limits to gate), Wave 3 (ATT
ordering).

**This wave cannot fully close until Wave 5 ships.** P7-SUB-04's declared
dependencies include P6-STUDIO-07, because the Studio quota is one of the three
things entitlement gates. Land -04 with two of its three gates and finish it in
Wave 5 — but write it knowing the third is coming, rather than discovering it.

Order: App Store Connect configuration and the checked-in `.storekit` file
(**-01**, and **-06**'s config half — `ios/README.md` currently tells a
developer to hand-make one, which is how two machines end up disagreeing), then
the purchase flow (**-02**), server reconciliation and the App Store webhook
(**-03**, which is two of the seven missing slugs: `subscriptions` and
`app-store`), entitlement gating (**-04**), the paywall (**-05**), restore
(**-06**), repository wiring (**-07**).

**-04 is the one to be careful with.** Entitlement today is a status boolean. It
has to become three real gates: the 30-item closet cap (which already exists in
`FreeTierCappedClosetRepository` and needs connecting, not writing), Kyra's
three-a-day limit from P5-KYRA-19, and the Studio quota from P6-STUDIO-07.

**Done when:** a sandbox purchase unlocks the closet and Kyra gates, restore
works on a second device, and P7-TEST-03 is no longer `.disabled()`.

---

## 7. Wave 5 — Style Studio

**Tickets:** P6-STUDIO-02, -03, -04, -06, -05, -07, -12, -08, -09, -10, -11,
P7-PRIVACY-04, P6-TEST-01, and the close-out of P7-SUB-04.
**Blocked by:** Wave 4's entitlement scaffold, and an external dependency (§11).

**Reference capture comes first, not last.** P6-STUDIO-04's declared
dependencies include P6-STUDIO-02, and -02 owns the consent gate —
`LiveStudioRepository.startGeneration` already refuses without
`request.hasUserConsent`, so `/studio/generate` has no reference path and no
consent record to validate until -02 exists.

So: **-02** (reference capture + consent), **-03** (provider protocol), **-04**
(`POST /studio/generate`), **-06** (status endpoint and job-queue states),
**-05** (prompt-template assembly, designed in `docs/10` and `docs/15`), **-07**
(cost controls, caching, and the abandoned-source-image retention job — this is
also what closes P7-SUB-04).

Then the rest of the client: **-12** is a repository that conforms but is
single-shot against an undeployed endpoint and needs a real polling loop with
backoff. Then the main screen (**-08**), presets (**-09**, whose data model is
already complete and spec-exact with zero UI exposing any of it), generation
state (**-10**), gallery and save-to-lookbook (**-11**).

**P7-PRIVACY-04** (delete individual reference and generated images) lands here,
not Wave 3, because it has nothing to delete until **-11** exists.

**Done when:** a generation completes end to end on device, the retention job
has removed an abandoned source image, and quota denial shows the paywall rather
than an error.

---

## 8. Wave 6 — Commerce

**Tickets:** P6-SHOP-02, -03, -04, -09, -05, -06, -07, -08, -10, P6-TEST-02.
**Blocked by:** Wave 1 (P5-KYRA-11's stubs become real here).

Extraction provider (**-02**), `POST /products/extract` (**-03**),
`POST /products/evaluate` (**-04** — the algorithm exists as
`_shared/scoring/unlockCount.ts`, unit-tested with no caller).

**Do -09 before any UI.** Sponsored-vs-organic separation needs a `sponsored`
field that exists in neither the models nor the migration. Adding it after the
decision page is built means retrofitting a labelling guarantee onto screens
designed without it, and §11's guardrail — affiliate availability must not
change the verdict — is exactly the rule a late schema change quietly violates.

Then the decision page (**-05**), Shop the look (**-06**), affiliate redirect
and wishlist (**-07** — needs the `wishlist_items` migration that was
deliberately deferred until the UI that has to live with the schema existed;
that UI now exists, so write it here), ingestion (**-08**), repository
completion (**-10**).

**Done when:** pasting a retailer link produces a verdict, every listed product
carries its disclosure, and a non-affiliate alternative that scores higher is
still recommended — with a test that proves it.

---

## 9. Wave 7 — The remaining surfaces

**Tickets:** P7-HOME-05, -03, -04, -01, -02, P6-CORE-01.

Profile and stats (**-05** — `Features/Profile/` contains one `README.md` and no
Swift at all; the tab renders `FeaturePlaceholderView`), monthly review
(**-03**), packing assistant (**-04**), notification scheduling (**-01**), then
the in-context permission timing audit (**-02**, which can only run once
notifications and voice input both exist). **P6-CORE-01**'s Discover screen
needs an editorial-content table that no migration creates.

**P7-HOME-04 is not client-only.** `AstraEndpoint.generatePacking` maps to
`packing/generate` — the seventh missing slug. Budget server work for it.

These are genuinely lower priority than everything above and are the natural
place to cut scope if the plan runs long.

---

## 10. Wave 8 — Hardening and submission

**Tickets:** P7-PRIVACY-07, P7-INFRA-01, P7-DS-01…-04, P7-INFRA-02, -03, -04,
-05, P7-TEST-02, -04, -06, -07, -08, P7-PRIVACY-05.

**P7-PRIVACY-07** and **P7-INFRA-01** land here rather than earlier for the same
reason: both are sweeps over *every* Edge Function, and both are wasted effort
until all twelve exist.

The four design-system audits could not run before now because two of the five
screens P7-DS-01 requires — the Kyra conversation and the paywall — did not
exist. Same for P7-DS-04's Kyra orb and Studio alt-text.

**P7-TEST-07** needs a snapshot-testing library wired in from scratch. That is a
dependency decision; this repo has exactly one dependency today.

**P7-PRIVACY-05** is the legal publish: register `astrastyle.app` (NXDOMAIN as
of 2026-07-30), fill the `[[NEEDS INPUT]]` placeholders enumerated in
`legal/README.md`, get review, upload to the public `legal` bucket, flip
`AstraLegal.isPublished`, update `LegalDocumentAvailabilityTests`.

**P7-TEST-08** is the full §30 definition-of-done run, and it is last.

---

## 11. External dependencies no amount of code closes

1. **The OpenAI billing hard limit.** Already blocking regeneration of the one
   quiz image pair that would lift `silhouette` above permanent low confidence.
   Wave 5 is image generation as a *product feature* — roughly $0.05 per
   generation on the planning rate, against a $12.99/month subscription. Raise
   the limit before Wave 5, not during it.
2. **Apple.** External TestFlight requires Beta App Review; internal testing does
   not, but internal testers must be App Store Connect users on the team.
   Sandbox StoreKit testing in Wave 4 needs products configured in App Store
   Connect first, and that configuration is not demonstrable in-repo — which is
   why P7-SUB-01 is Partial with one Unverifiable component rather than Done.
3. **A lawyer, for P7-PRIVACY-05.** The placeholders should not be invented.

---

## 12. How this gets tracked

The eight waves schedule **79 tickets**, not 65. The 65 figure is the *Not
started* count for Phases 5–7 and silently drops the ~14 Partial tickets that
also need finishing.

`docs/03-progress.md` has not been updated since before the Home redesign and
the Closet looks carousel, so it currently undercounts — and, per §13, two of
its statements are now wrong rather than merely stale. Update it at the close of
each wave, not per ticket: per-ticket updates on a 79-ticket plan produce a
document nobody reads.

Each wave closes with `scripts/check_progress.py` green, SwiftLint `--strict`
clean, the full test suite green, a device build installed, and the wave's "Done
when" line demonstrated on the phone rather than argued for in a commit message.

---

## 13. Corrections this document had to make to itself

Recorded because the two marked ✗ are wrong in `docs/03-progress.md` today and
will re-infect the next plan that reads it.

- ✗ **"`Features/Profile/` holds only the guest stub."** There is no guest stub
  anywhere — guest mode was removed wholesale by ADR 0014. Profile holds one
  README and no Swift.
- ✗ **"P7-SUB-01 is Unverifiable."** It is Partial; only its App Store Connect
  component is unverifiable, and Phase 7 has no Unverifiable rows at all.
- **Rate limiting is applied to all five deployed functions**, not just
  `outfits`, each with its own limit.
- **Seven Edge Function groups are missing, not five** — `packing`,
  `subscriptions` and `app-store` were invisible in the first count.
- **`stylistReasoning.ts` already has an implementation**
  (`style-dna/deterministicStylist.ts`); the gap is a live vendor adapter.
- **`finalize_account_deletion()` takes an argument and deletes no user rows.**
- **P6-STUDIO-04 depends on -02**, so reference capture cannot come last.
- **P7-SUB-04 depends on P6-STUDIO-07**, so Wave 4 cannot fully close before
  Wave 5.
- **P7-PRIVACY-07 depends on P5-KYRA-02 and P6-STUDIO-04**, so it is a Wave 8
  ticket wearing Wave 3's clothes.
- **P7-INFRA-01 was scheduled in no wave at all** in the first draft.
- **`DELETE /account` has a slug conflict** between the client's endpoint map
  and the migration's own build instruction.
- **`KyraCard`'s decoder throws on an unknown card type**, and as originally
  scoped neither P5-CORE-01 nor P5-KYRA-14 owned fixing it.

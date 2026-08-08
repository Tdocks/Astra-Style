# ASTRA STYLE — BUILD ROADMAP

**Source of truth:** `00-master-spec.md` (referenced below as "the spec"). Phase names and order follow spec §24. Exit criteria are written to be checkable by running the app, a test suite, or a SQL query — not by reading code.

---

## How to read this document

Each phase lists, in order: goal, ordered workstreams, hard dependencies, exit criteria, effort sizing, and risks. Sizing assumes a competent iOS/backend engineer working with an AI coding agent (Claude Code, Cursor, etc.) doing the typing, with a human directing architecture, reviewing diffs, and making product judgment calls the spec leaves open. Sizing is wall-clock, not idealized throughput — it includes debugging, App Store/StoreKit friction, and rework from wrong early guesses.

---

## Phase 1 — Foundation

**Goal:** Stand up a buildable, empty Astra Style app with real auth, real Supabase-backed persistence, and the design system tokens, so every later feature has a floor to build on instead of a green field.

**Ordered workstreams**

1. Xcode project + feature-first folder structure (spec §8).
2. Environment configuration and CI secret injection (Debug/Staging/Release `.xcconfig`, spec §25), and a CI pipeline that builds, lints, and tests every PR, failing on any warning or violation (spec §31).
3. Supabase project provisioning, base schema migration (`profiles`, `style_profiles`, `body_profiles`, `lifestyle_profiles`) with RLS on every table, and private Storage buckets with a signed-URL policy scoped to the owning user.
4. Design tokens: color, type, spacing, motion, haptics (spec §3).
5. Core networking (`APIClient` → Edge Functions), `AppContainer` DI, repository protocols (spec §8).
6. SwiftData persistence container + offline write queue primitive.
7. Root routing (`AppRouteState`), per-tab `NavigationStack` shell, modal coordinator (spec §27).
8. Authentication: Sign in with Apple, email OTP, session restore. ~~Guest mode + migration~~ — **withdrawn 2026-08-06, ADR 0014.**

*Amended 2026-07-30: this list previously had 7 items and never named Storage buckets, CI, or*
*secrets hygiene as their own workstreams, even though 3 of the 8 exit criteria below test exactly*
*those (storage bucket privacy, CI-on-PR, no leaked service-role key) — all three are real, tracked*
*work (`P1-INFRA-02`, `P1-INFRA-03`, `P1-INFRA-06`), just uncounted here. Reconciled by naming all*
*8, not by cutting any of the 8 exit criteria; see `docs/03-progress.md`'s "Acceptance criteria*
*that are wrong, rather than unmet."*

**Hard dependencies**

- *Needs to exist before this phase starts:* nothing — this is the zero point.
- *Unblocks:* every other phase. No feature work can meaningfully start until repository protocols, the DI container, and RLS-protected tables exist, because every feature ticket in Phases 2–7 is written against these interfaces.

**Exit criteria**

- [ ] A fresh install launches to a marble splash screen and routes to Welcome within 1.4 s.
- [ ] A user can sign in with Apple and land on an (empty) Home shell; killing and relaunching the app restores the session without re-authenticating.
- [x] ~~A user can enter guest mode, and the client enforces a 10-item local cap without a network call.~~ **Withdrawn, ADR 0014.**
- [ ] `profiles`, `style_profiles`, `body_profiles`, `lifestyle_profiles` exist in Supabase with RLS policies that block cross-user reads (verified by attempting a read with another user's JWT and getting zero rows, not an error).
- [ ] Storage buckets are private; an unsigned direct URL to any object returns 403.
- [ ] Tapping each of the 5 tab bar items navigates independently and preserves scroll/nav position when switching away and back.
- [ ] CI runs on every PR and fails the build on a compiler warning or SwiftLint violation.
- [ ] No Supabase service-role key or provider API key exists anywhere in the iOS target.

**Effort**

- Solo + AI agents: **3–4 engineer-weeks**.
- 3-person team: **2 wall-clock weeks** (~5–6 person-weeks; auth, schema/RLS, and design tokens parallelize cleanly).

**Risks**

- RLS policies that "work" in manual testing but have a gap (e.g., missing policy on an `INSERT`) — this is a security bug that won't surface until Phase 3+ when real user data exists. Mitigate with an automated RLS test per table, not manual QA.
- Sign in with Apple provisioning/entitlement mismatches between local, TestFlight, and App Store Connect burn unpredictable time; budget a buffer day.
- Over-building the DI container (a common trap when using an AI agent that will happily generate a large abstraction) — spec §8 explicitly says avoid a heavy third-party DI framework; keep `AppContainer` a flat struct of protocols.
- Design tokens drifting from spec §3 hex values because the agent "improves" contrast — lock values in a single source-of-truth file reviewed against the spec, not regenerated from memory.

---

## Phase 2 — Identity

**Goal:** Take a new user from account creation through a complete onboarding flow to a generated Style DNA and an empty-but-real Home screen.

**Ordered workstreams**

1. Onboarding screens in spec order: Kyra intro → style goals → style identity cards → measurements → appearance profile → lifestyle → preference quiz → optional selfie capture → add first items or skip (spec §6.3–6.9).
2. Profile repository CRUD wired to `style_profiles`/`body_profiles`/`lifestyle_profiles`.
3. `POST /profile/complete-onboarding` and `POST /style-dna/generate` Edge Functions, with `StylistReasoningProvider` behind a protocol (mock first, live provider second).
4. Style DNA result screen with edit/regenerate.
5. Home skeleton + empty state.

**Hard dependencies**

- *Needs Phase 1:* auth session, DI container, repository protocol pattern, design tokens, nav shell.
- *Unblocks:* Phase 4 (outfit generation needs `style_profiles.embedding` and the preference vector from the quiz), Phase 5 (Kyra's context packet is built from these same profile tables).

**Exit criteria**

- [ ] A new signed-in user who completes every onboarding step lands on Home with `profiles.onboarding_completed_at` set.
- [ ] A user who force-quits mid-onboarding and relaunches resumes at the step they left, not from the start.
- [ ] `POST /style-dna/generate` returns a primary identity, secondary influences, palette, silhouette direction, and priorities that are not lorem-ipsum placeholders, for a profile with only the required fields filled in (i.e., it degrades gracefully with sparse input).
- [ ] A user can edit and regenerate Style DNA and see the result change.
- [ ] Skipping "add first closet items" does not block reaching Home.
- [ ] Every onboarding field marked optional in spec §6.7 can be left blank without a validation error.

**Effort**

- Solo + AI agents: **4–6 engineer-weeks**.
- 3-person team: **2–3 wall-clock weeks**.

**Risks**

- The 12–20 image preference quiz (spec §6.9) requires curated paired imagery that doesn't exist yet — this is a content production dependency, not just engineering, and can silently block the whole phase if treated as "just wire up the UI."
- Style DNA quality is subjective and hard to unit test; a technically-working endpoint can still produce generic or repetitive output. Budget explicit human review passes against 5–10 synthetic profiles, not just "endpoint returns 200."
- Onboarding is the highest-drop-off surface in the whole app; a spec-compliant but clunky implementation (too many required-feeling steps) can look "done" while being a product failure. Track step-by-step completion instrumentation from day one, not retrofitted in Phase 7.

---

## Phase 3 — Closet

**Goal:** Let a user get real garments into the Wardrobe Graph, either by scanning or manual entry, with corrections and offline resilience.

**Ordered workstreams**

1. `closet_items` / `closet_item_images` schema + RLS.
2. Manual "add garment" form (cheapest path to a non-empty closet; also the vertical-slice dependency — see below).
3. Camera capture screen + device-side pipeline: blur/exposure detection, garment segmentation, OCR, dominant color extraction (spec §12 device-side).
4. `POST /closet/analyze-item` and `POST /closet/batch-analyze` Edge Functions with `VisionAnalysisProvider` behind a protocol.
5. Scan review/correction screen with confidence indicators.
6. Closet overview (grid/list/color-spectrum), item detail, filters, metrics.
7. Offline sync engine (queued edits, queued scans while offline).

**Hard dependencies**

- *Needs Phase 1:* storage buckets, offline queue primitive, repository protocol pattern.
- *Unblocks:* Phase 4 (outfit generation needs owned items to combine), Phase 5 (`search_closet` tool needs `ClosetRepository`), Phase 6 (product evaluation needs closet items to compare against).

**Exit criteria**

- [ ] A user can add a garment manually (name, category, color, size) without ever touching the camera.
- [ ] A user can scan a garment; the app returns suggested category/color/pattern/material/condition/fit within the spec §20 8-second target, with low-confidence fields visibly marked.
- [ ] A user can correct any suggested field before saving, and the corrected value — not the AI suggestion — is what's persisted.
- [ ] Capturing a scan while offline queues it locally and completes analysis automatically once connectivity returns, without data loss.
- [ ] The closet grid scrolls at 60 fps with 50+ items loaded (measured, not eyeballed).
- [ ] Item detail shows wear count, cost-per-wear, and last-worn-at that update correctly after a "mark worn" action.
- [ ] Free tier blocks a 31st item with a clear upgrade prompt. (The guest half of this criterion is withdrawn — ADR 0014.)
- [ ] `closet_items` and `closet_item_images` RLS blocks cross-user access (same automated test pattern as Phase 1).

**Effort**

- Solo + AI agents: **8–10 engineer-weeks**.
- 3-person team: **4–5 wall-clock weeks**.

**Risks**

- On-device segmentation quality with Vision framework varies a lot by garment/background — a "neutral background" camera flow that works in test conditions can fail badly with real users' cluttered rooms. Plan for the server-side background-removal fallback (spec §12) to be load-bearing, not a rare edge case.
- Vision provider cost and latency at scale is unknown until real usage; the 8-second analysis target (spec §20) may require choosing a faster/cheaper model over a more accurate one — this is a product tradeoff that needs to be made explicitly, not discovered in production.
- Offline sync conflict resolution (same item edited locally and remotely) is the kind of thing that's easy to skip and expensive to retrofit — do not leave it as a Phase 7 hardening task.
- Batch closet scan (multiple items in one session) is listed as "can follow shortly after" in spec §23 — do not let it block single-item scan on the critical path.

---

## Phase 4 — Outfit intelligence

**Goal:** Turn a populated closet into ranked, explainable outfit recommendations and a working Daily Brief.

**Ordered workstreams**

1. `outfits` / `outfit_items` / `outfit_wears` schema + RLS.
2. `CompatibilityScorer` — the 8-component weighted formula in spec §10, server-config-driven with a hardcoded fallback.
3. `POST /outfits/generate` and `POST /outfits/rank` Edge Functions.
4. Purchase-unlock-count algorithm and Wardrobe Score composite (spec §10).
5. Outfit detail and Outfit builder screens.
6. `daily_briefs` schema + `POST /daily-brief/generate` + Daily Brief hero card and secondary modules.
7. Wear feedback capture (`outfit_wears`, `style_feedback`).

**Hard dependencies**

- *Needs Phase 3:* real closet items to combine; needs Phase 2's `style_profiles` preference vector for the user-preference sub-score.
- *Unblocks:* Phase 5 (Kyra's `rank_outfits`/`create_outfit` tools wrap these same endpoints), Phase 6 (Studio generation prompts are built from outfit item lists; product evaluation's "outfits unlocked" reuses the unlock-count algorithm).

**Exit criteria**

- [ ] `CompatibilityScorer.score(pairing:)` returns a 0–100 value and its 8 sub-scores sum to the documented weights (0.25/0.20/0.15/0.10/0.10/0.10/0.05/0.05) in a unit test.
- [ ] A user with 5+ closet items can request an outfit and receive exactly 3 ranked outfits, each with a non-generic one-sentence reason.
- [ ] Locking an item in the outfit builder and regenerating changes only the unlocked slots.
- [ ] The Daily Brief hero card shows a real weather-conditioned recommendation, not a static fixture, for at least two different weather conditions in manual testing.
- [ ] Marking an outfit worn increments the correct `closet_items.wear_count` for every item in it and writes an `outfit_wears` row.
- [ ] A candidate product's "unlocks N outfits" count is reproducible (cached) and changes correctly when the closet changes.
- [ ] Wardrobe Score does not increase purely because the user added an expensive item with poor versatility (spec §10 explicit requirement) — verified with a fixture wardrobe unit test.

**Effort**

- Solo + AI agents: **7–9 engineer-weeks**.
- 3-person team: **4 wall-clock weeks**.

**Risks**

- Outfit quality is the core product promise and is subjective — a scorer that passes unit tests can still produce outfits that look wrong to a human stylist. Plan explicit qualitative review cycles against real photographed closets, not just numeric test coverage.
- Combination generation for the unlock-count algorithm is combinatorially large for wardrobes with 100+ items; naive enumeration will blow the 8-second-class performance budget — needs pruning/heuristics designed up front, not bolted on after a timeout in production.
- Weather provider (WeatherKit or server) is a hard external dependency for the Daily Brief's core value prop; an outage degrades the flagship screen, so a cached/last-known-good fallback is required, not optional polish.
- Client-side hardcoded fallback weights drifting out of sync with server-config weights over time, silently producing different scores offline vs online.

---

## Phase 5 — Kyra

**Goal:** Give the user a working conversational stylist that can actually act on the wardrobe, not just talk about it.

**Ordered workstreams**

1. `kyra_threads` / `kyra_messages` / `style_memories` schema + RLS.
2. Kyra context-packet builder (spec §11).
3. `POST /kyra/respond` Edge Function with structured response schema (`message`/`intent`/`cards`/`suggested_actions`/`memory_proposals`/`confidence`).
4. Server tools in priority order: `search_closet`, `create_outfit`, `rank_outfits`, `mark_item_worn`, `get_weather`, `get_schedule`, `save_preference`; stub the Phase-6-dependent tools (`analyze_product`, `search_products`, `generate_studio_preview`, `create_packing_list`).
5. Guardrail layer (no medical advice, no sensitive-trait inference, fit-certainty limits, affiliate disclosure).
6. Conversation UI, structured card renderer, memory inspection/deletion UI.

**Hard dependencies**

- *Needs Phase 4:* `create_outfit`/`rank_outfits` tools wrap `/outfits/generate` and `/outfits/rank`; needs Phase 3's `search_closet` over real closet data.
- *Unblocks:* Phase 6 (`generate_studio_preview` and `analyze_product`/`search_products` tools get wired to real endpoints once Studio/Shopping exist); the DoD acceptance criterion "ask Kyra what to wear."

**Exit criteria**

- [ ] A user can type "what should I wear tonight" and receive a response containing at least one structured outfit card, not unparsed prose.
- [ ] Kyra's response always validates against the documented JSON schema; a malformed provider response is caught and surfaces a retryable error, not a client crash.
- [ ] A user can inspect their `style_memories` and delete one; the deletion is reflected in Kyra's next response (it no longer references the deleted preference).
- [ ] Kyra never claims exact garment fit from a photo alone (verified against guardrail test prompts designed to elicit that claim).
- [ ] Free-tier users are blocked from a 4th Kyra conversation in a day with a clear upgrade prompt, and the block is enforced server-side, not just in the client.
- [ ] Voice input transcribes to text and produces the same structured response path as typed text.

**Effort**

- Solo + AI agents: **6–8 engineer-weeks**.
- 3-person team: **3–4 wall-clock weeks**.

**Risks**

- Tool-calling reliability: the reasoning provider may call the wrong tool, call it with malformed arguments, or hallucinate a result — this needs defensive parsing and fallback messaging, not an assumption that the provider always behaves.
- Structured response schema changes are a breaking-change surface between client and server; without versioning, a server-side prompt tweak can silently break the iOS card renderer in production.
- LLM cost per conversation is unknown until real usage; the 3-conversations/day free tier limit is a guess that may need to change post-launch — build the limit as server-config, not a hardcoded constant.
- Memory privacy: `save_preference` writing durable memories without a clear confidence/visibility gate risks the app "remembering" something the user considers private or incorrect — the user-visible/deletable requirement (spec §6.20, §29) must ship in this phase, not be deferred.

---

## Phase 6 — Studio and commerce

**Goal:** Let a user see themselves in a recommended outfit before buying, and get a clear buy/skip verdict on a real product.

**Ordered workstreams**

1. `studio_generations` schema + RLS; `ImageGenerationProvider` protocol.
2. `POST /studio/generate` (identity representation + structured garment prompt) and `GET /studio/status/:id` polling; cost controls (rate limits, caching, draft-before-hi-res).
3. Style Studio UI: reference capture with consent, presets/advanced controls, generation states, results gallery.
4. `product_candidates` / `user_product_evaluations` schema + `ProductExtractionProvider`; `POST /products/extract` and `POST /products/evaluate`.
5. Product decision page, Shop the look screen, affiliate redirect, wishlist.
6. Wire `generate_studio_preview`, `analyze_product`, `search_products` Kyra tools to the now-real endpoints.

**Hard dependencies**

- *Needs Phase 4:* outfit item lists are the input to Studio prompts; the unlock-count algorithm is reused in product evaluation.
- *Needs Phase 5 (soft):* the Kyra tool stubs from Phase 5 need real implementations to close the loop, but the Studio/Shopping UIs themselves can be built without Kyra.
- *Unblocks:* Phase 7's paywall (Studio quota is a premium-gated feature) and the DoD criteria "paste a retailer link" and "generate a visual styling estimate."

**Exit criteria**

- [ ] A user can select a reference image, choose an outfit, and receive a generated visual estimate within the 30-second draft target (spec §20), with a "styling estimate" disclaimer visibly attached to the image.
- [ ] A failed generation preserves the prompt, offers retry, and does not consume a quota credit when the failure is provider-side (spec §21 explicit requirement).
- [ ] A user can delete a reference image or a generated result and it is actually removed from storage, not just hidden in the UI.
- [ ] Pasting a real retailer product URL returns a compatibility score, redundancy risk, outfits-unlocked count, expected cost-per-wear, and one of buy/consider/wait/skip.
- [ ] Affiliate links open in `SFSafariViewController` or a universal link, and every affiliate placement is visibly labeled as such.
- [ ] Sponsored/affiliate availability does not change Kyra's verdict — verified with a test case where a non-affiliate alternative scores higher and is still recommended.

**Effort**

- Solo + AI agents: **8–10 engineer-weeks**.
- 3-person team: **4–5 wall-clock weeks**.

**Risks**

- Image generation cost and latency at scale is the single biggest unknown-cost risk in the app; without caching and draft-tier generation working correctly from day one, this phase can become financially unsustainable before launch.
- Consent/legal exposure around personal photos is real (spec §29, §13 safety requirements) — the "require user ownership/permission" gate is a legal control, not a UX nicety, and needs to actually block generation, not just show a checkbox that isn't enforced server-side.
- Product URL extraction from arbitrary retailer pages is inherently fragile (page structure changes break parsers) and has terms-of-service risk if treated as unrestricted scraping — spec §17 explicitly says don't rely on scraping as the only source; the curated catalog path needs to be real, not a placeholder.
- Generated-image quality that doesn't match the described garments erodes trust fast; this needs human review against real garment photos before shipping, not just "the API returned an image."

---

## Phase 7 — Monetization and hardening

**Goal:** Make the app sellable, legally compliant, accessible, and provably meeting the Definition of Done in spec §30.

**Ordered workstreams**

1. StoreKit 2 purchase flow, server-side reconciliation (`POST /subscriptions/sync`, `POST /app-store/webhook`), entitlement logic, paywall, restore purchases.
2. `DELETE /account` cascading deletion (DB, storage, embeddings, memories, auth identity) and in-app deletion UI with visible job status.
3. Data export, opt-out of model training, ATT prompt (only if tracking is implemented), privacy policy/terms content.
4. Accessibility pass: Dynamic Type, VoiceOver, high-contrast, Reduce Motion, color-independent meaning.
5. Notifications, permission-timing audit, remaining secondary screens (Monthly review, Packing assistant, full Profile).
6. Rate limiting and privacy-safe logging on every Edge Function; performance pass against spec §20 targets.
7. Full test suite: unit, integration, UI, snapshot; final Definition-of-Done acceptance run; README and App Store submission assets.

**Hard dependencies**

- *Needs Phases 1–6 substantially complete:* entitlement gating touches every feature (closet cap, outfit limits, Kyra limits, Studio quota); account deletion must enumerate every table and bucket created in every prior phase; the DoD acceptance run exercises the entire app.
- *Unblocks:* App Store submission. Nothing downstream — this is the terminal phase.

**Exit criteria**

- [ ] A user can subscribe monthly or annually via StoreKit sandbox, and entitlements (unlimited closet, full Daily Brief, higher Studio quota) apply immediately without app restart.
- [ ] Restore purchases correctly re-entitles a user on a fresh install.
- [ ] Deleting an account removes the auth identity and, verified by direct database/storage inspection, leaves zero rows and zero objects for that `user_id` across every table and bucket in the schema.
- [ ] VoiceOver can complete the full flow in spec §30 items 1–14 without a mislabeled or unreachable control.
- [ ] The app is usable end-to-end at the largest Dynamic Type accessibility size without truncated or overlapping text on primary screens.
- [ ] Reduce Motion setting removes all matched-geometry and breathing-orb animation.
- [ ] All spec §22 unit, integration, UI, and snapshot test categories exist and pass in CI.
- [ ] Every spec §22 "acceptance quality bar" item is true: no lorem ipsum, no dead buttons, no hard-coded user name, no exposed secrets (grep the built binary for provider API key prefixes), no unhandled network failure, no permission requested before context.
- [ ] The full spec §30 Definition-of-Done sequence (items 1–14) completes successfully in one uninterrupted session, in both light and dark mode, under a throttled/degraded network profile.
- [ ] The project builds with zero warnings and a README exists covering setup, env vars, migrations, Edge Function deployment, StoreKit config, and test instructions (spec §31).

**Effort**

- Solo + AI agents: **10–13 engineer-weeks**.
- 3-person team: **5–7 wall-clock weeks**.

**Risks**

- App Store review risk is concentrated here: subscription UX, AI-generated imagery, and personal-photo handling are all policy-sensitive areas; a rejection late in this phase can cost 1–2 weeks per review cycle. Get a TestFlight build with paywall + Studio in front of reviewers' likely concerns early, not at the last minute.
- Account deletion completeness is easy to certify wrong — a new table added in a late Phase 6 fix and forgotten in the deletion job is a silent data-retention/legal bug that won't show up in normal testing. Maintain the deletion job as a checklist tied 1:1 to the schema, regenerated whenever a migration adds a user-owned table.
- Accessibility and snapshot testing scope creep: "full Dynamic Type support" and "major screens in light/dark" can expand to cover every screen and state combinatorially. Timebox and prioritize the screens on the DoD critical path first.
- Performance targets (spec §20) discovered to be missed this late are expensive to fix if the root cause is architectural (e.g., full-resolution images loaded in a grid from Phase 3) rather than a tuning problem — this is why performance should be spot-checked in each earlier phase, not solely audited here.

---

## Critical path

The longest unavoidable dependency chain from zero to the spec §30 Definition of Done:

```
Xcode project + Supabase schema/RLS (P1)
  → Sign in with Apple / session (P1)
  → Onboarding data capture: body/lifestyle/style profiles (P2)
  → closet_items schema + manual/scanned item creation (P3)
  → CompatibilityScorer + outfits/generate (P4)
  → daily-brief/generate consuming outfits (P4)
  → Kyra context packet + /kyra/respond wrapping outfits/generate via create_outfit tool (P5)
  → studio/generate consuming an outfit's item list (P6)
  → products/evaluate reusing the unlock-count algorithm (P6)
  → StoreKit entitlement gating closet/outfit/Kyra/Studio limits (P7)
  → DELETE /account enumerating every table created above (P7)
  → full Definition-of-Done acceptance run (P7)
```

This chain is essentially linear because the DoD (§30) requires every capability in sequence in one session. The single highest-leverage point to de-risk early is the **closet → outfit generation** link (P3→P4): everything downstream (Kyra, Studio, commerce, entitlements) depends on outfits existing and being trustworthy, but almost nothing upstream depends on them. This is also why the vertical slice below targets exactly that link.

---

## Parallelizable work

Given the feature-first module structure in spec §8, once Phase 1's repository protocols and `AppContainer` exist, work can fan out to independent developers/agents with low merge-conflict risk because each feature owns its own `Views/ViewModels/Components/Models/Services/Routing/Tests` subtree and talks to the rest of the app only through protocols in `Domain/Repositories`:

- **Design System (`Core/DesignSystem`)** can be built in parallel with Auth from day one of Phase 1 — it has no dependency on backend state.
- **Backend Edge Functions can be built ahead of or in parallel with the client feature that consumes them**, since the client is written against repository protocols with mock implementations first. A backend-focused agent can build `/outfits/generate` while an iOS-focused agent builds the Outfit builder UI against a mock `OutfitRepository`, and they integrate once both are ready.
- **Within Phase 3**, the camera/CV pipeline (`SCAN` area) and the closet CRUD/grid/filters (`CLOSET` area) touch almost disjoint files and can be split across two developers; they only converge at the scan-review-screen-writes-to-closet-repository boundary.
- **Within Phase 4**, the eight `CompatibilityScorer` sub-scorers are independent pure functions and can be split across multiple agents/developers simultaneously, converging only in the weighted-aggregate ticket.
- **Phase 5 (Kyra), Phase 6 (Studio), and Phase 6 (Shopping)** can be developed largely in parallel by three separate workstreams once Phase 4's outfit generation and Phase 3's closet repository exist, because Kyra tool-wiring, Studio's image pipeline, and product evaluation touch different files and different Edge Functions; they converge only in the small set of "wire tool X to real endpoint" tickets.
- **Testing and accessibility work should not be batched entirely into Phase 7.** Unit tests for each phase's core algorithms (compatibility scoring, cost-per-wear, entitlement logic) and VoiceOver labeling for each new screen are cheapest to write by the same agent immediately after building the feature, in parallel with the next phase's work, rather than retrofitted at the end.
- **What does not parallelize well:** the account-deletion job (P7) and the entitlement-gating pass (P7) are inherently integration work that must follow everything else, since they touch every table and every feature's premium/free boundary.

---

## Vertical slice first

**Recommendation: build a thin end-to-end slice — auth → add one garment → generate one outfit → mark it worn — before completing the rest of Phase 1's foundation work, and before starting Phase 2's onboarding.**

### Why before finishing Phase 1

Phase 1 as scoped includes a lot of infrastructure (full nav shell, full design system, guest mode, email OTP) that is necessary for the *finished* app but does not retire any architectural risk. The riskiest, least-proven assumptions in the whole spec are: (1) that Supabase Auth + RLS actually protects a real user's data end-to-end, not just in isolated policy tests; (2) that SwiftData-to-Supabase sync round-trips correctly for a real write; (3) that an Edge Function can be deployed, authenticated, and called from the client without a service-role key leaking; and (4) that the `closet_items` → `outfit_items` → `outfit_wears` data shape is actually workable once real code is written against it, not just as designed on paper. All four of these are proven or disproven by the vertical slice, and none of them are proven by, say, polishing the splash screen animation or building email OTP. Finding out the data model is wrong *after* building onboarding, the full design system, and guest mode is far more expensive than finding out before.

### Precisely what the slice includes

- One auth path only (Sign in with Apple; skip email OTP and guest mode for the slice).
- A bare-minimum `RootView` → single screen (no 5-tab IA, no marble splash, functional UI only).
- `closet_items` table (minimal columns: id, user_id, name, category, primary_color) with RLS, and a manual add-garment form — no camera, no segmentation, no Vision analysis.
- `outfits` / `outfit_items` / `outfit_wears` tables with RLS.
- A real `POST /outfits/generate` Edge Function, deployed and JWT-validated, using a deterministic/simplified scoring rule (even just "pick one top + one bottom + one pair of shoes if available") rather than the full weighted `CompatibilityScorer` — the point is proving the deployment and data-flow, not the recommendation quality.
- A single outfit display with a "Mark Worn" button that writes to `outfit_wears` and increments `wear_count`.

### Precisely what it excludes

- Style DNA / onboarding quiz / body-fit profile.
- Camera capture, segmentation, OCR, background removal.
- Kyra (any form).
- Style Studio image generation.
- Product evaluation / affiliate commerce.
- Notifications, StoreKit, subscription gating.
- Design system polish (marble, custom typography scale, motion tokens) — use system defaults.
- Guest mode, email OTP, account deletion.
- Any UI beyond the single screen needed to demonstrate the four steps.

Once this slice works against the real backend (not mocks) for a real Sign in with Apple user, the team can proceed confidently into the full breadth of Phase 1 foundation work and Phase 2 onboarding, because the architecture is now validated rather than assumed.

---

## Cut-line analysis (40% timeline compression)

Using the midpoint of the solo+AI effort estimates above (~55 engineer-weeks) as the baseline, a 40% compression targets ~33 engineer-weeks. Cuts below are ordered from "cut first" to "cut last," and are chosen to preserve the spec §30 Definition of Done for as long as possible, since that is the contractual definition of a shippable product.

**Cut first (highest priority to cut, lowest cost to product):**

1. **Style Studio image generation (Phase 6).** This is the single most expensive workstream (image generation cost controls, consent flows, provider integration, polling infra) relative to how many DoD items depend on it (only one: "generate a visual styling estimate"). Ship a stub/"coming soon" state and treat this as the first post-launch feature. This alone recovers ~6–8 weeks.
2. **Packing assistant, Monthly review, Discover section depth, batch closet scan.** Spec §23 explicitly labels these "can follow shortly after" — they were never MVP-required. Cut them entirely from the compressed timeline rather than half-building them.
3. **Calendar/EventKit integration.** Replace with manual occasion entry only; `get_schedule` Kyra tool returns manually-entered occasions. Recovers real complexity around permission flows and calendar-event mapping.
4. **Style preference paired-image quiz.** Reduce from 12–20 comparisons to the style-identity card selection alone (spec §6.5), dropping §6.9 entirely for the compressed build. This also removes a content-production dependency (curating paired imagery) that was a real risk in Phase 2.
5. **Curated product catalog / affiliate feed ingestion.** Ship user-pasted-link product evaluation only (spec §17 option 3); this satisfies the DoD's "paste a retailer link" requirement without building catalog admin tooling.
6. **Kyra tool surface.** Ship `search_closet`, `create_outfit`, `mark_item_worn` only. Drop `save_preference` automation (memories become explicit user settings instead of inferred), `generate_studio_preview` (Studio is cut anyway), and `create_packing_list` (packing is cut anyway).
7. **Snapshot and Dynamic Type test coverage.** Reduce to the DoD-critical-path screens only (Home, Closet, Outfit detail, Paywall, Kyra) instead of "major screens" broadly.

**Never cut, under any compression, because they are either spec §30 Definition-of-Done items, legal/App-Store-blocking requirements, or foundational security controls that are cheaper to build once than retrofit:**

- Sign in with Apple + in-app account deletion (DoD items 2, 14; also an App Store requirement for any app offering account creation).
- Row Level Security on every user-owned table (data breach risk; spec §15 is non-negotiable).
- Closet CRUD (manual entry at minimum) + outfit generation from owned items (DoD items 5–9; this is the core product).
- StoreKit subscription + restore purchases (DoD item 12; there is no revenue without it, and Apple requires restore to be present for approval).
- Product-link evaluation with a buy/skip verdict (DoD item 10).
- View/delete stored style memories + data export (DoD item 13; spec §29 legal requirement).
- Provider-neutral abstraction (`StylistReasoningProvider` etc. behind protocols) — cutting this to "just call OpenAI directly" looks like a shortcut but is not a scope cut, it's technical debt that makes swapping providers under cost pressure post-launch much harder; keep the protocol boundary even under time pressure, just ship one live adapter behind it.
- VoiceOver labels and 44pt tap targets at a baseline level (not full audit depth, but not zero) — required by spec §19 and a plausible App Store accessibility rejection risk.
- Account-deletion completeness (spec §15) — a partial deletion job is worse than a late one; do not ship a "delete" button that doesn't actually delete everything.

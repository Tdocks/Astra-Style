# CLAUDE_HANDOFF — where Astra Style is (2026-08-06)

**Read this first** if you are Claude Code (or any coding agent) picking up the
project after the Cursor cloud / Mac TestFlight push. It is the situational
brief: what shipped, what actually works on a phone, what is still stub, and
what you should do next.

| Do not open first | Why |
|---|---|
| `HANDOFF.md` | Large, older cold-start dump (written around PR #12). Useful archaeology, easy to get lost in. |
| Random Phase 4 tickets | Out of scope until smoke is reported. |

| Open next, by job | Path |
|---|---|
| Ticket truth (Done / Partial / Not started) | [`docs/03-progress.md`](docs/03-progress.md) |
| Binding conventions | [`CLAUDE.md`](CLAUDE.md) |
| Agent router | [`AGENTS.md`](AGENTS.md) |
| Phone smoke checklist | [`START_HERE.md`](START_HERE.md) §6 |
| CLI archive / ASC upload | [`ios/CLI_BUILD_AND_TESTFLIGHT.md`](ios/CLI_BUILD_AND_TESTFLIGHT.md) |
| Marketing site | [`web/CLAUDE.md`](web/CLAUDE.md) |
| Spec | [`docs/00-master-spec.md`](docs/00-master-spec.md) |

---

## 1. One-paragraph status

Astra Style is a native iOS 18+ SwiftUI app (Swift 6) with a Supabase backend.
**Phases 1–2 (foundation + onboarding) and the Phase 3 closet + single-item
scanner loop are real and shipped on `main`.** Build **1.0.0 (1)** was archived
on the owner's Mac, uploaded to App Store Connect, attached to an Internal
TestFlight group, and **installed on Tyler Dockswell's iPhone** (confirmed
2026-08-02; still the tip of the TestFlight story as of this doc). Vision
analysis defaults to **mock**. Kyra, Style Studio, real outfit compatibility,
and StoreKit are **not** built. Legal docs exist as drafts on
https://astra-style.com but are **not** published in-app. Machine-checked
progress: **45 Done / 52 Partial / 81 Not started** of 178 tickets
(`scripts/check_progress.py`).

**Immediate next human/agent job:** run the five-item smoke checklist in
`START_HERE.md` §6 on the phone and report pass/fail. Do not cut another build
or start Phase 4 unless smoke fails hard or the owner asks.

---

## 2. Who built what (recent timeline)

Work landed mainly via Cursor cloud agents (Linux — cannot codesign) plus Claude
Code on the owner's Mac (Xcode 26.6 — can Archive / upload).

| When | What | Where |
|---|---|---|
| Through ~2026-07-31 | Phase 1 foundation, Phase 2 onboarding + Style DNA, quiz imagery | `main` (PRs #1–#4) |
| 2026-08-01 | Closet Edge Function (mock vision, idempotency, batch job+poll) | PRs #6–#7 |
| 2026-08-01 | Closet UI depth: free-tier 30-cap, offline read cache, add-garment UI test | PR #9 |
| 2026-08-01 | Scanner capture (camera + Photos import) | PR #8 |
| 2026-08-01 | Scanner upload → analyze → review → save | PR #10 |
| 2026-08-01 | Vision garment-region + OCR seams; OpenAI pilot docs (not enabled by default) | PR #11 |
| 2026-08-01 | Phase 3 exit: offline LWW conflict, pending-scan queue, unlock report, App Icon, TestFlight runbook | PR #12 → `86edb74` |
| 2026-08-01–02 | `START_HERE.md`, `HANDOFF` TestFlight section, marketing site + Cloudflare Worker, domain `astra-style.com` | PRs #13–#20 |
| 2026-08-02 | Mac Claude: pin `DEVELOPMENT_TEAM`, fix orientations in real `Info.plist` (ASC error 90474), CLI playbook | `e029568`, `913e43a`, `03737cc` on `main` |
| 2026-08-02 | Mac Claude: Archive → exportArchive upload of **1.0.0 (1)**; Internal TF group; owner invited; later **installed on phone** | ASC app `6797115649` — not a code commit |

Open draft PRs that may still exist when you pull (safe to ignore or merge as
docs/cleanup only): #21 (legal decisions), #22 (dead `INFOPLIST_KEY_*` removal +
status sync). Prefer this file + `docs/03-progress.md` over stale PR descriptions.

---

## 3. Progress snapshot (do not invent Done)

Verified by `python3 scripts/check_progress.py`:

| Phase | Tickets | Done | Partial | Not started |
|---|---|---|---|---|
| 1 — Foundation | 25 | 13 | 12 | 0 |
| 2 — Identity | 17 | 12 | 5 | 0 |
| 3 — Closet | 27 | 15 | 9 | 3 |
| 4 — Outfit intelligence | 26 | 2 | 11 | 13 |
| 5 — Kyra | 22 | 1 | 3 | 18 |
| 6 — Studio and commerce | 25 | 2 | 4 | 19 |
| 7 — Monetization and hardening | 36 | 0 | 8 | 28 |
| **Total** | **178** | **45** | **52** | **81** |

Phase 3 Done tickets (the product loop you can demo):  
`P3-SCAN-05`, `06`, `09`, `11`, `P3-CLOSET-01`–`03`, `05`, `08`–`11`,
`P3-INFRA-01`, `02`, `P3-TEST-02`.

Phase 3 Not started: `P3-SCAN-10` (server cutout), `P3-SCAN-12` (receipt/mirror),
`P3-CLOSET-07` (insights).

When you finish a ticket, update its row in `docs/03-progress.md` **in the same
commit**. The checker fails CI if the doc lies.

---

## 4. What works end-to-end (honest)

### 4.1 Auth, guest, onboarding — real

- Sign in with Apple, email OTP, session restore / refresh.
- Guest mode: local closet, **10-item cap**, no network (ADR 0011).
- Guest → account migration path exists.
- Onboarding §6.3–§6.10: goals, identities, measurements, appearance, lifestyle,
  style quiz, Style DNA result (via deployed `profile` + `style-dna` Edge
  Functions).
- Optional reference photo (consent before picker; upload on submit for signed-in
  users) and skippable first closet items.
- Welcome screen: legal links are **nil** while unpublished — shows an honest
  notice, not a Safari DNS error (`AstraLegal.isPublished = false`).

Gaps: quiz `silhouette` has only one pair → permanently low confidence; some
live Apple→Supabase round-trips still treated as §22 placeholders in docs;
authenticated Profile tab is still thin vs guest profile.

### 4.2 Closet — real and the strongest surface

On device (including TestFlight):

- Category tiles + grids, search, **eight-facet filters**, metrics row (5 of 6 —
  no versatility), grid / compact / colour-spectrum view modes.
- Manual add / edit form (no camera required).
- Item detail, mark worn, archive.
- Offline **read cache** for authenticated closet; mutations queue and drain
  (closet-owned paths).
- Last-write-wins conflict recording on drain (`P3-INFRA-01`).
- Free-tier **30-item** cap + guest **10-item** cap enforced.
- UI test `testAddGarment` covers the manual-add path.

Not real yet: versatility metric, care instructions, outfit count, insights /
redundancy (`P3-CLOSET-04` Partial, `06` Partial, `07` Not started).

### 4.3 Scanner — single-item loop real; vision is mock by default

Happy path:

1. Scanner modal → camera capture **or** Photos import.
2. Quality check + JPEG prepare (1024px / q0.72, metadata stripped).
3. Device hints before review: garment region, OCR lines, dominant colour
   (`P3-SCAN-06` Done — device Vision QA for blur/OCR quality still Partial).
4. Upload to private `user-content` → `POST /closet/analyze-item` (idempotent).
5. Editable review (low-confidence fields footnoted) → Save → unlock-count
   report → Done.

Offline: pending-scan queue analyzes on reconnect without re-capture
(`P3-INFRA-02`).

**Critical honesty:** `VISION_ANALYSIS_PROVIDER` defaults to **`mock`**. Fields
look plausible but are not live model vision until someone sets
`VISION_ANALYSIS_PROVIDER=openai` + `OPENAI_API_KEY` on the Supabase project and
redeploys `closet` (see `supabase/functions/closet/README.md` and
`docs/08-provider-abstraction.md` §2.5). The OpenAI pilot gate has **not** been
run.

Not built: server background removal (`P3-SCAN-10`), receipt/mirror modes
(`P3-SCAN-12`). Batch analyze API exists server-side but has no proven live
5-upload E2E (`P3-SCAN-08` Partial).

### 4.4 Home — shell only

- Real tab shell: brief header, hero card, module layout.
- Guest brief is local-only.
- Outfit confidence currently from a **placeholder** least-recently-worn style
  scorer — **not** real Wardrobe Graph compatibility.
- Edit / Visualize and several modules still hit `FeaturePlaceholderView`.
- Weather / calendar permissions are not forced at launch (correct per §7);
  weather is not wired as a live home dependency yet.
- No `daily-brief` Edge Function.

### 4.5 Outfits / Kyra / Studio / Discover / Subscription — not product yet

| Tab / area | Reality |
|---|---|
| Outfits | DB + `outfits` generate endpoint with placeholder scorer; `Features/Outfits/` is essentially a README; detail UI placeholder |
| Kyra | Tables exist; **no** `kyra` Edge Function; tab is placeholder |
| Studio | Migrations exist; no generation UI; estimate-badge rule still applies whenever that ships |
| Discover / Shopping / Subscription | Placeholder / README |
| Profile (signed-in) | Stubbier than guest profile |

Do not tell the owner these "almost work." They do not.

### 4.6 Marketing site — live

- **https://astra-style.com** (and www) → Cloudflare Worker `astra-style`, HTTP 200.
- Also: `https://astra-style.7rff2b9rjf.workers.dev`
- Sources: `web/site/` + `legal/*.html` → build into `web/dist/` →
  `npx wrangler deploy` from **repo root** (`wrangler.toml`).
- `/privacy` (and siblings) carry a **“Draft — not yet in force”** banner and
  `[[NEEDS INPUT]]` placeholders — intentional.

### 4.7 TestFlight — installed; smoke not formally reported

| Fact | Value |
|---|---|
| Bundle ID | `com.astrastyle.app` |
| Team ID | `Q9ZH8AA9NY` |
| ASC App ID | `6797115649` |
| Owner ASC login | `tdoxwell@icloud.com` |
| Version | `1.0.0` |
| Build | `1` (`CURRENT_PROJECT_VERSION` in `ios/project.yml`) |
| Xcode | **26.6** exactly |
| Group | Internal, automatic distribution enabled |
| Device | Owner confirmed install on iPhone |

`START_HERE.md` §7 smoke checkbox may still be open in git until someone
records results. **Do not invent pass/fail.** Ask the owner or run the checklist.

---

## 5. Backend (Supabase)

Project ref (docs / xcconfig): **`anutsdzbxycaavmmkewo`**.

### Edge Functions present

| Slug | Role |
|---|---|
| `closet` | `analyze-item`, batch-analyze + status; vision provider switch |
| `profile` | onboarding completion paths |
| `style-dna` | generate Style DNA (deterministic stylist path + protocol) |
| `outfits` | generate (placeholder scorer); rank not built |

**Not present:** `kyra`, `studio`, `products`, `daily-brief`, App Store webhook /
subscriptions function, account-deletion Edge Function.

### Migrations

~22 SQL files under `supabase/migrations/` (append-only). Themes: profiles /
identity, closet + embeddings, outfits, feedback/memory, commerce/studio/
subscriptions tables, RLS, storage, search, account deletion scaffolding, legal
bucket, closet analysis jobs / idempotency.

RLS is required on user-owned tables. Service-role and provider keys live **only**
in Edge Functions — never in the iOS bundle.

### iOS → backend rule

Views → `@Observable` view models → repository protocols →
`AstraAPIClient` / Supabase. No `URLSession` or Edge Function calls inside
`View` bodies.

---

## 6. Legal / privacy — decided, deferred

**Owner / Cursor decision (2026-08-02), still in force:**

1. Keep the live Draft banner on https://astra-style.com/privacy/.
2. Do **not** flip `AstraLegal.isPublished` in
   `ios/AstraStyle/Core/Utilities/AstraLegal.swift`.
3. Do **not** fill `[[NEEDS INPUT]]` or chase counsel for the TestFlight cut.
4. ASC may use `https://astra-style.com/privacy/` as the app-record Privacy
   Policy URL — that is **not** in-app publication.

Ticket: `P7-PRIVACY-05`. Record: `legal/README.md`. Publishing unreviewed
policies is worse than none.

---

## 7. What Cursor (cloud) built that you will touch

Concrete artifacts, not vibes:

- **Closet + scanner product loop** under `ios/AstraStyle/Features/{Closet,Scanner}/`
  with unit/UI tests under `ios/AstraStyle/Tests/`.
- **Offline:** closet LWW conflict + pending scan queue
  (`P3-INFRA-01` / `02`).
- **Unlock report** after save (`ScanOutfitUnlockEstimator`).
- **App Icon** in `ios/AstraStyle/Resources/Assets.xcassets`.
- **`closet` Edge Function** with mock vision + OpenAI adapter behind env flags.
- **Marketing site** Worker + static dist; Cloudflare skills under `.agents/skills/`.
- **Docs:** `START_HERE.md`, `docs/12-testflight-cut.md`,
  `ios/CLI_BUILD_AND_TESTFLIGHT.md`, `web/GATE.md`, `web/CLAUDE.md`, this file.

Cloud agents **cannot** Archive or talk to App Store Connect. You (Mac) already
did that for build 1.

---

## 8. Footguns (will waste your session if ignored)

1. **`xcodegen generate` wipes GUI signing.** `CODE_SIGN_STYLE` +
   `DEVELOPMENT_TEAM: Q9ZH8AA9NY` must stay in `ios/project.yml`.
2. **`GENERATE_INFOPLIST_FILE: NO`.** Edit
   `ios/AstraStyle/Resources/Info.plist` for orientations, usage strings, URL
   schemes. `INFOPLIST_KEY_*` in `project.yml` are **dead** (caused ASC error
   **90474** until orientations were added to the real plist).
3. **xcconfig URL escaping:** `https:/$()/anutsdzbxycaavmmkewo.supabase.co` in
   `Secrets.xcconfig` — see comments in `ios/Config/Base.xcconfig`.
4. **Never commit** `Config/Secrets.xcconfig`, `.p12`, or provisioning profiles.
5. **Bump `CURRENT_PROJECT_VERSION`** before any re-upload — ASC rejects
   duplicate build numbers. Build **1** is already used.
6. **Do not re-open legal publish** while cutting builds or smoking the phone.
7. Standing account rule: do not call Higgsfield tools/MCP from this repo.

Full CLI error table: `ios/CLI_BUILD_AND_TESTFLIGHT.md` §6.

---

## 9. What you should do next

### A. If the owner has not finished smoke (default)

1. Pull `main`.
2. Open TestFlight build **1.0.0 (1)** on the phone.
3. Run `START_HERE.md` §6 verbatim; report pass/fail per line.
4. Paste any crash / Organizer / ASC compliance prompt **verbatim**.

### B. If smoke fails

- Fix the smallest bug that explains the failure.
- Bump build number, archive via GUI or
  `ios/CLI_BUILD_AND_TESTFLIGHT.md`, upload, re-smoke.
- Do not “while I’m here” into Kyra or Studio.

### C. If smoke passes and the owner asks “what’s next?”

Suggested order (still owner-gated):

1. Optional: enable live vision (`VISION_ANALYSIS_PROVIDER=openai`) and run the
   §2.5 pilot checklist — only with a real key the owner provides.
2. Device Vision QA for Partial `P3-SCAN-01`–`04` criteria.
3. Then Phase 4 per `docs/01-build-roadmap.md` / open tickets in
   `docs/03-progress.md` — real compatibility, daily brief, outfit UI.
4. Legal publish (`P7-PRIVACY-05`) stays end-of-project unless the owner
   explicitly changes that decision.

---

## 10. Architecture cheat sheet

```
iOS (Swift 6, SwiftUI, @Observable VMs)
  └─ AppContainer (protocol DI — ADR 0007)
       └─ Repositories → AstraAPIClient / Supabase client
            └─ Edge Functions only (no direct AI provider keys on device)

Supabase
  ├─ Postgres + RLS + pgvector
  ├─ Storage: user-content (private), legal (public, empty)
  └─ Functions: closet, profile, style-dna, outfits

Web
  └─ Cloudflare Worker `astra-style` serving web/dist
```

Design system: **never** hardcode colours/spacing/radii — `Astra*` tokens only
(`docs/07-design-system.md`, `Core/DesignSystem/`).

Kyra (when built): structured JSON cards only; guardrails server-side
(`docs/06-kyra-orchestration.md`, ADR 0004).

---

## 11. Doc map (keep this short list in your head)

| Question | Answer lives in |
|---|---|
| What should the product do? | `docs/00-master-spec.md` |
| Is ticket X done? | `docs/03-progress.md` |
| How do we build / phase? | `docs/01-build-roadmap.md`, `docs/02-task-breakdown.md` |
| Schema detail | `docs/04-data-model.md` |
| Compatibility / wardrobe score | `docs/05-wardrobe-graph.md` |
| Why Supabase / Observation / DI / testing? | `docs/adr/*.md` |
| Risks | `docs/11-risk-register.md` |
| This session’s situation | **this file** |

---

## 12. Definition of “TestFlight cut complete”

- [x] Phase 3 exit code on `main` (PR #12+)
- [x] ASC app + signing + orientations fixed
- [x] Build 1.0.0 (1) uploaded
- [x] Internal group + owner invited
- [x] Installed on owner's iPhone
- [ ] Smoke §6 reported pass/fail
- [ ] Owner accepts mock vision for now **or** asks to enable OpenAI pilot

Until the smoke checkbox is filled with real results, treat the cut as
**install-complete, verification-open**.

---

*Written by the Cursor cloud agent for Claude Code / the owner, 2026-08-06.
Update this file when smoke results land or when Phase 4 actually starts — not
for every typo fix.*

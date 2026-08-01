# 03 — BUILD PROGRESS

**Last audited:** 2026-08-01 (Phase 3 closet: `P3-CLOSET-03`, `-04`, `-05`, verified against a full
build and test run); 2026-07-31 (Phase 2 onboarding capture steps, and the §6.9 quiz imagery);
everything else 2026-07-30, at commit `45b4b90c`.

This file answers one question: *which of the 178 tickets in `docs/02-task-breakdown.md` are
actually done?* Nothing else in the repo answers it. Before this file existed, the only way to find
out was to read the git log, count files, run the tests, and probe the live backend — about an hour
of archaeology at the start of every session, repeated because the result was never written down.

## How this file is kept honest

A hand-maintained status file is accurate the day it is written and quietly wrong a week later,
which is worse than having none because people trust it. So this one is checked:
`scripts/check_progress.py` runs in CI and fails when this document disagrees with the parts of
reality a script can see — every ticket in `02-task-breakdown.md` appears here exactly once, no
invented ticket ids, the summary counts match the rows beneath them, cited files and tests exist,
and the deployed Edge Function slugs match what the tickets claim.

The checker cannot judge whether something was built *well*. That part is on the reader, and it is
why every row carries evidence rather than just a status.

**When you finish a ticket, update its row in the same commit.** A status change with no
corresponding code change is a lie in the making.

## Status vocabulary

| Status | Means |
|---|---|
| **Done** | Every acceptance criterion in the ticket is met, with evidence. |
| **Partial** | Some criteria met, others provably not. The row says which are missing. |
| **Not started** | No implementing code exists anywhere in the repo. |
| **Unverifiable** | The criterion is real but cannot be settled by reading code — needs a device, a sandbox purchase, App Store review, or a judgement about subjective quality. Used honestly; it is not a synonym for Done. |

"Partial" is the most common status and that is expected, not a failure. A repo built spec-first
lands data layers, protocols, and models long before the screens that use them.

## Summary

| Phase | Tickets | Done | Partial | Not started |
|---|---|---|---|---|
| 1 — Foundation | 25 | 13 | 12 | 0 |
| 2 — Identity | 17 | 12 | 5 | 0 |
| 3 — Closet | 27 | 5 | 7 | 15 |
| 4 — Outfit intelligence | 26 | 2 | 11 | 13 |
| 5 — Kyra | 22 | 1 | 3 | 18 |
| 6 — Studio and commerce | 25 | 2 | 4 | 19 |
| 7 — Monetization and hardening | 36 | 0 | 8 | 28 |
| **Total** | **178** | **35** | **50** | **93** |

Read that table carefully before drawing a conclusion from it. 32 of 178 "Done" understates where
the project is: Phase 1's foundation is genuinely finished in substance, most Phase 1 "Partial"
rows are missing one narrow criterion rather than the bulk of the work, and a large amount of
Phase 3–7 data-layer work is already applied to production. It also *overstates* readiness in one
specific way — see **Blockers** below.

---

## What is actually blocking, right now

Ranked by what stops the next user-visible thing from working.

1. **iOS CI has still never run on a pull request** — but it is no longer red. SwiftLint
   `--strict` reported 122 violations across 19 rules (not the 4 rules first estimated); all 122
   are now resolved, 121 in the source and one by a documented `nesting` threshold change in
   `.swiftlint.yml`. With lint passing, the zero-compiler-warnings gate ran for the first time:
   reproduced locally with the same scoped build-log grep `.github/workflows/ios.yml` uses, and
   first-party code is clean (0 warnings under `ios/AstraStyle/`). What remains open is the part
   no local run can settle — every commit has gone straight to `main`, so no criterion in
   `P1-INFRA-03` has ever been validated *on a PR*.
2. **The quiz covers all eight dimensions now; two of them are one pair short.** The §6.9
   imagery was regenerated from scratch on 2026-07-31 against a single canonical reference
   figure, and the shipped catalog holds **14 pairs** — inside §6.9's 12–20, with every one of
   the eight preference dimensions returning a value rather than *absent*. What remains is
   narrower, and it is not a code problem: `silhouette` and `logo_tolerance` ship with one pair
   each, which is `.low` confidence permanently, so Kyra may not state either back to the user.
   The two pairs that would fix that were generated and rejected — one returned a real trademark,
   the other varied sleeve length alongside volume — and their corrected prompts are committed in
   `scripts/generate_quiz_imagery.py`; regeneration is blocked on an OpenAI billing hard limit,
   not on an open question. `POST /style-dna/generate` handles a sparse vector correctly either
   way: an unasked axis contributes nothing and is named in the result's `open_questions`, and an
   axis asked-and-declined is not asked again.
3. **Terms and Privacy are drafted, and publishing them is deliberately deferred to the end of
   the project.** This is a plan decision, not a slip. The four documents exist and are committed
   under `legal/`, the public `legal` storage bucket exists and is empty, and
   `AstraLegal.isPublished` is `false`, so every legal URL in the app is `nil` and call sites must
   handle it — `LegalDocumentAvailabilityTests` pins that invariant and the welcome screen shows
   an honest one-line notice instead of opening Safari on a DNS error. **Nothing further happens
   until the end of the build:** no publishing, no domain registration (`astrastyle.app` is still
   NXDOMAIN, re-verified 2026-07-30), no filling of the `[[NEEDS INPUT]]` placeholders, no legal
   review. Those placeholders still stand and are still enumerated in `legal/README.md`; they are
   simply not being chased now. It remains an App Store review blocker whenever submission comes,
   and it is a one-flag change once the documents are live. Ticket `P7-PRIVACY-05`.

## Acceptance criteria that are wrong, rather than unmet

**Amended 2026-07-30.** These six could never pass as written, because the shipped behaviour was
deliberate and better than the criterion demanded. A criterion that can never pass quietly trains
its reader to stop trusting criteria at all, so each has been corrected at its source rather than
left open. This section stays as the record of *why*.

- **P1-CORE-04** required "exactly one retry" on 5xx. `AstraRetryPolicy.default` ships
  `maxAttempts: 3` with backoff, the better policy for a mobile client on unreliable networks.
  Amended in `docs/02-task-breakdown.md`. What the wrong criterion was masking is real and stays
  open: no test asserts retry count or backoff, so the ticket stays `Partial`.
- **P1-CORE-03** required `MockCalendarService` to return zero events by default. It returns two
  fixtures, which makes previews and early tests more useful without extra setup. Amended in
  `docs/02-task-breakdown.md`; the ticket is now `Done`.
- **P1-DS-01** required Asset Catalog colour sets matching spec §3's hex values. Three values were
  deliberately revised for WCAG contrast (`textMuted` in both schemes, light-mode
  `accentChampagne`), already documented in `docs/07-design-system.md`. Spec §3 was the wrong
  document, so it was corrected — `docs/00-master-spec.md` §3 now carries the shipped hex values,
  cross-referenced to `docs/07`'s contrast analysis, so nobody "restores" the failing values later.
  Separately, and genuinely unmet: no Asset Catalog exists in the repo at all (no `.xcassets`, and
  therefore no app icon) — the ticket stays `Partial` on that basis.
- **P2-ONBOARD-06** required a climate/location permission prompt in §6.8. It was consciously moved
  to first use of §6.11, with the reasoning in `OnboardingLifestyleView`'s header comment — a sound
  call, but no ticket owned the prompt at its new home. The criterion is dropped from
  `P2-ONBOARD-06` (now `Done`) and added to `P4-HOME-05`, which owns §6.11's first-use path.
- **P7-DS-03** specified an accessible champagne behind a "High Contrast" toggle.
  `accentChampagneAccessible` ships as the *default* instead, which is strictly better and made the
  toggle criterion unreachable. Amended in `docs/02-task-breakdown.md`; the ticket stays `Partial`
  — the verdict/laundry-state half of its color-independent-meaning audit has no UI yet to audit.
- **Phase 1's section in `docs/01-build-roadmap.md`** carried 8 exit-criteria checkboxes, but its
  `Ordered workstreams` list only named 7 items and never mentioned Storage buckets, CI, or secrets
  hygiene at all, despite 3 of the 8 checkboxes testing exactly those. Reconciled by expanding the
  workstream list to name all 8 — every one of the 8 criteria is real and independently tracked
  (`P1-INFRA-02`, `P1-INFRA-03`, `P1-INFRA-06` among others), so the fix adds coverage rather than
  cutting a criterion.

---

# PHASE 1 — FOUNDATION

**13 Done · 12 Partial · 0 Not started.** Substantively complete. Every Partial below is a narrow
missing criterion, not missing work — but three of them (CI on PRs, SwiftData schema versioning,
the dead offline queue) will cost real money later if they stay open.

| Ticket | Status | Evidence |
|---|---|---|
| P1-INFRA-01 | Partial | `ios/project.yml` (XcodeGen, Swift 6, iOS 18); all 11 spec §8 features exist under `Features/`. No per-feature `Tests/` subfolder — tests are centralised in `Tests/{UnitTests,UITests}`. Extra `Features/Slice` is outside spec §8. |
| P1-INFRA-02 | Partial | `ios/Config/{Base,Debug,Release}.xcconfig` + gitignored `Secrets.xcconfig`; no key material found by grep. **No `Staging.xcconfig`** — ticket requires Debug/Staging/Release. |
| P1-INFRA-03 | Partial | 4 workflows exist. SwiftLint `--strict` now **passes** (swiftlint 0.65.0, 122 violations found and fixed; see `.swiftlint.yml`'s header for what the original hand-estimated thresholds got wrong), so the build step is reachable and the "Fail on warnings in our own code" grep was exercised for the first time — 0 warnings under `ios/AstraStyle/`. Still Partial: **zero PRs have ever existed**, so "a PR with a warning/violation fails CI" and "CI run time is visible on the PR" remain unvalidated by construction. |
| P1-INFRA-04 | Done | 19 migration files; `rls-tests.yml` applies all of them to a fresh `pgvector/pgvector:pg16` on every push and passes. |
| P1-INFRA-05 | Done | `20260728100200_profiles_and_identity.sql` + `20260728100900_rls_policies.sql`; `supabase/tests/20_rls_isolation_tests.sql` runs all six isolation checks on all four tables. |
| P1-INFRA-06 | Done | `20260728101000_storage_buckets.sql`; live bucket `user-content`, `public=false`, 25 MiB cap, four path-scoped policies. Caveat: storage policies are not covered by the RLS CI suite (CI Postgres has no `storage` schema). |
| P1-CORE-01 | Done | `App/AppContainer.swift` — flat `@Observable` protocol bag, `live()` + `preview()` factories, injected via `.environment`. |
| P1-CORE-02 | Done | 10 protocols in `Domain/Repositories/`, each with a mock. `grep "import Supabase" Domain/` returns nothing — no vendor type leaks into a signature. |
| P1-CORE-03 | Done | `MockWeatherService` is deterministic. `MockCalendarService` returns a deterministic 2-event fixture by default and accepts a configurable set (`Core/Mocks/MockCalendarService.swift:14-37`). Criterion amended 2026-07-30 to match — see "Acceptance criteria that are wrong, rather than unmet." |
| P1-CORE-04 | Partial | Auth precondition and `URLSession` containment both hold. `AstraRetryPolicy.default` retries a 5xx up to `maxAttempts: 3` with backoff (`Core/Networking/AstraAPIClient.swift:220-236`) — criterion amended 2026-07-30 to match this as the better policy. **No test asserts retry count or backoff** — that gap is real and stays open. |
| P1-CORE-05 | Partial | `Core/Persistence/AstraModelContainer.swift` builds a 4-entity on-disk store. **No `VersionedSchema`/`SchemaMigrationPlan` anywhere**, no pre-migration fixture test — the versioning criterion is entirely unmet. |
| P1-CORE-06 | Partial | Now wired, not dead code. `LiveClosetRepository.drainPendingMutations()` replays the backlog through a `ClosetWriting` seam and is called after every successful `fetchItems`/`createItem`/`updateItem`/`archiveItem`; `attemptCount` is incremented by both queue conformances on a failed replay; `OfflineMutationNotHandled` lets a shared queue be drained by one owner without discarding or wedging on another's mutations. 6 new tests in `Tests/UnitTests/OfflineDrainWiringTests.swift` drive the wiring itself (queue on failure, flush on the next success, attempt counting, skip-not-drop, no double-apply under concurrency) on top of the 5 that already covered the queue. Still Partial for two reasons: replay is triggered by the next successful call, not by a reachability event, so "reconnecting triggers replay" is met only in effect; and **`LiveOutfitRepository`'s `.outfit`/`.outfitWear` mutations are still never replayed by anything** — they are now safely skipped rather than silently dropped, but they still accumulate. |
| P1-CORE-07 | Done | `App/AppRouter.swift` — 4-case route state, 5 independent path arrays, 7 modal routes; `TabNavigationStateTests` (7 tests) assert cross-tab independence and modal isolation. |
| P1-DS-01 | Partial | `Tokens/AstraColor.swift` covers every §3 token in both schemes via a `UIColor` trait provider, and now matches spec §3 exactly — the three deliberately-revised hex values (`textMuted` both schemes, light `accentChampagne`) were ported into spec §3 itself 2026-07-30, cross-referenced to `docs/07-design-system.md`'s contrast analysis. **No Asset Catalog exists in the repo at all** (no `.xcassets`, and therefore no app icon) — that part is genuinely unmet. `surfaceMarble` returns `backgroundPrimary`. |
| P1-DS-02 | Done | `Tokens/AstraTypography.swift` — all 9 styles at exact §3 sizes, correct serif/sans split, `micro` uppercase + 1.5 tracking, `@ScaledMetric(relativeTo:)` throughout. |
| P1-DS-03 | Partial | `AstraSpacing`/`AstraRadius`/`AstraSize` all correct and referenced by name. **No lint rule flags raw point values** — `.swiftlint.yml` has only the sparkle and ticket-id custom rules. |
| P1-DS-04 | Partial | `AstraButton`/`AstraCard`/`AstraChip` on tokens with 44pt minimum targets. **`AstraTextField` does not exist** (8 raw `TextField` call sites). **No destructive button variant.** No per-component previews — only 4 whole-page gallery previews. |
| P1-DS-05 | Partial | `AstraMarble` (procedural, not an asset) + `LaunchingView`; session restore bounded by `withDeadline(.milliseconds(1400))`. Marble used at exactly 3 sites, none behind dense text. The "measured, not estimated" 1.4 s criterion has no measurement artifact. |
| P1-DS-06 | Partial | `AstraMotion` — 220 ms standard, springs, Reduce-Motion-aware `.astraAnimation`, haptics mapped per §3 and used at 12 onboarding sites. **No matched-geometry hero helper exists**, and **`AstraMotion.breathing` has zero call sites**, so the Reduce-Motion criterion has nothing to assert against. |
| P1-AUTH-01 | Done | `AppleSignInCoordinator` + SHA-256 nonce; `handle_new_user()` trigger deployed; cancellation maps to `AstraError.cancelled`. Live round-trip is a deliberate §22 placeholder. |
| P1-AUTH-02 | Done | `LiveAuthRepository.requestEmailOTP`/`verifyEmailOTP`; `EmailAuthSheet` is the entry UI; distinct errors for wrong code vs unconfirmed email; `astrastyle` URL scheme registered. |
| P1-AUTH-03 | Done | `SessionStore.restoreSession()` + `SessionRefreshing`; `SessionRestoreTests` — 6 tests including transparent refresh, refresh rejection, corrupt Keychain item, and guest session surviving relaunch. |
| P1-AUTH-04 | Done | `GuestClosetRepository` rejects the 11th item; `GuestClosetRepositoryTests` (7 tests) plus `GuestModeNetworkTests` proving 0 intercepted requests via a `URLProtocol` trap. |
| P1-AUTH-05 | Done | `LiveGuestMigrationService`; `GuestMigrationServiceTests` (4 tests) including partial-failure retention and ownership re-pointing. |
| P1-AUTH-06 | Partial | `SignedOutGateView` wires all four actions. The criterion "Terms/Privacy open real documents, not a 404" is **still unmet — no policy text exists** and `astrastyle.app` is still NXDOMAIN (re-verified 2026-07-30 with `nslookup` and `curl`). What changed is the failure mode: `AstraLegal` now gates every URL behind `isPublished` (false) and vends `URL?`, so the dead link is a compile-time obligation rather than a runtime 404, and the welcome screen renders an honest "will be published before release" notice instead of opening Safari on a DNS error — the control still does something, so §22's "no dead buttons" holds. **Writing the documents and registering the domain are product/legal decisions, not code.** Flip `AstraLegal.isPublished` and update `Tests/UnitTests/LegalDocumentAvailabilityTests.swift` in the same change. |

---

# PHASE 2 — IDENTITY

**12 Done · 5 Partial · 0 Not started.** The onboarding flow is complete end to end. §6.3–§6.10 is
built and hardened at AX5, `profile` and `style-dna` are deployed and were exercised against
production with a real JWT, the §6.10 result screen renders what they return, and as of 2026-07-31
the two §5.1-only steps between the quiz and the result exist as well: `P2-ONBOARD-08` (the
optional reference photo, behind an on-screen §29 consent gate) and `P2-ONBOARD-09` (first closet
items, skippable). `OnboardingStep` now has ten cases and the progress indicator reads out of eight
answerable steps rather than six — the count is derived from `allCases`, so nothing had to be
edited to follow it.

The five remaining Partial rows are all about depth rather than reach: a missing minimum-selection
rule, two quiz axes stuck at one pair, no SwiftData profile cache, no live stylist adapter, and no
pgvector ordering test.

| Ticket | Status | Evidence |
|---|---|---|
| P2-ONBOARD-01 | Done | `OnboardingIntroView.swift:36-43` renders §6.3 copy; the avatar is `AstraMonogram`, an abstract mark — the header explicitly rules out a face. |
| P2-ONBOARD-02 | Partial | All 8 goals in `StyleGoal`; persistence across back verified by `OnboardingFlowUITests.testBackPreservesAnswers`. **"At least one selection required" is not enforced** — `canAdvance` gates only `.identity`. |
| P2-ONBOARD-03 | Done | 10 identities; exactly-3 enforced (a 4th tap is refused, not absorbed) plus a primary; `OnboardingDraftTests` covers the complete/incomplete states. |
| P2-ONBOARD-04 | Done | `OnboardingMeasurementsView` (610 lines) covers all §6.6 fields; `MeasurementEntry.State` distinguishes `.declined` from `.unanswered`; unit conversion proven by tests plus `check_column_drift.py`. |
| P2-ONBOARD-05 | Done | All 6 appearance fields carry a `reason:` string; each individually skippable; `OnboardingDraftTests` — "A skipped appearance step is empty rather than a blob of nulls". |
| P2-ONBOARD-06 | Done | All 10 in-scope §6.8 fields present and mapped (`typical_week` added by `20260730160000`). Climate/location is deliberately not part of this screen's scope — moved to `P4-HOME-05`'s first-use-of-§6.11 prompt; criterion amended 2026-07-30 — see "Acceptance criteria that are wrong, rather than unmet" and `Features/Onboarding/Views/OnboardingLifestyleView.swift`'s header comment. |
| P2-ONBOARD-07 | Partial | `StyleQuizEngine`/`StyleQuizCatalog`/`StylePreferenceInference` + 35 tests; pairs content-managed in `Resources/QuizImagery/quiz-pairs.json`, now at `version: 2`. **The shipped catalog holds 14 pairs, inside §6.9's 12–20, and all 8 dimensions produce a reading** — the whole set was regenerated 2026-07-31 from one canonical reference figure, so every frame is the same man and the person is no longer a variable in the instrument. What keeps this Partial is coverage, not quality: **`silhouette` and `logo_tolerance` ship with one pair each**, and one forced choice gives a direction with no magnitude — `StylePreferenceInference.confidence` cannot exceed `.low` below `moderateObservationFloor = 2.0`, so those two axes are `.low` permanently and `PreferenceConfidence.isStatable` will not let Kyra say either one back to the user. The other six axes have two pairs each and reach `.moderate` on agreeing answers. The two missing pairs were generated and rejected — `logo-1-b` returned a real trademark, `silhouette-2-b` varied sleeve length alongside volume — and their corrected prompts are committed in `scripts/generate_quiz_imagery.py`; regeneration is blocked on an OpenAI billing hard limit rather than on an unresolved question. Full record in `ios/AstraStyle/Resources/QuizImagery/README.md`. |
| P2-ONBOARD-08 | Done | `OnboardingStep.reference` (§5.1 step 11, between the quiz and the result) + `Features/Onboarding/Views/OnboardingReferenceView.swift`, `Services/ReferenceImageStore.swift` and `ViewModels/OnboardingViewModel+Reference.swift`. **Both acceptance criteria met.** Skipping does not block completion — the step is skippable like every step except `.identity`, and `OnboardingReferenceTests` asserts a submission with no photo succeeds with `reference_selfie_paths` empty. Consent is shown *before* any picker opens and capture cannot proceed without it: the explanation is a panel on the screen, the acknowledgment is a checkbox, and the picker and camera controls do not exist in the view hierarchy until it is ticked (asserted three ways — `captureRequiresConsent` in unit tests, `testConsentIsRequiredBeforeAnyCaptureControlAppears` and the AX5 variant in `Tests/UITests/OnboardingCaptureStepsUITests.swift`). **The copy stands alone because the legal documents do not exist** — `AstraLegal.isPublished` is false and every URL is nil, so there is no link and the panel says in four plain sections what the photo is for, where it goes, what is never done with it (never used to train a model, nothing measures or identifies the face) and how to remove it, plus one line saying the Privacy Policy is unpublished and that nothing above depends on it. **Nothing is uploaded at capture time.** The image is written to `FileReferenceImageStore` (complete file protection, backup-excluded, user-scoped) and uploaded once during `submit()` to `users/{uid}/references/{uuid}.jpg` in the private `user-content` bucket, lowercased user id — the argument is in `uploadReferenceImageIfNeeded()`'s doc comment; the short version is that ADR 0010's abandoned-upload sweep does not exist, so nothing should be left behind to sweep. A guest uploads nothing at all (ADR 0011) and his copy stays on the device; a failed upload never fails the submission and surfaces a retry on §6.10. 13 unit tests in `Tests/UnitTests/OnboardingReferenceTests.swift`. **Not verified: the camera path.** A simulator has no camera, so `ReferenceCameraPicker` is correctly not offered there and is exercised by nothing. |
| P2-ONBOARD-09 | Done | `OnboardingStep.firstItems` (§5.1 step 12) + `Features/Onboarding/Views/OnboardingFirstItemsView.swift` and `ViewModels/OnboardingViewModel+FirstItems.swift`. **Both acceptance criteria met.** Skip proceeds straight to §6.10 and on to Home — nothing on the step can disable the footer's forward button, proven by `skippingDoesNotBlockReachingHome`, by `aBrokenBackendStillLetsHimLeave` (a `ClosetRepository` that fails every write still cannot trap the user), and end to end by `OnboardingCaptureStepsUITests.testSkippingFirstItemsStillReachesHome`. The step does not degrade to skip-only: it writes real `closet_items` rows through `ClosetRepository`, so it does not wait on Phase 3 — but the form is deliberately three fields (name, category, colour) because `P3-CLOSET-08` owns the full editor and a second one here would drift. Nothing touches the scanner (`P3-SCAN-*` does not exist). Guest behaviour is the real one: `AppContainer` hands the flow `GuestAwareClosetRepository`, so a guest's items stay local, the 10-item cap is enforced in `GuestClosetRepository` and surfaces here as a typed `GuestClosetError.capReached` that closes the form and explains itself rather than throwing an error dialog — and the step is still skippable at the cap. The remaining allowance is shown before he starts, counted from local storage rather than from this session so a resumed draft agrees with the repository. 12 unit tests in `Tests/UnitTests/OnboardingFirstItemsTests.swift`. |
| P2-ONBOARD-10 | Done | `Features/Onboarding/Views/OnboardingResultView.swift` + `Features/Onboarding/Components/StyleDNASections.swift` render all six §6.10 sections from the `style-dna/generate` response, plus the three honesty fields (`known_inputs`, `open_questions`, `measured_dimensions`) the six sections cannot keep the step's own promise without. The palette is drawn as swatches resolved through `Core/DesignSystem/Tokens/AstraGarmentColor.swift`, always beside the colour's name (§19: colour is never the sole carrier of meaning) and name-only when this build has no swatch for a word the server sent. **Edit and regenerate edits the INPUT, not the prose** — the §6.5 identity picks, via `updateStyleProfile` then `generateStyleDNA`, the two-call order `ProfileRepository` documents; the argument is in `OnboardingViewModel.regenerate`'s doc comment. Submission moved to the way IN to §6.10 (`loadStyleDNA()`), because the endpoint reads the profile rows rather than taking a body, so generating first returned a null identity for every new user. Three cases pinned by `Tests/UnitTests/StyleDNAResultTests.swift` (15 tests): rich, sparse, and a null `primary_identity` that is never backfilled. Guests reach `.guestPreview` with zero calls (ADR 0011). UI coverage in `Tests/UITests/OnboardingFlowUITests.swift` — every section reachable by scrolling both directions at AX5, and an edit that changes the headline. |
| P2-ONBOARD-11 | Done | `restore()` reopens at `draft.furthestStepReached`; `FileOnboardingDraftStore` is user-scoped and written on every mutation; routes to `.main` on success. |
| P2-ONBOARD-12 | Done | `supabase/functions/profile/` (`index.ts`/`handler.ts`/`schema.ts` + 40 Deno tests) serving `POST /profile/complete-onboarding` via `_shared/routing.ts`, deployed to `anutsdzbxycaavmmkewo`. All three criteria verified against production with a real JWT: the call returned **200** with `onboarding_completed_at` set and all four tables written, while a payload carrying a different `user_id` in every document still wrote as the JWT's user (the write goes through `supabase/migrations/20260730190000_complete_onboarding_rpc.sql`, which has no user-id parameter — `auth.uid()` is the only identity source); a malformed enum returns 400, not 500 (`profile/schema_test.ts`). The write is atomic: one `SECURITY INVOKER` plpgsql function, so a failure leaves nothing written rather than a half-populated profile. The §6.9 vector round-trips with absent axes absent and `observations: 0` axes intact, confirmed on the live row. Unauthenticated returns 401; an unknown path under the slug returns 404. |
| P2-CORE-01 | Partial | `LiveProfileRepository` implements read/upsert for all four tables. **No SwiftData caching** and **no `OfflineMutationQueue` dependency** — both acceptance criteria unmet. |
| P2-CORE-02 | Partial | The protocol, the mock and the endpoint all exist and are deployed; **the "one live adapter" half of the ticket's scope does not.** Built: `supabase/functions/_shared/providers/stylistReasoning.ts` (spec §8's protocol, verbatim), `supabase/functions/style-dna/deterministicStylist.ts` (a genuinely useful mock — ten distinct identity playbooks, palettes modulated by the §6.9 vector, cut advice from the derived frame axes), and `supabase/functions/style-dna/` serving `POST /style-dna/generate`, deployed and returning **200** against production with a real JWT. Criterion 1 (output maps 1:1 onto the six §6.10 sections) and criterion 3 (sparse input) are met with evidence: 74 Deno tests plus `Tests/UnitTests/StyleDNADecodingTests.swift`, including an identity-only profile producing named garments and a non-empty `open_questions`, and a no-identity profile returning a null identity rather than inventing one. Criterion 2 (a provider swap needs no client change) is structurally satisfied — `style-dna/handler_test.ts` runs the same request through two unrelated providers and asserts identical status, envelope and persisted columns — but cannot be *demonstrated* until a real vendor adapter exists, which is why this is Partial. No vendor key, no retry/circuit-breaker baseline (`docs/08` §0.1), no escalation router (`docs/09` §2), and no golden-set eval have been built. |
| P2-HOME-01 | Done | `HomeView` + `DailyBriefHeaderView`, `HeroOutfitCardView`, and 6 secondary modules; `HomeBriefProvidingTests` cover the zero-item path. Built well past "skeleton". |
| P2-HOME-02 | Done | `HomeEmptyStateView.swift:28` carries the §21 copy verbatim; CTA calls `router.startScan()`; state recomputed in `.task`. |
| P2-INFRA-01 | Partial | `vector` extension enabled; live `style_profiles.embedding` is `vector(1536)`; hnsw `vector_cosine_ops` index exists. **No test inserts a fixture embedding or asserts cosine ordering.** |

---

# PHASE 3 — CLOSET

**5 Done · 7 Partial · 15 Not started.** Split cleanly in two. The CLOSET half is now substantially
real UI: overview, category screen, item detail, manual add, item actions, metrics, three view
modes and the filter panel all ship and are reachable, on a data layer that is applied to
production. The SCAN half is untouched — no camera, no Vision, no server-side analysis — which is
why `P3-CLOSET-03` is still Partial and why the closet's only working way in is typing.

| Ticket | Status | Evidence |
|---|---|---|
| P3-SCAN-01 | Not started | No `AVFoundation`/camera code anywhere; `Features/Scanner/` holds only `README.md`. |
| P3-SCAN-02 | Not started | No Vision-based blur/exposure/segmentation code (zero `VNDetect` hits). |
| P3-SCAN-03 | Not started | No OCR or dominant-colour extraction. |
| P3-SCAN-04 | Not started | No resize/compress/EXIF-strip pipeline. |
| P3-SCAN-05 | Partial | `LiveClosetRepository.uploadCaptured()` now targets the bucket that exists (`user-content`) and lowercases the user id in the path — the storage policies compare `(storage.foldername(name))[2]` to `auth.uid()::text`, which Postgres renders lowercase while Swift's `UUID.uuidString` is uppercase, so the original would have been rejected by RLS even after the bucket name was corrected. Still Partial: no signed-URL read path, and nothing calls it yet (no scan UI — see P3-SCAN-01). |
| P3-SCAN-06 | Not started | Zero `PhotosPicker`/`PhotosUI` hits. |
| P3-SCAN-07 | Not started | No `supabase/functions/closet/`. Client protocol method targets a nonexistent function. |
| P3-SCAN-08 | Not started | `batchAnalyzeItems` defined client-side only; no server function. |
| P3-SCAN-09 | Not started | No review screen; `Features/Closet/` and `Scanner/` are empty. |
| P3-SCAN-10 | Not started | No server-side background removal. |
| P3-SCAN-11 | Not started | No unlock-count logic; `HomeBriefData.purchaseOpportunity` is hardcoded `nil`. |
| P3-SCAN-12 | Not started | No receipt or mirror capture modes. |
| P3-CLOSET-01 | Done | `20260728100300_closet.sql` creates both tables with all spec columns + `embedding vector(1536)`; RLS applied and cross-user isolation asserted; live in production. |
| P3-CLOSET-02 | Partial | Full CRUD via Postgrest, writes queued on failure. **Reads have no local cache** — `PersistedClosetItem` is wired only to the guest store, never `LiveClosetRepository`. |
| P3-CLOSET-03 | Partial | `Features/Closet/Views/ClosetView.swift` + `ClosetCategoryView.swift`, `ViewModels/ClosetViewModel.swift`, `Routing/ClosetDestinationView.swift`, `Components/` (category tile, grid tile, skeleton, empty state, error state, offline banner), wired into `MainTabView.closetTab` in place of `FeaturePlaceholderView`. Criterion 1 is met: a category tile pushes `ClosetRoute.category(_)` to a grid of that category alone. **Criterion 2 is now the only thing holding this Partial** — the scan button calls `AppRouter.startScan()`, which is the flow's single entry point, and that presents `FeaturePlaceholderView` until `P3-SCAN-01` exists. The button reaches the scanner flow; the scanner flow does not exist. The §6.14 header is otherwise complete: the filter button landed with `P3-CLOSET-05`'s panel and the metrics row and view-mode toggle with `P3-CLOSET-04`, and the paragraph in `ClosetView.swift` that argued for their absence has been deleted rather than left describing a state that no longer holds. That header is now laid out with `ViewThatFits` — a display-weight title plus four glyph controls does not fit one line, and not only at accessibility text sizes: at the default size on a 320pt-wide phone the title loses about a hundred points to the controls, so a threshold keyed to Dynamic Type would have fixed the loud half and shipped the quiet half. The fallback row wraps rather than truncating or scaling text down. "All items" still has no `ClosetRoute` case and was not given one — the eighth tile scrolls to the whole-closet grid already on the page. Search is real, narrows on name, brand and colour, and now composes with filters through the single `narrowed(_:)` seam. Tests: `Tests/UnitTests/ClosetViewModelTests.swift`. |
| P3-CLOSET-04 | Partial | `Features/Closet/Models/ClosetMetrics.swift`, `Models/ClosetViewMode.swift`, `Models/ClosetColorSpectrumOrder.swift`, `Components/ClosetMetricsRow.swift`, `Components/ClosetViewModeToggle.swift`, `Components/ClosetCompactList.swift`, `Components/ClosetColorSpectrum.swift`, `Core/Utilities/CurrencyFormatting.swift`, all reachable: the metrics row sits between the category tiles and the grid in `Views/ClosetView.swift`, the toggle is in that screen's header and in `Views/ClosetCategoryView.swift`'s navigation bar, and the selection persists in `@AppStorage("closet.viewMode")` under one key both screens read. **Both acceptance criteria are met.** Criterion 1: metrics are a pure function of the item array (`ClosetMetrics.compute(for:)`), exposed as a computed `ClosetViewModel.metrics` with nothing stored, so there is no cache a future mutation can forget to invalidate; adding, archiving and marking worn are each asserted, archiving in both shapes it can arrive in (the row leaves the array, or stays and gains an `archived_at`). Criterion 2: the colour spectrum's ordering is verified against fixture closets with known colours. **Partial, not Done, for exactly one reason: versatility is absent.** §6.14 lists six metrics and five ship. Versatility is defined in `docs/05-wardrobe-graph.md` §5.1 against outfit data and a compatibility score that are both Phase 4 work; its only producer, `LiveClosetRepository.fetchWardrobeScore()`, throws `AstraError.unimplemented` and no `wardrobe_scores` table exists. A client-side substitute (category/colour spread) was considered and deliberately rejected: it would render in the same type, in the same row, beside four measured figures, and would move when the real scorer lands for reasons no user could connect to anything he did. The gap is recorded in `ClosetMetrics.swift`'s header, and the row grows a sixth tile in Phase 4 without a shape change. One documented judgement: metrics are computed over the whole closet, not the search-narrowed view — a category tile's count is a door and must match what is behind it, but "estimated closet value" falling because three letters were typed into a search field reads as money going missing. Tests: `Tests/UnitTests/ClosetMetricsTests.swift` (28), `ClosetViewModeTests.swift` (7), `ClosetColorSpectrumOrderTests.swift` (32) — 67 tests, all passing. |
| P3-CLOSET-05 | Done | `Features/Closet/Models/ClosetFilters.swift` (all eight §6.14 facets: category, colour, season, brand, condition, fit, availability, and wear as the two axes the row can actually support — a count and a recency, never a rate, because there is no denominator on the device), `Models/ClosetFilterOptions.swift`, `Views/ClosetFilterPanelView.swift`, `Components/ClosetFilterButton.swift`; presented as a sheet from `Views/ClosetView.swift`, bound to `filters` on `ViewModels/ClosetViewModel.swift`. **Both acceptance criteria met and asserted.** Criterion 1: values OR within a facet and facets AND across them — AND within a facet would make every multi-select empty the screen on its second tap — verified against a fixture closet including the category+colour intersection the ticket names. Criterion 2: `apply(to:)` returns the identical array it was handed when nothing is active, so clearing cannot put the screen through a reload; nothing on this path fetches or can produce a `.loading` state. The control is not a dead door in any state: the button is drawn only where `!options.isEmpty || activeFacetCount > 0`, so it is absent where there is nothing to filter but never absent while a filter is on; chips are derived from the search-narrowed, filter-free scope, so every offered value matches something on screen and none shifts under the user's finger as he taps; and a filter set that excludes everything gets its own empty state and its own recovery rather than a blank grid (`ClosetViewModel.EmptyReason.noFilterMatches` and `Components/ClosetEmptyStateView.swift`, which withholds the manual-add affordance there for the same reason the search state does). Deliberately NOT offered on the category screen: that screen is the category facet already applied, and it holds its own view model, so a filter set there would be a second invisible one behind the same glyph — argued in `Views/ClosetCategoryView.swift`'s header. Tests: `Tests/UnitTests/ClosetFiltersTests.swift` (40), all passing. |
| P3-CLOSET-06 | Partial | `Features/Closet/Views/ClosetItemDetailView.swift` + `ViewModels/ClosetItemDetailViewModel.swift`, reached by `ClosetRoute.itemDetail(itemID:)`. Criterion 1 met for every §6.15 field the model can answer, and editable fields save through `P3-CLOSET-08`'s form, presented here as a sheet over the loaded item. Criterion 2 met in its stated initial form: wear count and last-worn render real `closet_items` values, which are zero and empty until Phase 4 writes them. **Two §6.15 fields are absent because the data does not exist, not because they were skipped:** *care instructions* has no `closet_items` column and no `ClosetItem` property (adding one without a migration fails `check_column_drift.py`), and *outfit count* needs `outfit_items` (`P4-OUTFIT-*`). Neither is stubbed. §6.15's Insights block (best pairings, outfit gallery, redundancy score, replacement suggestion) is `P3-CLOSET-07` and depends on the Phase 4 compatibility engine; the screen leaves room below the fields rather than faking it. Absent optional fields are omitted rather than rendered as dashes, except the four where absence is itself the answer (wear count, last worn, cost per wear, laundry state), which always render with copy saying what the blank means. Tests: `Tests/UnitTests/ClosetItemDetailViewModelTests.swift`. |
| P3-CLOSET-07 | Not started | No insights section; `WardrobeScore.redundancyControl` is never populated. |
| P3-CLOSET-08 | Done | `Features/Closet/ViewModels/ClosetItemFormViewModel.swift`, `Views/ClosetItemFormView.swift`, `Components/ClosetColorPicker.swift`, `Components/ClosetAddItemSheet.swift`. **Both acceptance criteria met, and the path is reachable.** A garment goes in end to end with no camera anywhere in it — nothing in the feature imports AVFoundation, offers a "scan instead" affordance, or reaches `analyzeItem`. The door is in two places on purpose: the Closet header (`closet.header.addManually`) and the two "you own nothing here" empty states (`closet.empty.addManually`). Header as well as empty state, because the empty state disappears once the closet holds one item, so an empty-state-only entry point would let a man add his first garment and never a second. Name and category block submission — name trimmed, so three spaces is not a name — and submit is disabled with the reason rendered beneath it rather than silently greyed; every other field is optional and an untouched price stores `nil`, not `0`. One screen serves both add and edit: `Mode` changes only the copy, where the user id comes from, and which repository verb runs, so it is also `P3-CLOSET-06`'s edit surface. Editing rebuilds the row by mutating a copy of the original, so `id`, `user_id`, `created_at`, `wear_count`, `last_worn_at`, `archived_at`, `embedding` and the derived scores survive by construction rather than by a checklist. `SessionStore.currentUserID()` was added alongside the existing `currentGuestUserID()` so the form resolves an owner for a guest and a real account alike. Guest behaviour is the real one: `GuestClosetError.capReached` surfaces its own sentence as a non-retryable notice and, unlike the onboarding step, does not close the form or discard the draft. Supersedes the throwaway add form in `Features/Slice/`. 24 unit tests in `Tests/UnitTests/ClosetItemFormViewModelTests.swift`. |
| P3-CLOSET-09 | Done | `Features/Closet/Components/ClosetItemActionRow.swift` driven by `ClosetItemDetailViewModel`; the repository half was already true and is now reachable from the UI. **Both criteria met and asserted:** mark worn increments `wear_count` by 1 and sets `last_worn_at` to now; archive sets `archived_at`, leaves the row in place, and `fetchItems()` already filters it out of default views. All three writes apply optimistically and roll back on failure, so the screen never shows a wear count, laundry state or archive the database does not have — pinned by three tests named for exactly that. Archive fires `AstraHaptics.warning()` per spec §3 and does not dismiss on failure, because dismissing would tell a man his jacket was gone while it is still there. Edit opens `P3-CLOSET-08`'s form. §6.15's "Sell/donate" is explicitly a later action and is not stubbed. Tests: `Tests/UnitTests/ClosetItemDetailViewModelTests.swift`. |
| P3-CLOSET-10 | Done | `CostPerWearCalculator` + tests: $100/4→$25, 0 wears→nil, missing price→nil, rounding, average, projection. |
| P3-CLOSET-11 | Partial | Guest 10-item cap enforced and tested. **Free-tier 30-item cap is explicitly absent** — the test asserts non-guests route through "uncapped". |
| P3-INFRA-01 | Not started | `OfflineMutationQueue` is FIFO-only; no conflict rule, no last-write-wins on `updated_at`, no conflict test. |
| P3-INFRA-02 | Not started | No scan capture exists to queue; no "pending analysis" state. |
| P3-TEST-01 | Partial | Cost-per-wear and offline replay-after-failure tests exist and pass. Redundancy-score test cannot exist — no redundancy logic does. |
| P3-TEST-02 | Not started | `AstraStyleUITests.testAddGarment()` is an unwritten placeholder — it reports as an explicit `XCTSkip` naming the assertions it owes. |

---

# PHASE 4 — OUTFIT INTELLIGENCE

**2 Done · 11 Partial · 13 Not started.** The most misread phase. The Home tab is a near-complete
Phase 4 vertical build (19 files) sitting in `Features/Home/`, and the deployed outfit generator is
deliberately a placeholder scorer, not the real one.

| Ticket | Status | Evidence |
|---|---|---|
| P4-OUTFIT-01 | Done | `20260728100400_outfits.sql` creates `outfits`/`outfit_items`/`outfit_wears` with embeddings; RLS + cross-user isolation tested; live in production. |
| P4-OUTFIT-02 | Partial | `CompatibilityBreakdown.score(weights:)` implements and tests the weighted-sum formula on caller-supplied values. **No type computes the 8 dimensions from real closet items**, and there is no server-config fetch with fallback. |
| P4-OUTFIT-03 | Not started | No `compatibility_weights` table or endpoint anywhere. |
| P4-OUTFIT-04 | Not started | No colour-compatibility or formality-alignment sub-scorer; `docs/05`'s CIE LCh algorithm has zero corresponding code. |
| P4-OUTFIT-05 | Partial | `FrameHarmonyScorer`/`FrameDerivation`/`FitRules` + `FrameFitTests` are real, tested silhouette-on-wearer work blended into `silhouetteCompatibility`. Garment-vs-garment silhouette, season/weather, and user-preference sub-scorers do not exist. |
| P4-OUTFIT-06 | Not started | No co-wear, occasion-relevance, or availability/laundry sub-scorer. |
| P4-OUTFIT-07 | Partial | `POST /outfits/generate` deployed and JWT-validated, returns `desiredCount` outfits. **Scoring is `LeastRecentlyWornScorer`, whose own header says "NOT the real compatibility scorer"** — every outfit's `reason` is an identical hardcoded string, violating the non-generic-reason criterion. No P95 measurement. |
| P4-OUTFIT-08 | Not started | `outfits/index.ts` says "`POST /rank` -> not built yet". Client `rankOutfits()` 404s. |
| P4-OUTFIT-09 | Not started | No unlock-count algorithm; `ProductEvaluation.outfitsUnlocked` is a passive field, never computed. |
| P4-OUTFIT-10 | Not started | `WardrobeScoring.swift` is protocol + constants only — no conforming scorer exists, so nothing in this repo can compute a score. `fetchWardrobeScore()` used to query a `wardrobe_scores` table that no migration creates, failing on every call in production while Home's `try?` hid it; it now throws `AstraError.unimplemented` and says so at the throw site. The migration was deliberately **not** written: an empty table would produce the same blank module with more schema to maintain. Build the scorer first, then the table. |
| P4-OUTFIT-11 | Not started | `Features/Outfits/` holds only `README.md`; `HomeDestinationView.outfitDetail` resolves to `FeaturePlaceholderView`. |
| P4-OUTFIT-12 | Not started | No outfit builder UI or view model. |
| P4-OUTFIT-13 | Partial | `AlternativeLooksCarouselView` is a real reusable paged component, but its required second reuse site (Outfit detail) does not exist. |
| P4-OUTFIT-14 | Partial | `recordWear()` writes `outfit_wears` and the `bump_closet_item_wear_stats()` trigger increments item counts. **Nothing anywhere writes a `style_feedback` row** — the model has zero writers. |
| P4-OUTFIT-15 | Partial | Full Postgrest CRUD with correct `role`/`sort_order`/`is_required`. **No offline cache wired for reads** — `PersistedOutfit` is never read or written by the live repository. |
| P4-HOME-01 | Done | `20260728100700_planning.sql` creates `daily_briefs` with RLS; live in production; isolation tested. |
| P4-HOME-02 | Not started | No `supabase/functions/daily-brief/`. Client `generateDailyBrief()` targets a nonexistent function. |
| P4-HOME-03 | Partial | `HeroOutfitCardView` renders every required element and wires all 4 actions. But Edit and Visualize both resolve to placeholders, and the displayed confidence comes from the placeholder scorer. |
| P4-HOME-04 | Partial | Wardrobe-score, laundry-alert and upcoming-occasions modules built and wired. Home's own README admits purchase-opportunity never populates and `MonthlyProgressModuleView` is previewable but unwired. |
| P4-HOME-05 | Not started | `weatherService` is never called in `loadTodayBrief`/`loadGuestBrief`; `WeatherService.currentSnapshot()` has **zero production call sites**. |
| P4-HOME-06 | Partial | `occasions` migration + RLS done, and `CalendarService.fetchUpcomingEvents` feeds the brief. No manual add-occasion UI or repository method exists. |
| P4-CORE-01 | Partial | `LiveWeatherService` is a complete WeatherKit + CoreLocation adapter requesting permission in context. No fallback to last-known forecast on failure, and per P4-HOME-05 it is never called. |
| P4-TEST-01 | Partial | `CompatibilityScoringTests` fully covers the weighted aggregate. Per-sub-scorer pass/fail cases cannot exist — 7 of 8 sub-scorers don't. |
| P4-TEST-02 | Not started | No test for Wardrobe Score or unlock count; neither algorithm exists. |
| P4-TEST-03 | Not started | `PendingIntegrationRequirementsTests.dailyBriefGeneration()` is a deliberate placeholder, `.disabled()` with the reason stated. |
| P4-TEST-04 | Not started | `testGenerateOutfit()`/`testMarkOutfitWorn()` are unwritten placeholders — both report as explicit `XCTSkip`s naming the assertions they owe. |

---

# PHASE 5 — KYRA

**1 Done · 3 Partial · 18 Not started.** Client protocols and the live repository conformance are
fully wired into DI; there is no UI and no server. `docs/06` and `docs/09` are implementation-ready
design, not evidence of build.

| Ticket | Status | Evidence |
|---|---|---|
| P5-KYRA-01 | Done | `20260728100500_feedback_and_memory.sql` creates `kyra_threads`/`kyra_messages`/`style_memories` with embeddings; cross-user RLS asserted and run in CI. |
| P5-KYRA-02 | Not started | No `supabase/functions/kyra/`; `EndpointDeploymentMappingTests` pins `requiredNow = ["outfits"]`. |
| P5-KYRA-03 | Not started | No server code. Token budget and truncation order are design-only in `docs/06` §1. |
| P5-KYRA-04 | Not started | No `search_closet` tool; schema exists only as documentation. |
| P5-KYRA-05 | Not started | No `rank_outfits` tool wiring. |
| P5-KYRA-06 | Not started | No "Ask Kyra to finish" code; no `create_outfit` tool. |
| P5-KYRA-07 | Not started | No `get_weather` tool. |
| P5-KYRA-08 | Not started | No `get_schedule` tool. |
| P5-KYRA-09 | Not started | No `save_preference` tool server-side; client memory methods exist but nothing writes memories from a conversation. |
| P5-KYRA-10 | Not started | No `mark_item_worn` tool. |
| P5-KYRA-11 | Not started | No stub tool interfaces — no server code at all. |
| P5-KYRA-12 | Not started | No guardrail layer; the system prompt with its "WHAT YOU NEVER DO" section is design-only. |
| P5-KYRA-13 | Not started | `Features/Kyra/` holds only `README.md`. |
| P5-KYRA-14 | Not started | `KyraCard` model exists; no renderer view. |
| P5-KYRA-15 | Not started | No UI. |
| P5-KYRA-16 | Not started | No microphone or speech code anywhere. |
| P5-KYRA-17 | Not started | No memory UI; Profile has only the guest stub. |
| P5-KYRA-18 | Partial | `LiveKyraRepository` fully implements the protocol. `AstraModelContainer` states Kyra threads are "network-first and simply not cached" — **the offline-cache criterion is unmet by design.** |
| P5-KYRA-19 | Not started | No Kyra rate limiting — no server function to limit. |
| P5-CORE-01 | Partial | **The defensive-parsing criteria are unmet despite a passing happy-path test.** `KyraStructuredResponse`/`KyraIntent` use plain synthesized `Codable`, so a missing optional field or unknown intent throws rather than degrading to `[]`/`.general`. |
| P5-TEST-01 | Partial | `ModelCodableRoundTripTests` has one happy-path decode (`daily_outfit` only); no coverage of the other 5 intents, no malformed-payload test. |
| P5-TEST-02 | Not started | `testAskKyra()` is a deliberate placeholder — reports as an explicit `XCTSkip` naming the assertions it owes. |

---

# PHASE 6 — STUDIO AND COMMERCE

**2 Done · 4 Partial · 19 Not started.** Data layers live in production and the request models are
complete and spec-accurate; nothing renders them. The image vendor was resolved ahead of any
build: **OpenAI, called directly with our own key, and nothing else** — Studio on `gpt-image-1.5`,
quiz imagery and reference generation on `gpt-image-2` (`docs/15` §5, `docs/16` §4). The
previously-named vendor is dropped outright, so P6-STUDIO-03's provider adapter has one target
and `docs/10`'s integration detail is history rather than a spec.

| Ticket | Status | Evidence |
|---|---|---|
| P6-STUDIO-01 | Done | `20260728100800_studio_and_subscriptions.sql` creates `studio_generations`; cross-user RLS tested. |
| P6-STUDIO-02 | Not started | No reference-image capture UI. |
| P6-STUDIO-03 | Not started | No `ImageGenerationProvider` protocol file — referenced only in comments. |
| P6-STUDIO-04 | Not started | No `supabase/functions/studio/`. |
| P6-STUDIO-05 | Not started | No prompt-template assembly; `docs/10` and `docs/15` are design-only. |
| P6-STUDIO-06 | Not started | No status endpoint; client `fetchStatus(generationID:)` calls an undeployed route. |
| P6-STUDIO-07 | Not started | No cost-control, caching, or retention job. |
| P6-STUDIO-08 | Not started | No UI; `Features/Studio/` empty. |
| P6-STUDIO-09 | Partial | Data model complete and spec-exact — all 8 `StudioPromptPreset` cases, background, pose, preserve-face/proportions/hair, formality, season, palette. **Zero UI exposes any of it.** |
| P6-STUDIO-10 | Not started | No generation-state UI. |
| P6-STUDIO-11 | Not started | No gallery UI, though repository fetch/delete methods exist. |
| P6-STUDIO-12 | Partial | `LiveStudioRepository` conforms (submit/status/retry/delete, `hasUserConsent` guard) but has **no polling loop or backoff** — single-shot only — against an undeployed endpoint. |
| P6-SHOP-01 | Done | `20260728100600_commerce.sql` creates `product_candidates`/`user_product_evaluations`; RLS proves shared-read/service-write and per-user isolation. |
| P6-SHOP-02 | Not started | No `ProductExtractionProvider` protocol. |
| P6-SHOP-03 | Not started | No `supabase/functions/products/`; client `extractProduct(from:)` targets nothing. |
| P6-SHOP-04 | Not started | No evaluate endpoint. `ProductEvaluation` matches the migration schema but nothing computes it. |
| P6-SHOP-05 | Not started | No decision-page UI. |
| P6-SHOP-06 | Not started | No "Shop the look" UI. |
| P6-SHOP-07 | Not started | No `SFSafariViewController` anywhere. `LiveShoppingRepository`'s four wishlist methods used to query a `wishlist_items` table that no migration creates; they now throw `AstraError.unimplemented`. The migration was deliberately not written ahead of the Phase 6 UI that has to live with the schema — see the file header for the reasoning. |
| P6-SHOP-08 | Partial | RLS proves `product_candidates` writes are service-role-only (2nd criterion, tested). No ingestion script or seed path demonstrates the 1st. |
| P6-SHOP-09 | Not started | No `sponsored` field in the models or the migration. |
| P6-SHOP-10 | Partial | `extractProduct`, `evaluateProduct` and `fetchCuratedProducts` are implemented for real. The four wishlist methods are now honestly `AstraError.unimplemented` rather than Postgrest calls against a nonexistent `wishlist_items` table; evaluations are still explicitly not cached. |
| P6-CORE-01 | Not started | `Features/Discover/` holds only `README.md`; no editorial-content table in any migration. |
| P6-TEST-01 | Not started | `PendingIntegrationRequirementsTests.studioJobPolling()` is a deliberate placeholder, `.disabled()` with the reason stated. |
| P6-TEST-02 | Not started | `PendingIntegrationRequirementsTests.productEvaluation()` is a deliberate placeholder, `.disabled()` with the reason stated. |

---

# PHASE 7 — MONETIZATION AND HARDENING

**0 Done · 8 Partial · 28 Not started.** Expected — this phase hardens features that mostly do not
exist yet. Several tickets here will be **Unverifiable** rather than Done even once built, because
they need a StoreKit sandbox, a physical device, or App Store review.

| Ticket | Status | Evidence |
|---|---|---|
| P7-SUB-01 | Partial | Migration + RLS done; `AstraProductID` defines both product IDs client-side. App Store Connect configuration is not demonstrable in-repo — that component is Unverifiable. |
| P7-SUB-02 | Not started | No `import StoreKit` purchase code anywhere; only doc comments. |
| P7-SUB-03 | Not started | No `subscriptions/sync` or `app-store/webhook` functions. |
| P7-SUB-04 | Not started | Only `Subscription.isEntitledToPremium` (a status boolean). No closet-cap, Kyra-limit, or Studio-quota gating. |
| P7-SUB-05 | Not started | No paywall UI; `Features/Subscription/` empty. |
| P7-SUB-06 | Not started | No `.storekit` file checked in; `ios/README.md` §6 tells the developer to create one by hand. |
| P7-SUB-07 | Partial | `LiveSubscriptionRepository` conforms to the protocol but calls undeployed endpoints and has no purchase flow to trigger it. |
| P7-PRIVACY-01 | Partial | **The most misleadingly advanced ticket in the repo.** `account_deletions`, `request_account_deletion()`, `finalize_account_deletion()`, the cascade chain and RLS are production-grade and were hardened today — but **no `DELETE /account` Edge Function exists**, so no deletion can actually happen. |
| P7-PRIVACY-02 | Not started | No deletion UI. |
| P7-PRIVACY-03 | Not started | No export feature. |
| P7-PRIVACY-04 | Not started | No per-image deletion UI (depends on unbuilt P6-STUDIO-11). |
| P7-PRIVACY-05 | Not started | No Privacy Policy or ToS content anywhere in the repo, and none should be invented here — this needs a human and probably a lawyer. `Core/Utilities/AstraLegal.swift` is now the single documented point of change: register the domain, publish the four documents, flip `isPublished`, update `LegalDocumentAvailabilityTests`. Until then every legal URL is `nil` and callers must handle it. See also P1-AUTH-06. |
| P7-PRIVACY-06 | Not started | No training-opt-out column; no ATT code. |
| P7-PRIVACY-07 | Not started | No `analytics_events` table in any migration; `LiveAnalyticsClient.log()` is a no-op stub. `AnalyticsEvent` is designed to exclude PII by construction. |
| P7-DS-01 | Not started | No audit artifact; 2 of the 5 required screens (Kyra conversation, paywall) don't exist to audit. |
| P7-DS-02 | Not started | No Phase 7 VoiceOver pass; scattered `accessibilityLabel` usage exists from earlier phases. |
| P7-DS-03 | Partial | `accentChampagneAccessible` ships as the **default**, unconditionally, rather than behind a toggle — criterion amended 2026-07-30 to match, since applying it unconditionally is strictly better than gating it behind a setting a user has to find. `AstraScoreMeter` already pairs colour with numeral and text for confidence/score, but verdict and laundry-state UI don't exist yet to audit — that half of the ticket stays open. |
| P7-DS-04 | Not started | `AstraMotion.aware(_:reduceMotion:)` exists, but the Kyra orb and Studio alt-text UI it would audit do not. |
| P7-HOME-01 | Not started | No `UNUserNotificationCenter` or scheduling code. |
| P7-HOME-02 | Not started | No permission-timing audit; depends on P7-HOME-01 / P5-KYRA-16. |
| P7-HOME-03 | Not started | Only the Home teaser stub exists, documented as pointing at a Phase 7 review that isn't built. |
| P7-HOME-04 | Not started | No packing assistant. |
| P7-HOME-05 | Not started | `Features/Profile/` has only the guest stub — no real profile or stats screen. |
| P7-INFRA-01 | Partial | `_shared/rateLimit.ts` is reusable and applied to `outfits` (20/min), surfaced as `AstraError.rateLimited`. Not applied to any Phase 5/6/7 endpoint — none are deployed. |
| P7-INFRA-02 | Not started | No performance measurements against §20 targets. |
| P7-INFRA-03 | Not started | No thumbnail, downsample, or prefetch code. |
| P7-INFRA-04 | Partial | CI enforces zero-warnings-in-own-code via a scoped build-log grep. No per-dependency purpose/licence documentation (there is one dependency, `supabase-swift`). |
| P7-INFRA-05 | Partial | READMEs cover setup, env vars, migrations, function deployment, StoreKit config and tests. No App Store Connect assets — screenshots, listing copy, privacy nutrition labels — exist anywhere. |
| P7-TEST-01 | Partial | `SubscriptionEntitlementTests` covers active/grace/trialing/non-entitled by status. Free-tier-at-limit, guest-cap and expired-mid-session cases are absent because that gating logic doesn't exist (P7-SUB-04). |
| P7-TEST-02 | Not started | `authLifecycle()` is a deliberate placeholder, `.disabled()` with the reason stated. |
| P7-TEST-03 | Not started | `storeKitSandboxPurchase()` is a deliberate placeholder, `.disabled()` with the reason stated. |
| P7-TEST-04 | Not started | `testCompleteOnboarding()` is a deliberate placeholder — reports as an explicit `XCTSkip` naming the assertions it owes. |
| P7-TEST-05 | Not started | `testOpenPaywallAndRestorePurchases()` is a deliberate placeholder — reports as an explicit `XCTSkip` naming the assertions it owes. |
| P7-TEST-06 | Not started | `testDeleteAccount()` is a deliberate placeholder — reports as an explicit `XCTSkip` naming the assertions it owes. |
| P7-TEST-07 | Not started | No snapshot-testing library is wired in at all. |
| P7-TEST-08 | Not started | Cannot be attempted — most of the §30 definition-of-done sequence has no built UI to exercise. |

---

## Phase exit criteria

`docs/01-build-roadmap.md` carries these as unticked checkboxes. Assessed here rather than there so
there is one place to look; the roadmap stays a planning document.

### Phase 1

| Criterion | Met? | Evidence |
|---|---|---|
| Fresh install → marble splash → Welcome within 1.4 s | Partial | `LaunchingView` + `splashDeadline` enforced via `withDeadline`; no on-device measurement exists. |
| Apple sign-in → empty Home; kill/relaunch restores session | Partial | Sign-in, `handle_new_user()` trigger and 6 `SessionRestoreTests` all present; the live Apple→Supabase leg is an acknowledged §22 placeholder. |
| Guest mode enforces the 10-item cap with no network call | **Yes** | `GuestClosetRepositoryTests` + `GuestModeNetworkTests` (0 intercepted requests). |
| 4 profile tables with RLS returning zero rows cross-user, not an error | **Yes** | `20_rls_isolation_tests.sql`; RLS workflow green. |
| Storage buckets private; unsigned URL returns 403 | Partial | Live bucket is private with 4 path-scoped policies. No automated test — CI Postgres has no `storage` schema. |
| 5 tab items navigate independently and preserve position | **Yes** | `AppRouter` 5 path arrays + `TabNavigationStateTests`. |
| CI runs on every PR and fails on a warning or lint violation | **No** | Zero PRs have ever existed; iOS CI is red on `main` at SwiftLint, so the warning gate has never run. |
| No service-role or provider key anywhere in the iOS target | **Yes** | Grep of target and config finds none; `Secrets.xcconfig` holds only URL + anon key, gitignored. |

### Phase 2

| Criterion | Met? | Evidence |
|---|---|---|
| New user completes onboarding → Home with `onboarding_completed_at` set | **Yes** | `profile` deployed; `POST /profile/complete-onboarding` returned 200 with a real JWT against production and `profiles.onboarding_completed_at` was set (verified by a subsequent read), with all four tables written in one transaction. `OnboardingViewModel.submit()` clears the draft only on success. Since `P2-ONBOARD-10`, that submission runs on the way INTO §6.10 rather than out of it (the Style DNA endpoint reads the profile rows, so they have to exist first), and routing to `.main` is keyed on `isFinished` — the user tapping Finish — rather than on the submission succeeding, which would otherwise skip the result screen entirely. `OnboardingFlowUITests.testWalkTheWholeFlow` still asserts the hand-off to the tab shell. |
| Force-quit mid-onboarding resumes at the same step | **Yes** | `restore()` → `furthestStepReached`; `FileOnboardingDraftStore` + `OnboardingDraftTests`. |
| `POST /style-dna/generate` returns non-placeholder DNA from sparse input | **Yes** | `style-dna` deployed; returned 200 with a real JWT and produced all six §6.10 sections — named garments, a palette modulated by the two measured axes, cut advice from the derived frame axes — from a profile with 2 of 8 preference dimensions scored. Degradation is asserted, not assumed: an identity-only profile still names concrete pieces and lists what is unknown; a profile with no identity and no dress code returns a null identity rather than inventing one (`style-dna/deterministicStylist_test.ts`). |
| User can edit and regenerate Style DNA and see the result change | **Yes** | `OnboardingResultView`'s edit control opens the §6.5 question again; confirming calls `OnboardingViewModel.regenerate`, which writes the edited identity with `updateStyleProfile` and then reads it back with `generateStyleDNA`. `StyleDNAResultTests` asserts the second result differs from the first, that the write carries the columns the generator owns rather than blanking them, and that a failed regenerate keeps the previous result on screen; `OnboardingFlowUITests.testStyleDNAResultShowsEverySectionAndRegenerates` asserts the identity headline actually changes. Editing the generated prose is deliberately not offered — see `OnboardingViewModel.regenerate`'s doc comment for why that would stop Style DNA being a derivation of anything. |
| Skipping "add first closet items" does not block reaching Home | **Yes** | `OnboardingStep.firstItems` exists and is skippable (`isSkippable` is true for everything except `.identity`). Nothing on the step feeds `canAdvance`: an empty form, a write that fails, and a guest at the 10-item cap all resolve to a message beside the form rather than to a blocked footer. `OnboardingFirstItemsTests.skippingDoesNotBlockReachingHome` and `aBrokenBackendStillLetsHimLeave` pin it at the view-model level; `OnboardingCaptureStepsUITests.testSkippingFirstItemsStillReachesHome` walks a guest from the quiz through both new steps without adding anything and asserts the tab bar appears, and `testFirstItemsAtLargestDynamicType` asserts the forward button is still hittable and enabled at AX5, which is where a footer is most likely to be pushed off screen. |
| Every §6.7-optional field can be left blank without a validation error | **Yes** | Only `.identity` is non-skippable; per-field skip in appearance; covered by `OnboardingDraftTests`. |

Phases 3–7 exit criteria are not yet assessed — those phases have not started in earnest, and
assessing them now would produce a wall of "No" with no information in it.

---

## Bugs found during the audit that no ticket covers

These were latent — the code paths were unreachable — but each would have failed outright the
moment its feature was wired up. **1–4 were addressed on 2026-07-30**; the resolutions are
recorded here rather than deleted, because "why does this method throw instead of querying a
table?" is the question the next reader will ask.

1. ~~**`uploadCaptured()` uploads to bucket `"closet"`.**~~ Fixed: uploads to `user-content`, the
   only bucket that exists. The audit under-reported this one — the bucket name was not the only
   defect. The path embedded `UUID.uuidString`, which Swift renders UPPERCASE, while the storage
   policies compare that segment to `auth.uid()::text`, which Postgres renders lowercase. With the
   bucket fixed and the case not, the upload would still have been rejected by RLS while looking
   entirely correct. Both are fixed; see the method's doc comment. (P3-SCAN-05)
2. ~~**`LiveShoppingRepository` queries a `wishlist_items` table that no migration creates.**~~
   Resolved by making the four wishlist methods honestly `AstraError.unimplemented` rather than by
   writing the migration. Wishlist is Phase 6 with no UI, no decision page and no browser
   integration; a table added now would ship untested, unused, and would freeze a schema shape
   ahead of the feature that has to live with it. Reasoning is in the file header. (P6-SHOP-07/10)
3. ~~**`fetchWardrobeScore()` queries a `wardrobe_scores` table that no migration creates.**~~ Same
   resolution, for a stronger reason: `WardrobeScoring` is a protocol plus the §10 weights with no
   conforming scorer, so nothing in this repo could populate such a table. The migration would buy
   a permanently empty table and the same hidden Home module. Now throws `.unimplemented`.
   (P4-OUTFIT-10)
4. ~~**`OfflineMutationQueue.drain()` is never called by anything.**~~ Wired. `LiveClosetRepository`
   drains after every successful call, `attemptCount` is incremented on a failed replay, and the
   false header comment claiming this already happened is gone. Two things the audit did not
   surface and that wiring it exposed: the queue is *shared* with `LiveOutfitRepository`, so a
   single-owner drain needed an explicit "not mine" signal (`OfflineMutationNotHandled`) to avoid
   either discarding or wedging on another repository's mutations — and **outfit/outfitWear
   mutations still have no drainer at all**, which remains open under P1-CORE-06.
5. **`WeatherService.currentSnapshot()` has zero production call sites** — a complete WeatherKit
   adapter that nothing invokes. Still open.

A new `AstraError.Category.unimplemented` backs 2 and 3. It is deliberately distinct from
`.server`: retrying a missing table can never succeed, so the UI should degrade rather than offer
a retry button, and a not-yet-built feature should not be indistinguishable from an outage at the
call site.

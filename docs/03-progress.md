# 03 — BUILD PROGRESS

**Last audited:** 2026-08-06 (photo-first first-items, `P2-ONBOARD-13`); 2026-08-06 (guest mode removed, ADR 0014; `daily-brief` built and deployed); 2026-08-06 (TestFlight defects: §6.11 empty state reachable for signed-in users, 404 mapped to `.unimplemented`, full-bleed app icon, placeholders labelled); 2026-08-01 (Phase 3 exit for TestFlight: SCAN-06 pre-review hints, INFRA-01/02 offline queue+conflict, SCAN-11 unlock report, AppIcon xcassets + `docs/12-testflight-cut.md`); 2026-08-01 (Phase 3 debts + Vision/OCR + review/upload on main); 2026-07-31 (Phase 2 onboarding); earlier 2026-07-30 at `45b4b90c`.

This file answers one question: *which of the 179 tickets in `docs/02-task-breakdown.md` are
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
| **Withdrawn** | The ticket's feature was removed by a decision, so its criteria can never be met. The row must name the ADR that withdrew it — `check_progress.py` enforces that. Every other status would be a lie: `Done` claims a capability nobody can use, `Not started` erases work that was done and then deliberately removed. |

"Partial" is the most common status and that is expected, not a failure. A repo built spec-first
lands data layers, protocols, and models long before the screens that use them.

## Summary

| Phase | Tickets | Done | Partial | Not started |
|---|---|---|---|---|
| 1 — Foundation | 25 | 11 | 12 | 0 |
| 2 — Identity | 18 | 13 | 5 | 0 |
| 3 — Closet | 27 | 15 | 9 | 3 |
| 4 — Outfit intelligence | 26 | 7 | 10 | 9 |
| 5 — Kyra | 22 | 1 | 3 | 18 |
| 6 — Studio and commerce | 25 | 2 | 4 | 19 |
| 7 — Monetization and hardening | 36 | 0 | 8 | 28 |
| **Total** | **179** | **49** | **51** | **77** |

Read that table carefully before drawing a conclusion from it. 49 of 179 "Done" understates where
the project is: Phase 1's foundation is genuinely finished in substance, most Phase 1 "Partial"
rows are missing one narrow criterion rather than the bulk of the work, Phase 2 onboarding is
largely Done, Closet is usable end to end, and a large amount of Phase 3–7 data-layer work is
already applied to production. It also *overstates* readiness in one specific way — see
**Blockers** below.

---

## What is actually blocking, right now

Ranked by what stops the next user-visible thing from working.

1. **iOS CI's negative case is still unproven.** SwiftLint `--strict` and the zero-compiler-
   warnings gate are green locally and on real PRs: **#3 and #4** opened, ran the full
   `ios.yml` job green, and merged (#5 closed without merging; its content landed on `main`).
   First-party code is clean (0 warnings under `ios/AstraStyle/`). What remains open for
   `P1-INFRA-03` is the negative case — no PR has yet been made to *fail* on a warning or a
   lint violation — and the working convention moved to committing directly to `main` on
   2026-08-01, so further positive PR validation may not arrive soon.
2. **The quiz covers all eight dimensions now; one of them is a pair short.** The §6.9
   imagery was regenerated from scratch on 2026-07-31 against a single canonical reference
   figure, and the shipped catalog holds **15 pairs** — inside §6.9's 12–20, with every one of
   the eight preference dimensions returning a value rather than *absent*. What remains is
   narrower, and it is not a code problem: `silhouette` ships with one pair, which is `.low`
   confidence permanently, so Kyra may not state that axis back to the user. `logo_tolerance`
   was in the same position until `logo-01` shipped 2026-07-31 with its mark composited rather
   than generated. The pair that would fix silhouette was generated and rejected — it
   varied sleeve length alongside volume — and its corrected prompt is committed in
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

**11 Done · 12 Partial · 0 Not started · 2 Withdrawn.** Substantively complete. Every Partial below is a narrow
missing criterion, not missing work — but three of them (CI on PRs, SwiftData schema versioning,
the dead offline queue) will cost real money later if they stay open.

| Ticket | Status | Evidence |
|---|---|---|
| P1-INFRA-01 | Partial | `ios/project.yml` (XcodeGen, Swift 6, iOS 18); all 11 spec §8 features exist under `Features/`. No per-feature `Tests/` subfolder — tests are centralised in `Tests/{UnitTests,UITests}`. Extra `Features/Slice` is outside spec §8. |
| P1-INFRA-02 | Partial | `ios/Config/{Base,Debug,Release}.xcconfig` + gitignored `Secrets.xcconfig`; no key material found by grep. **No `Staging.xcconfig`** — ticket requires Debug/Staging/Release. |
| P1-INFRA-03 | Partial | 4 workflows exist. SwiftLint `--strict` now **passes** (swiftlint 0.65.0, 122 violations found and fixed; see `.swiftlint.yml`'s header for what the original hand-estimated thresholds got wrong), so the build step is reachable and the "Fail on warnings in our own code" grep was exercised for the first time — 0 warnings under `ios/AstraStyle/`. Both criteria have since been validated on real PRs: **#3 and #4 were opened, ran the full `ios.yml` job green, and were merged** (#5 was opened and closed without merging, its content landing directly on `main`). Still Partial for a different reason — no PR has yet been made to *fail* on a warning or a lint violation, so the negative case is still unproven, and the working convention moved to committing directly to `main` on 2026-08-01. |
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
| P1-DS-01 | Partial | `Tokens/AstraColor.swift` covers every §3 token in both schemes via a `UIColor` trait provider, and now matches spec §3 exactly — the three deliberately-revised hex values (`textMuted` both schemes, light `accentChampagne`) were ported into spec §3 itself 2026-07-30, cross-referenced to `docs/07-design-system.md`'s contrast analysis. **App Icon + AccentColor now ship** in `Resources/Assets.xcassets`, and since 2026-08-06 the icon is generated by `scripts/build_app_icon.py` rather than exported by hand. The hand-made one shipped a marketing mockup — a rounded, shadowed tile on the mockup's off-white page, letterboxed with black bars, filling 70% of the canvas — which iOS composited as a white border around the mark on the owner's home screen. The script crops the marble tile out of `brand/assets/app-icon-marble.jpg`, fills the rounded corners, squares it full-bleed, and re-renders the mark from `AstraMonogram.swift`'s traced geometry filled solid champagne, because the artwork's mark is embossed and its gold is a rim light that disappears below ~120px. `--check` fails on a bright corner or a mark covering under 8% of the canvas. Spec §3 colour sets as Asset Catalog entries remain unmet — tokens still live in `AstraColor.swift` via trait providers; `surfaceMarble` returns `backgroundPrimary`. |
| P1-DS-02 | Done | `Tokens/AstraTypography.swift` — all 9 styles at exact §3 sizes, correct serif/sans split, `micro` uppercase + 1.5 tracking, `@ScaledMetric(relativeTo:)` throughout. |
| P1-DS-03 | Partial | `AstraSpacing`/`AstraRadius`/`AstraSize` all correct and referenced by name. **No lint rule flags raw point values** — `.swiftlint.yml` has only the sparkle and ticket-id custom rules. |
| P1-DS-04 | Partial | `AstraButton`/`AstraCard`/`AstraChip` on tokens with 44pt minimum targets. **`AstraTextField` exists** (`Core/DesignSystem/Components/AstraTextField.swift`) and is used by Closet forms. **No destructive button variant.** No per-component previews — only 4 whole-page gallery previews. |
| P1-DS-05 | Partial | `AstraMarble` (procedural, not an asset) + `LaunchingView`; session restore bounded by `withDeadline(.milliseconds(1400))`. Marble used at exactly 3 sites, none behind dense text. The "measured, not estimated" 1.4 s criterion has no measurement artifact. |
| P1-DS-06 | Partial | `AstraMotion` — 220 ms standard, springs, Reduce-Motion-aware `.astraAnimation`, haptics mapped per §3 and used at 12 onboarding sites. **No matched-geometry hero helper exists**, and **`AstraMotion.breathing` has zero call sites**, so the Reduce-Motion criterion has nothing to assert against. |
| P1-AUTH-01 | Done | `AppleSignInCoordinator` + SHA-256 nonce; `handle_new_user()` trigger deployed; cancellation maps to `AstraError.cancelled`. Live round-trip is a deliberate §22 placeholder. |
| P1-AUTH-02 | Done | `LiveAuthRepository.requestEmailOTP`/`verifyEmailOTP`; `EmailAuthSheet` is the entry UI; distinct errors for wrong code vs unconfirmed email; `astrastyle` URL scheme registered. |
| P1-AUTH-03 | Done | `SessionStore.restoreSession()` + `SessionRefreshing`; `SessionRestoreTests` — 6 tests including transparent refresh, refresh rejection, corrupt Keychain item, and guest session surviving relaunch. |
| P1-AUTH-04 | Withdrawn | **ADR 0014** removed guest mode; an account is required before onboarding. This was genuinely finished — `GuestClosetRepository` rejected the 11th item, and `GuestModeNetworkTests` proved zero intercepted requests through a `URLProtocol` trap — and has been deleted along with the feature. Not `Done` (nobody can use it) and not `Not started` (the work happened). The free-tier 30-item cap on a signed-in closet is a different rule and still ships: `P3-CLOSET-11`. |
| P1-AUTH-05 | Withdrawn | **ADR 0014** removed guest mode, so there is nothing to migrate from. Worth recording that this was never as finished as its `Done` implied: `LiveGuestMigrationService` migrated closet items and **no profile table**, so a user who onboarded as a guest and then signed in lost his onboarding answers — the exact data loss ADR 0011's own Consequences section predicted. It shipped that way for the feature's whole life. |
| P1-AUTH-06 | Partial | `SignedOutGateView` wires all four actions. The criterion "Terms/Privacy open real documents, not a 404" is **still unmet — no policy text exists** and `astrastyle.app` is still NXDOMAIN (re-verified 2026-07-30 with `nslookup` and `curl`). What changed is the failure mode: `AstraLegal` now gates every URL behind `isPublished` (false) and vends `URL?`, so the dead link is a compile-time obligation rather than a runtime 404, and the welcome screen renders an honest "will be published before release" notice instead of opening Safari on a DNS error — the control still does something, so §22's "no dead buttons" holds. **Writing the documents and registering the domain are product/legal decisions, not code.** Flip `AstraLegal.isPublished` and update `Tests/UnitTests/LegalDocumentAvailabilityTests.swift` in the same change. |

---

# PHASE 2 — IDENTITY

**13 Done · 5 Partial · 0 Not started.** The onboarding flow is complete end to end. §6.3–§6.10 is
built and hardened at AX5, `profile` and `style-dna` are deployed and were exercised against
production with a real JWT, the §6.10 result screen renders what they return, and as of 2026-07-31
the two §5.1-only steps between the quiz and the result exist as well: `P2-ONBOARD-08` (the
optional reference photo, behind an on-screen §29 consent gate) and `P2-ONBOARD-09` (first closet
items, skippable). `OnboardingStep` now has ten cases and the progress indicator reads out of eight
answerable steps rather than six — the count is derived from `allCases`, so nothing had to be
edited to follow it.

`P2-ONBOARD-13` is new (2026-08-06) and is the reason this phase gained a ticket. The first
internal TestFlight build showed the first-items step doing what its ticket asked and still being
wrong: a three-field typing exercise one screen before the payoff, in a product whose whole premise
is that you photograph a garment and it reads it. `P2-ONBOARD-09` stays Done — both of its criteria
are still met and still tested — because reopening a ticket whose criteria were met would make the
status mean "we changed our minds" rather than "the work was not finished", and this file is only
useful if those stay distinct.

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
| P2-ONBOARD-07 | Partial | `StyleQuizEngine`/`StyleQuizCatalog`/`StylePreferenceInference` + 35 tests; pairs content-managed in `Resources/QuizImagery/quiz-pairs.json`, now at `version: 2`. **The shipped catalog holds 15 pairs, inside §6.9's 12–20, and all 8 dimensions produce a reading** — the whole set was regenerated 2026-07-31 from one canonical reference figure, so every frame is the same man and the person is no longer a variable in the instrument. What keeps this Partial is coverage, not quality: **`silhouette` ships with one pair**, and one forced choice gives a direction with no magnitude — `StylePreferenceInference.confidence` cannot exceed `.low` below `moderateObservationFloor = 2.0`, so that axis is `.low` permanently and `PreferenceConfidence.isStatable` will not let Kyra say it back to the user. The other seven axes have two pairs each and reach `.moderate` on agreeing answers. `logo_tolerance` was in the same position until `logo-01` shipped: its first generation returned a real trademark, so the branded frame is now Astra's own monogram **composited onto the plain frame** rather than generated, which makes the pair's backdrop delta 0.0 by construction. `silhouette-2-b` was generated and rejected for varying sleeve length alongside volume; its corrected prompt is committed in `scripts/generate_quiz_imagery.py` and regeneration is blocked on an OpenAI billing hard limit rather than on an unresolved question. Full record in `ios/AstraStyle/Resources/QuizImagery/README.md`. |
| P2-ONBOARD-08 | Done | `OnboardingStep.reference` (§5.1 step 11, between the quiz and the result) + `Features/Onboarding/Views/OnboardingReferenceView.swift`, `Services/ReferenceImageStore.swift` and `ViewModels/OnboardingViewModel+Reference.swift`. **Both acceptance criteria met.** Skipping does not block completion — the step is skippable like every step except `.identity`, and `OnboardingReferenceTests` asserts a submission with no photo succeeds with `reference_selfie_paths` empty. Consent is shown *before* any picker opens and capture cannot proceed without it: the explanation is a panel on the screen, the acknowledgment is a checkbox, and the picker and camera controls do not exist in the view hierarchy until it is ticked (asserted three ways — `captureRequiresConsent` in unit tests, `testConsentIsRequiredBeforeAnyCaptureControlAppears` and the AX5 variant in `Tests/UITests/OnboardingCaptureStepsUITests.swift`). **The copy stands alone because the legal documents do not exist** — `AstraLegal.isPublished` is false and every URL is nil, so there is no link and the panel says in four plain sections what the photo is for, where it goes, what is never done with it (never used to train a model, nothing measures or identifies the face) and how to remove it, plus one line saying the Privacy Policy is unpublished and that nothing above depends on it. **Nothing is uploaded at capture time.** The image is written to `FileReferenceImageStore` (complete file protection, backup-excluded, user-scoped) and uploaded once during `submit()` to `users/{uid}/references/{uuid}.jpg` in the private `user-content` bucket, lowercased user id — the argument is in `uploadReferenceImageIfNeeded()`'s doc comment; the short version is that ADR 0010's abandoned-upload sweep does not exist, so nothing should be left behind to sweep. A guest uploads nothing at all (ADR 0011) and his copy stays on the device; a failed upload never fails the submission and surfaces a retry on §6.10. 13 unit tests in `Tests/UnitTests/OnboardingReferenceTests.swift`. **Not verified: the camera path.** A simulator has no camera, so `ReferenceCameraPicker` is correctly not offered there and is exercised by nothing. |
| P2-ONBOARD-09 | Done | `OnboardingStep.firstItems` (§5.1 step 12) + `Features/Onboarding/Views/OnboardingFirstItemsView.swift` and `ViewModels/OnboardingViewModel+FirstItems.swift`. **Both acceptance criteria met.** Skip proceeds straight to §6.10 and on to Home — nothing on the step can disable the footer's forward button, proven by `skippingDoesNotBlockReachingHome`, by `aBrokenBackendStillLetsHimLeave` (a `ClosetRepository` that fails every write still cannot trap the user), and end to end by `OnboardingFirstItemsUITests.testSkippingFirstItemsStillReachesHome`. The step does not degrade to skip-only: it writes real `closet_items` rows through `ClosetRepository`, so it does not wait on Phase 3 — but the form is deliberately three fields (name, category, colour) because `P3-CLOSET-08` owns the full editor and a second one here would drift. The refusable path is the free-tier cap (§16, `P3-CLOSET-11`): `FreeTierCappedClosetRepository` refuses the 31st write and it surfaces here as a typed `FreeTierClosetError.capReached` that closes the form and explains itself rather than throwing an error dialog — and the step is still skippable at the cap. (It used to be the guest cap; **ADR 0014** removed guest mode and `prepareFirstItemsStep()` is now empty, because a remaining-count for a limit nobody is near in their first minute is a number about nothing.) **The scanner claim in this row was true until 2026-08-06 and is not any more** — the photo path is `P2-ONBOARD-13`, which adds a control to this screen and a `didScanItem(_:)` seam to this view model; both of this ticket's criteria are unaffected and still tested. 11 unit tests in `Tests/UnitTests/OnboardingFirstItemsTests.swift`, plus 4 more for the seam. |
| P2-ONBOARD-13 | Done | The photo path on §5.1 step 12. **All four criteria met.** `OnboardingFirstItemsView.scanCard` is the first thing on the step and `OnboardingFirstItemsUITests.testFirstItemsOffersThePhotoPathFirst` asserts it is `isHittable` without scrolling at the default text size. **At AX5 the bar is order, not no-scrolling** — a headline and two sentences fill that screen on their own and nothing in this flow fits unscrolled at that size, so `testFirstItemsAtLargestDynamicType` asserts `scan.frame.minY < add.frame.minY` (the step must not silently revert to a form with a camera button after it) plus reachable-by-scrolling, and the criterion in `02-task-breakdown.md` says so rather than claiming a standard no screen in the app meets. `OnboardingFlowView` presents `ScannerDestinationView(route: .singleItem)` as a sheet — `.singleItem` and not `.batchCloset`, which is still an honest placeholder and would put "not built yet" one tap inside onboarding. **Nothing here writes.** The scanner has already been through `ClosetRepository.createItem` by the time onboarding hears about it, so `ScannerReviewViewModel.savedItem` carries the repository's RETURN value (the server's normalisation, not the draft) out through `ScannerDestinationView.onItemSaved`, and `OnboardingViewModel.didScanItem(_:)` only records it — guarded on `id` so a completion delivered twice lists one garment once. All four seam tests run against `FailingClosetRepository`, which throws on every write: if this ever started writing, all four would fail rather than quietly creating two rows per photograph. The typed form stays, and **not** as a no-camera fallback — the scanner degrades to a Photos import itself. It stays for the garment that is at the cleaners or in a suitcase. `canAdvance` is untouched: `scanningDoesNotBlockReachingHome`, `skippingDoesNotBlockReachingHome`, `aBrokenBackendStillLetsHimLeave` and `testSkippingFirstItemsStillReachesHome` all still pass. Tests: `Tests/UnitTests/OnboardingFirstItemsTests.swift` (4), `Tests/UnitTests/ScannerReviewViewModelTests.swift` (`savedItemIsTheRepositorysReturnValue`), `Tests/UITests/OnboardingFirstItemsUITests.swift` (2 of its 4 — the other two are `P2-ONBOARD-09`'s, moved with them out of `OnboardingCaptureStepsUITests` when the class crossed SwiftLint's `type_body_length` limit; the shared walk now lives in `Tests/UITests/OnboardingCaptureUITestCase.swift`). |
| P2-ONBOARD-10 | Done | `Features/Onboarding/Views/OnboardingResultView.swift` + `Features/Onboarding/Components/StyleDNASections.swift` render all six §6.10 sections from the `style-dna/generate` response, plus the three honesty fields (`known_inputs`, `open_questions`, `measured_dimensions`) the six sections cannot keep the step's own promise without. The palette is drawn as swatches resolved through `Core/DesignSystem/Tokens/AstraGarmentColor.swift`, always beside the colour's name (§19: colour is never the sole carrier of meaning) and name-only when this build has no swatch for a word the server sent. **Edit and regenerate edits the INPUT, not the prose** — the §6.5 identity picks, via `updateStyleProfile` then `generateStyleDNA`, the two-call order `ProfileRepository` documents; the argument is in `OnboardingViewModel.regenerate`'s doc comment. Submission moved to the way IN to §6.10 (`loadStyleDNA()`), because the endpoint reads the profile rows rather than taking a body, so generating first returned a null identity for every new user. Three cases pinned by `Tests/UnitTests/StyleDNAResultTests.swift` (15 tests): rich, sparse, and a null `primary_identity` that is never backfilled. Guests reach `.guestPreview` with zero calls (ADR 0011). UI coverage in `Tests/UITests/OnboardingFlowUITests.swift` — every section reachable by scrolling both directions at AX5, and an edit that changes the headline. |
| P2-ONBOARD-11 | Done | `restore()` reopens at `draft.furthestStepReached`; `FileOnboardingDraftStore` is user-scoped and written on every mutation; routes to `.main` on success. |
| P2-ONBOARD-12 | Done | `supabase/functions/profile/` (`index.ts`/`handler.ts`/`schema.ts` + 40 Deno tests) serving `POST /profile/complete-onboarding` via `_shared/routing.ts`, deployed to `anutsdzbxycaavmmkewo`. All three criteria verified against production with a real JWT: the call returned **200** with `onboarding_completed_at` set and all four tables written, while a payload carrying a different `user_id` in every document still wrote as the JWT's user (the write goes through `supabase/migrations/20260730190000_complete_onboarding_rpc.sql`, which has no user-id parameter — `auth.uid()` is the only identity source); a malformed enum returns 400, not 500 (`profile/schema_test.ts`). The write is atomic: one `SECURITY INVOKER` plpgsql function, so a failure leaves nothing written rather than a half-populated profile. The §6.9 vector round-trips with absent axes absent and `observations: 0` axes intact, confirmed on the live row. Unauthenticated returns 401; an unknown path under the slug returns 404. |
| P2-CORE-01 | Partial | `LiveProfileRepository` implements read/upsert for all four tables. **No SwiftData caching** and **no `OfflineMutationQueue` dependency** — both acceptance criteria unmet. |
| P2-CORE-02 | Partial | The protocol, the mock and the endpoint all exist and are deployed; **the "one live adapter" half of the ticket's scope does not.** Built: `supabase/functions/_shared/providers/stylistReasoning.ts` (spec §8's protocol, verbatim), `supabase/functions/style-dna/deterministicStylist.ts` (a genuinely useful mock — ten distinct identity playbooks, palettes modulated by the §6.9 vector, cut advice from the derived frame axes), and `supabase/functions/style-dna/` serving `POST /style-dna/generate`, deployed and returning **200** against production with a real JWT. Criterion 1 (output maps 1:1 onto the six §6.10 sections) and criterion 3 (sparse input) are met with evidence: 74 Deno tests plus `Tests/UnitTests/StyleDNADecodingTests.swift`, including an identity-only profile producing named garments and a non-empty `open_questions`, and a no-identity profile returning a null identity rather than inventing one. Criterion 2 (a provider swap needs no client change) is structurally satisfied — `style-dna/handler_test.ts` runs the same request through two unrelated providers and asserts identical status, envelope and persisted columns — but cannot be *demonstrated* until a real vendor adapter exists, which is why this is Partial. No vendor key, no retry/circuit-breaker baseline (`docs/08` §0.1), no escalation router (`docs/09` §2), and no golden-set eval have been built. |
| P2-HOME-01 | Done | `HomeView` + `DailyBriefHeaderView`, `HeroOutfitCardView`, and 6 secondary modules; `HomeBriefProvidingTests` cover the zero-item path. Built well past "skeleton". |
| P2-HOME-02 | Done | `HomeEmptyStateView.swift:28` carries the §21 copy verbatim; CTA calls `router.startScan()`; state recomputed in `.task`. **Reachable for signed-in users since 2026-08-06** — `DefaultHomeBriefProvider.loadTodayBrief` now short-circuits to `loadSparseClosetBrief` below `HomeBriefData.minimumItemsForOutfits`, so a man who has just finished onboarding sees this screen instead of the `P4-HOME-02` 404. Previously only guests could reach it. Pinned by `HomeBriefProvidingTests`' sparse-closet suite, including the fifth-garment boundary and the unreadable-closet case. |
| P2-INFRA-01 | Partial | `vector` extension enabled; live `style_profiles.embedding` is `vector(1536)`; hnsw `vector_cosine_ops` index exists. **No test inserts a fixture embedding or asserts cosine ordering.** |

---

# PHASE 3 — CLOSET

**15 Done · 9 Partial · 3 Not started.** Closet UI and single-item SCAN are end-to-end (capture/import with device hints → upload → analyze → editable review → save → unlock report). Offline: closet read cache, LWW conflict on drain, queued scan while offline that analyzes on reconnect. Free-tier/guest caps and `testAddGarment` land. App Icon asset catalog ships for TestFlight; cut steps in `docs/12-testflight-cut.md`. Still Partial/deferred: device Vision QA, live OpenAI pilot gate, batch/receipt/mirror modes, server cutout, versatility/insights (Phase 4).

| Ticket | Status | Evidence |
|---|---|---|
| P3-SCAN-01 | Partial | Capture screen ships: `Features/Scanner/Views/ScannerCaptureView.swift`, `ViewModels/ScannerCaptureViewModel.swift`, `Routing/ScannerDestinationView.swift`, wired from `MainTabView`’s scanner modal (replacing `FeaturePlaceholderView`). Camera session is protocol-fronted (`CaptureSessionControlling`) with `LiveCaptureSessionController` (AVFoundation) and `MockCaptureSessionController` for CI. Permission is requested only in `onAppear` of the capture screen (spec §7). Live frames feed `CaptureQuality.evaluate` and surface `guidance` in a banner; optional auto-capture fires after consecutive acceptable frames. Framing guide + shutter + Close are real controls. **Criterion 1 met** (permission in context). **Criterion 2 (live blur warning on a shaken device preview) is device-only and has not been run** — Partial, not Done. Continue hands a `CaptureDraft` into `ScannerReviewView` (`P3-SCAN-09`). Tests: `Tests/UnitTests/ScannerCaptureViewModelTests.swift`. |
| P3-SCAN-02 | Partial | `Features/Scanner/Services/CaptureQuality.swift`. §12 step 1 is complete as pure nonisolated functions over a `Sendable` `LuminancePlane`: variance-of-Laplacian focus and histogram exposure, returning per-dimension severities (`acceptable`/`warning`/`blocking`) plus the one instruction to show. Every entry point is synchronous and nonisolated on purpose — that is what lets a capture queue hand it a non-`Sendable` `CGImage` without `@unchecked Sendable`, because a sync nonisolated call runs in the caller's isolation domain. Thresholds are measured rather than taken from literature: the 36 garment photographs in `brand/quiz-imagery` score 122-309, a radius-1 blur scores 44-73 and radius-2 scores 16-26, so warn=90 and block=30 sit in the two gaps; exposure is stated in sRGB-**encoded** space with stop offsets, because a naive "mean < 0.18" rejects frames 1.5 stops brighter than correct. Over-exposure blocks only on clipped fraction **and** high mean together — a dark garment on a white duvet is half near-white and blocking on clipping alone would refuse an ordinary photo. 33 tests in `Tests/UnitTests/CaptureQualityTests.swift` against synthesised fixtures. §12 steps 2–3: `GarmentRegionDetecting` seam plus live adapter `LiveVisionGarmentRegionDetector` (`VNGenerateForegroundInstanceMaskRequest`, attention-saliency fallback) and `MockGarmentRegionDetector`. `DeviceHintsExtraction` optionally supplies a detected region into `DominantColorExtraction.extract(from:garmentRegion:)` — proven with the mock in `Tests/UnitTests/DeviceHintsExtractionTests.swift` / existing `DominantColorExtractionTests`. Wired into review analyze via `DeviceHintsExtraction`; **not** on the live ~10 Hz capture-quality path (Vision there is not safe for the capture budget); whole-frame quality stays. **Neither acceptance criterion is met.** The 20-sample manual blur set and the “usable foreground mask on a neutral background” judgement need a device and have not been run. |
| P3-SCAN-03 | Partial | Dominant colour: `Features/Scanner/Services/DominantColorExtraction.swift` — centre-region prior, optional `garmentRegion`, hex RGB for `GarmentDeviceHints.dominantColorsRGB`; solid-swatch suite in `Tests/UnitTests/DominantColorExtractionTests.swift` (automatable half of criterion 2). OCR: `LabelTextRecognizing` + `LiveVisionLabelTextRecognizer` (`VNRecognizeTextRequest`) + `MockLabelTextRecognizer`; lines only — no brand/size parsing. Composition: `DeviceHintsExtraction` fills `detectedText` from the recognizer (`Tests/UnitTests/DeviceHintsExtractionTests.swift`). Wired into `ScannerReviewViewModel` analyze via `DeviceHintsExtraction` + live Vision adapters; **not** on the ~10 Hz capture-quality path. **Neither acceptance criterion is fully met:** OCR “readable brand/size text from a clear label photo in manual testing” is unrun; dominant-colour criterion’s real-garment/human-judgement half is unrun (swatch suite alone is not that claim). |
| P3-SCAN-04 | Partial | `Features/Scanner/Services/CapturePreparation.swift`. `Data` in, `Data` out: resize to `docs/08` §2.3's 1024px longest-edge cap through ImageIO, re-encode at JPEG q0.72 (chosen from a measured sweep -- 48 KB at q0.50, 95 KB at q0.72, 145 KB at q0.90), metadata dropped by construction rather than by a strip pass. A sibling of `ImageDownsampling` and not an extension of it: that utility returns a `UIImage` with no re-encoding step for steps 6-7 to live in, and its `scale` multiplier would make a pixel cap unenforceable. **Criterion 1 is met and automated** -- `Tests/UnitTests/CapturePreparationTests.swift` builds a capture carrying EXIF, GPS, TIFF and an orientation tag, then asserts through `CGImageSourceCopyPropertiesAtIndex` that GPS, TIFF and orientation are gone and no identifying EXIF key survives. The honest claim is "nothing identifying the person, place, time or device", not "no metadata": ImageIO writes its own `{JFIF}` block and a three-key `{Exif}` block (`ColorSpace`, `PixelXDimension`, `PixelYDimension`), so the test asserts on keys rather than on a block's absence. Orientation is asserted **baked into the pixels** -- a stripped orientation tag on an unrotated image would ship every garment sideways. **Criterion 2 is half met:** 18.2x mean reduction measured on simulated 12 MP captures (1.4-1.75 MB to 76-99 KB); "without visible quality loss in the review screen" is a human judgement on a real device and visual quality on the review screen is still a human judgement (`P3-SCAN-09` now exists). `ScannerReviewViewModel` uploads the prepared draft from `CapturePreparation` (`P3-SCAN-05`). |
| P3-SCAN-05 | Done | `ClosetRepository.uploadCapturedImage` is a first-class protocol method (split from analyze so retries do not re-upload). `ScannerReviewViewModel` uploads the prepared draft, then resolves the path via `ClosetImageURLResolving` for the review hero (signed-URL criterion). Upload failure keeps the local draft and offers Retry. Path still lowercases the user id into `user-content`. **Abandoned captures are now removed (2026-08-06).** The upload happens before the user has decided anything, so Retake, Close and a swipe-dismiss each stranded an object in `user-content` that no `ClosetItemImage` referenced — invisible to him, invisible in the app, counted against his storage, one per retake. `ClosetRepository.deleteCapturedImage(atPath:)` plus `ScannerReviewViewModel.discardUnsavedUpload()`, called from every non-save exit in `ScannerDestinationView`. It is a no-op after `.saved` (that path *is* the saved garment's image), clears `storagePath` first so a double exit cannot delete twice, and swallows its own failure so a cleanup that cannot reach the network never traps the user on a screen he is leaving. `LiveClosetRepository` also compensates its own uploads: `analyzeItem` and `batchAnalyzeItems` delete what *they* uploaded if the call fails, and only that — a caller-supplied path belongs to the caller, and the batch stops compensating once the job is enqueued because the server owns those objects from then on. Tests: `ScannerReviewViewModelTests` covers upload fail→retry, analyze retry without a second upload, and five abandonment cases asserting on "nothing was left behind" rather than a delete call count. |
| P3-SCAN-06 | Done | `ScannerCaptureView` Photos import + shutter both run `CaptureQuality` → `CapturePreparation` → `DeviceHintsExtraction` (region/OCR/colour) before review via `PreparedCapture` / `CaptureDraft.deviceHints`. Live Vision adapters injected from `ScannerDestinationView`; mocks in `ScannerCaptureViewModelTests`. Review prefers draft hints over re-extract. Photos permission only on Import tap (spec §7). Simulator / denied camera: Import primary, shutter absent. **Both criteria met.** |
| P3-SCAN-07 | Partial | `supabase/functions/closet/` serves `POST /analyze-item` with `VisionAnalysisProvider` behind a protocol (`_shared/providers/visionAnalysis.ts`), defaulting to `MockVisionAnalysisProvider`; live OpenAI adapter exists in `openaiVisionAnalysis.ts` and is constructed only from `closet/index.ts` when `VISION_ANALYSIS_PROVIDER=openai` + `OPENAI_API_KEY` are set (optional `OPENAI_VISION_MODEL`). Operator how-to + §2.5 pilot checklist: `supabase/functions/closet/README.md` and `docs/08-provider-abstraction.md` §2.5 / §2.5.1. Wire DTO matches `ClosetItemAnalysisResult` (per-field confidence + `fields_below_confidence_threshold`). Idempotency: required `Idempotency-Key` header, durable store in `closet_analysis_idempotency` (`20260801120000_closet_analysis_jobs.sql`), iOS client reuses one key across retries (`AstraAPIClient` + `AstraEndpoint.requiresIdempotencyKey`). Deno tests in `closet/handler_test.ts` / `schema_test.ts`; Swift coverage in `EndpointDeploymentMappingTests` + `AstraAPIClientIdempotencyTests`. **Deployed 2026-08-06** to `anutsdzbxycaavmmkewo` (`verify_jwt: true`), with `20260801120000_closet_analysis_jobs.sql` applied at the same time — until then the function was fully written and fully tested but had never been deployed, so every scan 404'd *and* leaked its uploaded storage object. Smoke-verified live: no `Authorization` → 401 from the gateway, anon key → 401 in Astra's envelope, so the slug routes. **Also fixed in the same pass, because deploying the mock without it would have been worse than the 404:** `mapper.resolveCategory` hardcoded the category's confidence to `0.91` whenever the provider returned a valid category string, discarding the provider's own number. No production iOS code sets `approximate_category` (`DeviceHintsExtraction` computes colours and OCR text, not a category), so the mock defaults to `"top"` on *every* real request — which the wire DTO then presented at 0.91 with nothing marked uncertain. A man photographing shoes was told, confidently, that he owned a navy crewneck sweater. The mapper now passes `result.confidence` through, the mock reports `0.35` and adds `category`/`subcategory` to `fields_below_confidence_threshold` when it has defaulted rather than read, and the review screen marks both "Kyra isn't sure — check this". Two Deno tests pin both directions. **Not Done:** P95 <8s against a representative image set is unmeasured; docs/08 §2.5 menswear-subcategory pilot gate has **not** been run (env flip alone is not the gate); the deploy still uses the mock, so category is honest but uninformative until the pilot runs. |
| P3-SCAN-08 | Partial | `POST /closet/batch-analyze` enqueues a `closet_analysis_jobs` row and returns `{job_id,status}` (HTTP 202) without analysing synchronously; `GET /closet/batch-status/:id` advances **one item per poll** and returns per-item outcomes keyed by client `request_id`. A failure on one item does not fail the batch. iOS: `AstraEndpoint.batchAnalyzeClosetStatus`, `LiveClosetRepository.batchAnalyzeItems` uploads then polls to a `ClosetItemAnalysisBatch`. Cross-user isolation covered in `closet/handler_test.ts` (attacker-supplied `user_id` ignored; other user's job → 404; other user's storage path rejected). **Not Done:** not yet exercised end-to-end against a live Supabase project with five real uploads; mock provider only. |
| P3-SCAN-09 | Done | `ScannerReviewView` + `ScannerReviewViewModel`: every suggested field is editable; low-confidence fields use `isLowConfidence(_:)` with a text footnote (“Kyra isn’t sure — check this”) so meaning is not colour-alone (§19); Save writes the edited `ClosetItem` + `ClosetItemImage` through `createItem` and logs `closetItemAdded` / `scanCorrected`. Capture Continue pushes `.review(capturedImageID:)` via `CaptureDraftStore`. Cutout is the prepared JPEG until Vision/P3-SCAN-10 — not faked. Tests: `ScannerReviewViewModelTests`. |
| P3-SCAN-10 | Not started | No server-side background removal. |
| P3-SCAN-11 | Done | Post-save unlock report on `ScannerReviewView` (phase `.saved` + Done). Count from `ScanOutfitUnlockEstimator.newlyUnlockedCount` — complementary-category partners in the active closet (Phase-3-era heuristic; revisit against `P4-OUTFIT-09`). Zero is shown honestly, never a fabricated positive. Tests: `ScanOutfitUnlockEstimatorTests`. `HomeBriefData.purchaseOpportunity` remains nil (different surface). |
| P3-SCAN-12 | Not started | No receipt or mirror capture modes. |
| P3-CLOSET-01 | Done | `20260728100300_closet.sql` creates both tables with all spec columns + `embedding vector(1536)`; RLS applied and cross-user isolation asserted; live in production. |
| P3-CLOSET-02 | Done | Full CRUD via Postgrest; writes queue on failure and drain on the next success (`OfflineDrainWiringTests`). **Reads now cache through `ClosetItemCaching`:** `SwiftDataClosetItemCache` / `InMemoryClosetItemCache` backed by `PersistedClosetItem`; `LiveClosetRepository.fetchItems` write-through on success and serves active cached rows when the network fetch fails (authenticated offline cold start). Create/update (including offline-queued) upsert the cache; archive updates it. Tests: `Tests/UnitTests/LiveClosetRepositoryCacheTests.swift`. |
| P3-CLOSET-03 | Done | `Features/Closet/Views/ClosetView.swift` + `ClosetCategoryView.swift`, `ViewModels/ClosetViewModel.swift`, `Routing/ClosetDestinationView.swift`, `Components/` (category tile, grid tile, skeleton, empty state, error state, offline banner), wired into `MainTabView.closetTab` in place of `FeaturePlaceholderView`. **Both acceptance criteria met.** Criterion 1: a category tile pushes `ClosetRoute.category(_)` to a grid of that category alone. Criterion 2: the scan button calls `AppRouter.startScan()`, which presents the real `ScannerDestinationView` / `ScannerCaptureView` from `P3-SCAN-01` (no longer a `FeaturePlaceholderView`). The §6.14 header is complete: filter button (`P3-CLOSET-05`), metrics row and view-mode toggle (`P3-CLOSET-04`), laid out with `ViewThatFits`. "All items" still has no `ClosetRoute` case — the eighth tile scrolls to the whole-closet grid already on the page. Search narrows on name, brand and colour and composes with filters through `narrowed(_:)`. Tests: `Tests/UnitTests/ClosetViewModelTests.swift`. |
| P3-CLOSET-04 | Partial | `Features/Closet/Models/ClosetMetrics.swift`, `Models/ClosetViewMode.swift`, `Models/ClosetColorSpectrumOrder.swift`, `Components/ClosetMetricsRow.swift`, `Components/ClosetViewModeToggle.swift`, `Components/ClosetCompactList.swift`, `Components/ClosetColorSpectrum.swift`, `Core/Utilities/CurrencyFormatting.swift`, all reachable: the metrics row sits between the category tiles and the grid in `Views/ClosetView.swift`, the toggle is in that screen's header and in `Views/ClosetCategoryView.swift`'s navigation bar, and the selection persists in `@AppStorage("closet.viewMode")` under one key both screens read. **Both acceptance criteria are met.** Criterion 1: metrics are a pure function of the item array (`ClosetMetrics.compute(for:)`), exposed as a computed `ClosetViewModel.metrics` with nothing stored, so there is no cache a future mutation can forget to invalidate; adding, archiving and marking worn are each asserted, archiving in both shapes it can arrive in (the row leaves the array, or stays and gains an `archived_at`). Criterion 2: the colour spectrum's ordering is verified against fixture closets with known colours. **Partial, not Done, for exactly one reason: versatility is absent.** §6.14 lists six metrics and five ship. Versatility is defined in `docs/05-wardrobe-graph.md` §5.1 against outfit data and a compatibility score that are both Phase 4 work; its only producer, `LiveClosetRepository.fetchWardrobeScore()`, throws `AstraError.unimplemented` and no `wardrobe_scores` table exists. A client-side substitute (category/colour spread) was considered and deliberately rejected: it would render in the same type, in the same row, beside four measured figures, and would move when the real scorer lands for reasons no user could connect to anything he did. The gap is recorded in `ClosetMetrics.swift`'s header, and the row grows a sixth tile in Phase 4 without a shape change. One documented judgement: metrics are computed over the whole closet, not the search-narrowed view — a category tile's count is a door and must match what is behind it, but "estimated closet value" falling because three letters were typed into a search field reads as money going missing. Tests: `Tests/UnitTests/ClosetMetricsTests.swift` (28), `ClosetViewModeTests.swift` (7), `ClosetColorSpectrumOrderTests.swift` (32) — 67 tests, all passing. |
| P3-CLOSET-05 | Done | `Features/Closet/Models/ClosetFilters.swift` (all eight §6.14 facets: category, colour, season, brand, condition, fit, availability, and wear as the two axes the row can actually support — a count and a recency, never a rate, because there is no denominator on the device), `Models/ClosetFilterOptions.swift`, `Views/ClosetFilterPanelView.swift`, `Components/ClosetFilterButton.swift`; presented as a sheet from `Views/ClosetView.swift`, bound to `filters` on `ViewModels/ClosetViewModel.swift`. **Both acceptance criteria met and asserted.** Criterion 1: values OR within a facet and facets AND across them — AND within a facet would make every multi-select empty the screen on its second tap — verified against a fixture closet including the category+colour intersection the ticket names. Criterion 2: `apply(to:)` returns the identical array it was handed when nothing is active, so clearing cannot put the screen through a reload; nothing on this path fetches or can produce a `.loading` state. The control is not a dead door in any state: the button is drawn only where `!options.isEmpty || activeFacetCount > 0`, so it is absent where there is nothing to filter but never absent while a filter is on; chips are derived from the search-narrowed, filter-free scope, so every offered value matches something on screen and none shifts under the user's finger as he taps; and a filter set that excludes everything gets its own empty state and its own recovery rather than a blank grid (`ClosetViewModel.EmptyReason.noFilterMatches` and `Components/ClosetEmptyStateView.swift`, which withholds the manual-add affordance there for the same reason the search state does). Deliberately NOT offered on the category screen: that screen is the category facet already applied, and it holds its own view model, so a filter set there would be a second invisible one behind the same glyph — argued in `Views/ClosetCategoryView.swift`'s header. Tests: `Tests/UnitTests/ClosetFiltersTests.swift` (40), all passing. |
| P3-CLOSET-06 | Partial | `Features/Closet/Views/ClosetItemDetailView.swift` + `ViewModels/ClosetItemDetailViewModel.swift`, reached by `ClosetRoute.itemDetail(itemID:)`. Criterion 1 met for every §6.15 field the model can answer, and editable fields save through `P3-CLOSET-08`'s form, presented here as a sheet over the loaded item. Criterion 2 met in its stated initial form: wear count and last-worn render real `closet_items` values, which are zero and empty until Phase 4 writes them. **Two §6.15 fields are absent because the data does not exist, not because they were skipped:** *care instructions* has no `closet_items` column and no `ClosetItem` property (adding one without a migration fails `check_column_drift.py`), and *outfit count* needs `outfit_items` (`P4-OUTFIT-*`). Neither is stubbed. §6.15's Insights block (best pairings, outfit gallery, redundancy score, replacement suggestion) is `P3-CLOSET-07` and depends on the Phase 4 compatibility engine; the screen leaves room below the fields rather than faking it. Absent optional fields are omitted rather than rendered as dashes, except the four where absence is itself the answer (wear count, last worn, cost per wear, laundry state), which always render with copy saying what the blank means. Tests: `Tests/UnitTests/ClosetItemDetailViewModelTests.swift`. |
| P3-CLOSET-07 | Not started | No insights section; `WardrobeScore.redundancyControl` is never populated. |
| P3-CLOSET-08 | Done | `Features/Closet/ViewModels/ClosetItemFormViewModel.swift`, `Views/ClosetItemFormView.swift`, `Components/ClosetColorPicker.swift`, `Components/ClosetAddItemSheet.swift`. **Both acceptance criteria met, and the path is reachable.** A garment goes in end to end with no camera anywhere in it — nothing in the feature imports AVFoundation, offers a "scan instead" affordance, or reaches `analyzeItem`. The door is in two places on purpose: the Closet header (`closet.header.addManually`) and the two "you own nothing here" empty states (`closet.empty.addManually`). Header as well as empty state, because the empty state disappears once the closet holds one item, so an empty-state-only entry point would let a man add his first garment and never a second. Name and category block submission — name trimmed, so three spaces is not a name — and submit is disabled with the reason rendered beneath it rather than silently greyed; every other field is optional and an untouched price stores `nil`, not `0`. One screen serves both add and edit: `Mode` changes only the copy, where the user id comes from, and which repository verb runs, so it is also `P3-CLOSET-06`'s edit surface. Editing rebuilds the row by mutating a copy of the original, so `id`, `user_id`, `created_at`, `wear_count`, `last_worn_at`, `archived_at`, `embedding` and the derived scores survive by construction rather than by a checklist. `SessionStore.currentUserID()` was added alongside the existing `currentGuestUserID()` so the form resolves an owner for a guest and a real account alike. Guest behaviour is the real one: `GuestClosetError.capReached` surfaces its own sentence as a non-retryable notice and, unlike the onboarding step, does not close the form or discard the draft. Supersedes the throwaway add form in `Features/Slice/`. 24 unit tests in `Tests/UnitTests/ClosetItemFormViewModelTests.swift`. |
| P3-CLOSET-09 | Done | `Features/Closet/Components/ClosetItemActionRow.swift` driven by `ClosetItemDetailViewModel`; the repository half was already true and is now reachable from the UI. **Both criteria met and asserted:** mark worn increments `wear_count` by 1 and sets `last_worn_at` to now; archive sets `archived_at`, leaves the row in place, and `fetchItems()` already filters it out of default views. All three writes apply optimistically and roll back on failure, so the screen never shows a wear count, laundry state or archive the database does not have — pinned by three tests named for exactly that. Archive fires `AstraHaptics.warning()` per spec §3 and does not dismiss on failure, because dismissing would tell a man his jacket was gone while it is still there. Edit opens `P3-CLOSET-08`'s form. §6.15's "Sell/donate" is explicitly a later action and is not stubbed. Tests: `Tests/UnitTests/ClosetItemDetailViewModelTests.swift`. |
| P3-CLOSET-10 | Done | `CostPerWearCalculator` + tests: $100/4→$25, 0 wears→nil, missing price→nil, rounding, average, projection. |
| P3-CLOSET-11 | Done | Guest 10-item cap remains in `GuestClosetRepository` (`GuestClosetRepositoryTests`). Free-tier 30-item cap is `FreeTierCappedClosetRepository` + `FreeTierLimits` / `FreeTierClosetError` (spec §16), wrapping the live/mock path in `AppContainer` and consulting `Subscription.isEntitledToPremium` (fail closed to free limits on lookup error). Premium fixture is never blocked; archiving frees a slot. Form surfaces `freeTierCapReached` as a non-retryable notice (same pattern as guest) — **no paywall UI invented** (purchase chrome is `P7-SUB-05`). Tests: `Tests/UnitTests/FreeTierClosetCapTests.swift`, plus form coverage in `ClosetItemFormViewModelTests`. |
| P3-INFRA-01 | Done | ADR 0005 wired into drain: `OfflineConflictResolution.resolve` (LWW by `updated_at` for `.update`; `.delete`/archive surfaces `needsResolution` when remote is newer — never auto-applied). `ClosetWriting.fetch(id:)` feeds the compare; discards/conflicts record via `OfflineConflictRecording` + OSLog. Tests: `Tests/UnitTests/OfflineConflictResolutionTests.swift`. |
| P3-INFRA-02 | Done | `PendingScan` + `PendingScanQueue` (`InMemoryPendingScanQueue` / `SwiftDataPendingScanQueue`). `ScannerReviewViewModel` enqueues when offline or upload/analyze fails as network; phase `.pendingAnalysis` with honest queued copy. `NetworkReachabilityMonitoring.connectivityUpdates()` drives auto upload+analyze on reconnect without re-capture. Wired in `AppContainer` + `ScannerDestinationView`. Tests: offline enqueue + reconnect auto-analyze in `ScannerReviewViewModelTests`. |
| P3-TEST-01 | Partial | Cost-per-wear and offline replay-after-failure tests exist and pass. Redundancy-score test cannot exist — no redundancy logic does. |
| P3-TEST-02 | Done | `AstraStyleUITests.testAddGarment()` drives manual entry under `-astra-mock-backend` + `-astra-skip-onboarding`: Closet tab → `closet.header.addManually` → name + Tops category → submit → form dismisses → Tops category → asserts the new name appears and item detail shows wear count 0. `MainTabView` / `ClosetDestinationView` pass `sessionStore.currentUserID` into `ClosetViewModel` so the add form can resolve an owner (without that wiring every submit failed as `.auth` and the sheet never closed). `AstraStyleApp` mock-backend launch respects `AppRouter.postAuthenticationRoute` so skip-onboarding reaches `.main`. |

---

# PHASE 4 — OUTFIT INTELLIGENCE

**7 Done · 10 Partial · 9 Not started.** The most misread phase. The Home tab is a near-complete
Phase 4 vertical build (19 files) sitting in `Features/Home/`, and the deployed outfit generator is
deliberately a placeholder scorer, not the real one.

| Ticket | Status | Evidence |
|---|---|---|
| P4-OUTFIT-01 | Done | `20260728100400_outfits.sql` creates `outfits`/`outfit_items`/`outfit_wears` with embeddings; RLS + cross-user isolation tested; live in production. |
| P4-OUTFIT-02 | Done | `supabase/functions/_shared/scoring/` — 12 files, **129 unit tests**, pure functions with no database, provider or clock, which is what `docs/05` was written for. `compatibility.ts`'s `scoreOutfit` combines all eight components into the §2 `round(100 × Σ wᵢ·sᵢ)` and returns **every component and every degradation alongside the total**, not a bare number — the outfit card needs the breakdown, tuning needs the components, and Kyra must never say "these colours work together" off a 0.6 prior for a garment nobody analysed. Tests pin determinism over 25 runs, a coherent outfit beating an incoherent one by 15+ points, and a fully-contextless score landing between 60 and 95 — the ceiling is as load-bearing as the floor, since a fully-guessed 98 would be the app claiming confidence it has not got. |
| P4-OUTFIT-03 | Partial | `supabase/functions/_shared/scoring/` — 12 files, **129 unit tests**, pure functions with no database, provider or clock, which is what `docs/05` was written for. `ComponentWeights` is a parameter with `DEFAULT_WEIGHTS` matching spec §10 exactly, and a table that does not sum to 1 is renormalised rather than allowed to cap the product — a human editing eight numbers will eventually make them sum to 0.97, and that should shift emphasis, not silently cap every outfit at 97. A test proves reweighting toward colour actually punishes a colour clash. **Still Partial: there is no `compatibility_weights` table and no endpoint to edit one.** The seam is done; the server-side storage §10 asks for is not. |
| P4-OUTFIT-04 | Done | `supabase/functions/_shared/scoring/` — 12 files, **129 unit tests**, pure functions with no database, provider or clock, which is what `docs/05` was written for. Colour (0.25) is the full §1 pipeline — sRGB → linear → XYZ(D65) → LAB → LCh, CIE76 ΔE, §1.4's four harmony zones, §1.5's pattern interaction, §2.1 aggregation. Formality (0.20) is §2.3's super-linear `1-(Δf/40)^1.5` plus §3.1's outfit register. **§1.3's neutral band table did not work and is corrected** — it was written in HSL hue and applied in CIE hue, so the navy band (`h° 240–270`) matched none of five real navies (274–289) and olive-drab's chroma ceiling of 22 excluded every real olive-drab (18–31). Both bands — the only two the table exists for — classified their own subject as chromatic. Replaced with measured envelopes, pinned from both sides (13 must-be-neutral, 9 near-miss must-be-chromatic), and recorded in `docs/05` §0. **This reverses the doc's own worked example**: the olive polo is a neutral and the canonical outfit scores 0.97 on colour, not 0.91. |
| P4-OUTFIT-05 | Done | `supabase/functions/_shared/scoring/` — 12 files, **129 unit tests**, pure functions with no database, provider or clock, which is what `docs/05` was written for. Silhouette (0.15) implements §4 in full: the §4.1 fit-pairing table, §4.2's **deliberately asymmetric** directional rule (a looser top over a tighter bottom is a volume-balance play; the same volumes reversed read as clothes that do not fit — with `d = −1` carved out because regular-over-relaxed is the most ordinary casual combination there is), and §4.3's body dampeners. Season/weather (0.10) and user preference (0.10) are in `subscores/context.ts`. **§4.3 modifiers can only dampen, never lift, and a test asserts it across the whole 5×5 fit matrix** — an engine that rewarded a garment for a man's chest measurement would be scoring the man. Two of §4.3's four rules are computable and two are not (no column stores garment length or break); the two that cannot run report themselves rather than being silently skipped. `FrameHarmonyScorer` remains the separate silhouette-on-wearer work. |
| P4-OUTFIT-06 | Done | `supabase/functions/_shared/scoring/` — 12 files, **129 unit tests**, pure functions with no database, provider or clock, which is what `docs/05` was written for. Co-wear (0.10) is §2.7's Bayesian-smoothed positive rate with the doc's optimistic `α=2, β=1` prior, so an untested pair opens at 2/3 rather than 1/2 — absence of negative history is not evidence of a bad pairing, and a raw rate would structurally bury every new garment. Falls back from the specific pair to the role pair so a garment bought yesterday inherits how this user's tops and bottoms generally go, and marks itself degraded when it does. Occasion (0.05) returns §2.8's unconstrained-request default and names the missing column — `closet_items` has no `occasion_tags`; only `outfits` does. Availability (0.05) is the soft half of §2.9; the hard half is `wearableItems`, **widened beyond the doc to all seven `availability_state` values** — a jacket at the tailor, in a suitcase, lent out or lost is as impossible to wear as a dirty shirt. |
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
| P4-HOME-02 | Done | `supabase/functions/daily-brief/` (`index.ts`/`handler.ts`/`schema.ts` + 11 Deno tests), **deployed 2026-08-06** to `anutsdzbxycaavmmkewo` with `verify_jwt: true`. **Both acceptance criteria verified against production** with a real JWT minted for a throwaway user with a six-garment closet (deleted afterwards; the cascade was confirmed empty): a populated closet returned a `primary_outfit_id` **and** one alternative, and a second identical call returned the same brief id with no second set of outfits written. `regenerate: true` rebuilt in place — same row, new primary — and `2026-02-31` returned 400 rather than silently landing in a different day's row. Outfits are persisted as real `outfits` + `outfit_items` rows **before** the brief references them, because `daily_briefs.primary_outfit_id` is a foreign key and the ids `POST /outfits/generate` returns are client-minted and never stored; roles and `sort_order` were checked in the live rows. Idempotency is enforced twice — a read in `handler.ts` and an upsert on the table's own `(user_id, brief_date)` constraint — because the read alone is a race. The scorer moved to `_shared/scoring/leastRecentlyWorn.ts` on the terms its own header set out (a second caller arrived); it is still the placeholder, not `docs/05` §2's real compatibility scorer. **Two §14 inputs are deliberately absent rather than invented:** `weather_snapshot` stays null because there is no server-side weather provider (`P4-HOME-05`), and `kyra_message` stays null because the only sentence available would be `LeastRecentlyWornScorer`'s single hardcoded `reason`, identical every day, dressed as a judgement. **Known gap, recorded rather than guessed at:** a regenerate leaves the previous brief's generated outfits active and unreferenced. Nothing surfaces them today (`P4-OUTFIT-11` is Not started), and the right policy — archive the unworn ones, keep the worn ones for `outfit_wears` history — is easier to settle once there is a screen to look at. |
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
| P5-KYRA-02 | Not started | No `supabase/functions/kyra/`; `EndpointDeploymentMappingTests` pins `requiredNow = ["outfits", "profile", "style-dna"]` (Kyra is not among them). |
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
| CI runs on every PR and fails on a warning or lint violation | **Partial** | PRs #3/#4 ran `ios.yml` green (lint + warning gate). Negative case (PR fails on a deliberate warning/lint) still unproven; convention is now direct-to-`main`. |
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

Phases 4–7 exit criteria are not yet assessed in full. Phase 3 (Closet) is underway — overview,
metrics, filters, detail, and manual form are usable; Scanner UI and the `closet` Edge Function
are the remaining block. Assessing Phases 4–7 now would still produce a wall of "No" with little
information in it.

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

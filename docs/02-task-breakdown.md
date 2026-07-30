# ASTRA STYLE — ENGINEERING TASK BREAKDOWN

178 tickets across Phases 1–7, grouped by phase then area. IDs follow `P{phase}-{AREA}-{nn}`. Spec references are to `00-master-spec.md`. Size: S = ≤1 day, M = 2–4 days, L = ~1 week, XL = 1.5–2+ weeks.

---

# PHASE 1 — FOUNDATION

## INFRA

#### `P1-INFRA-01` — Initialize Xcode project with feature-first module structure
Scope: Create the Xcode project targeting iOS 18+, Swift 6, SwiftUI, and lay down the folder structure from spec §8 (`App/`, `Core/`, `Features/`, `Domain/`, `Resources/`, `Tests/`) with placeholder files so every subsequent ticket has a known location to land in.
**Acceptance criteria**
- Project builds and runs an empty app on simulator.
- Folder structure matches spec §8 exactly, including per-feature `Views/ViewModels/Components/Models/Services/Routing/Tests` subfolders for all 11 listed features.
- No feature code exists yet beyond stub files.
**Dependencies:** none
**Size:** S

#### `P1-INFRA-02` — Configure .xcconfig build configurations and CI secret injection
Scope: Create Debug/Staging/Release `.xcconfig` files per spec §25, exposing only `SUPABASE_URL` and `SUPABASE_ANON_KEY` to the app target, with CI-injected values for staging/release builds.
**Acceptance criteria**
- No secret value is committed to the repo; xcconfig files reference environment variables or a gitignored local file for local dev.
- Grepping the built binary for `SERVICE_ROLE` or any provider API key name returns nothing.
**Dependencies:** `P1-INFRA-01`
**Size:** S

#### `P1-INFRA-03` — Set up CI pipeline (build, lint, unit tests)
Scope: Configure CI (Xcode Cloud or GitHub Actions) to build the project, run SwiftLint/SwiftFormat, and run the unit test target on every PR, failing on any warning per spec §31.
**Acceptance criteria**
- A PR with a compiler warning fails CI.
- A PR with a SwiftLint violation fails CI.
- CI run time is reported and visible on the PR.
**Dependencies:** `P1-INFRA-01`, `P1-INFRA-02`
**Size:** M

#### `P1-INFRA-04` — Provision Supabase project and CLI migration workflow
Scope: Create dev/staging/prod Supabase projects, set up the Supabase CLI migration workflow (`supabase migration new` / `supabase db push`), and document the workflow for all future schema tickets.
**Acceptance criteria**
- `supabase db push` applies cleanly to a fresh dev project with zero errors.
- Migration files are checked into the repo under a `supabase/migrations/` directory.
**Dependencies:** none
**Size:** M

#### `P1-INFRA-05` — Migration: profiles, style_profiles, body_profiles, lifestyle_profiles + RLS
Scope: Write the migration creating `profiles`, `style_profiles`, `body_profiles`, `lifestyle_profiles` per the exact column lists in spec §9, with `user_id = auth.uid()` RLS policies on all four tables per spec §15.
**Acceptance criteria**
- Migration applies cleanly on a fresh database.
- Querying any of the four tables with a JWT for user A returns zero rows for data owned by user B (verified via an automated RLS test, not manual inspection).
- All four tables have `created_at`/`updated_at` columns.
**Dependencies:** `P1-INFRA-04`
**Size:** M

#### `P1-INFRA-06` — Configure private Storage buckets with signed URL policy
Scope: Create Supabase Storage buckets for `users/{user_id}/closet/`, `users/{user_id}/references/`, `users/{user_id}/studio/` per spec §15, set buckets private, and configure a signed-URL-generation policy scoped to the owning user.
**Acceptance criteria**
- An unsigned direct request to any object URL returns 403/404.
- A signed URL generated for user A's object cannot be reused to access user B's path (policy denies path traversal).
**Dependencies:** `P1-INFRA-04`
**Size:** S

## CORE

#### `P1-CORE-01` — Define AppContainer root DI container and environment injection
Scope: Implement `AppContainer` as a flat, protocol-based dependency container per spec §8 (avoid a third-party DI framework), injected via `.environment(appContainer)` from `AstraStyleApp` per spec §27, and include a minimal `AnalyticsLogger` protocol for event instrumentation used from Phase 2 onward.
**Acceptance criteria**
- `AppContainer.live()` and `AppContainer.preview()`/mock variants both compile and construct.
- A sample feature view model can resolve a repository from the injected container.
**Dependencies:** `P1-INFRA-01`
**Size:** M

#### `P1-CORE-02` — Define core repository protocols
Scope: Define `AuthRepository`, `ClosetRepository`, `OutfitRepository`, `KyraRepository`, `StudioRepository`, `ShoppingRepository`, `SubscriptionRepository` per spec §8, each with method signatures covering the CRUD/action surface needed by their respective feature phases, plus mock implementations returning fixture data.
**Acceptance criteria**
- Every protocol compiles with a mock conformance usable in SwiftUI previews.
- No protocol method leaks a Supabase- or provider-specific type into its signature (domain types only).
**Dependencies:** `P1-CORE-01`
**Size:** M

#### `P1-CORE-03` — Define WeatherService and CalendarService protocols with mocks
Scope: Define `WeatherService` and `CalendarService` protocols per spec §8 with mock implementations returning fixture weather/schedule data, to unblock Home and Kyra tool development before live integrations exist.
**Acceptance criteria**
- Mock `WeatherService` returns a deterministic forecast usable in previews and tests.
- Mock `CalendarService` returns a deterministic, non-empty fixture set by default (so previews and early tests have something to render without extra setup) and accepts a configurable fixture set for tests. Amended 2026-07-30: this originally required zero events by default; the shipped two-fixture default is more useful and was kept instead — see `docs/03-progress.md`'s "Acceptance criteria that are wrong, rather than unmet."
**Dependencies:** `P1-CORE-01`
**Size:** S

#### `P1-CORE-04` — Build APIClient wrapping Edge Function calls
Scope: Implement `Core/Networking/APIClient` that attaches the Supabase session JWT to every request, calls Edge Functions by path (e.g. `POST /outfits/generate`), retries idempotent GETs on transient failure, and maps HTTP/Edge Function errors to a typed `APIError`.
**Acceptance criteria**
- A request made without a valid session throws a typed unauthenticated error before hitting the network.
- A 5xx response triggers retries with backoff per `AstraRetryPolicy` before surfacing an error. Amended 2026-07-30: this originally said "exactly one retry"; the shipped default (`AstraRetryPolicy.default`, `maxAttempts: 3`) is the better policy for a mobile client on unreliable networks, so the criterion now matches it instead of the other way around — see `docs/03-progress.md`'s "Acceptance criteria that are wrong, rather than unmet."
- Retry count and backoff timing are covered by an automated test. **Still unmet** — no test in the repo currently asserts either; this gap is real and stays open rather than being papered over by the amendment above.
- No view or view model performs a network call directly — only repositories call `APIClient`.
**Dependencies:** `P1-INFRA-02`, `P1-CORE-01`
**Size:** M

#### `P1-CORE-05` — Build SwiftData persistence container and migration strategy
Scope: Set up the `Core/Persistence` SwiftData `ModelContainer` for offline-first entities, define the local schema versioning approach (lightweight migration plan), and document how local models map to Supabase-synced domain models.
**Acceptance criteria**
- App launches and creates a local SwiftData store on first run.
- A schema version bump migrates existing local data without data loss (tested with a fixture pre-migration store).
**Dependencies:** `P1-CORE-01`
**Size:** M

#### `P1-CORE-06` — Implement OfflineOperationQueue primitive
Scope: Build a generic `OfflineOperationQueue` that persists queued local edits (create/update/delete operations tagged with entity type and payload) to SwiftData and replays them against the relevant repository when connectivity returns, forming the basis for closet/outfit offline sync in later phases.
**Acceptance criteria**
- An operation queued while offline persists across app relaunch.
- Reconnecting triggers replay in FIFO order and clears successfully-replayed operations from the queue.
- A replay failure leaves the operation in the queue with a retry count rather than silently dropping it.
**Dependencies:** `P1-CORE-05`
**Size:** M

#### `P1-CORE-07` — Implement root routing, tab nav shell, and modal presentation coordinator
Scope: Implement `AppRouteState` (`launching`/`signedOut`/`onboarding`/`main`) per spec §27, a `RootView` that switches on it, a `NavigationStack`-per-tab shell for the 5 tabs in spec §4 with independently preserved paths, and a modal coordinator presenting camera/paywall/auth/onboarding/full-screen-generation as full-screen or sheet modals per spec §4.
**Acceptance criteria**
- Switching tabs preserves each tab's navigation stack position.
- Launching in each of the 4 `AppRouteState` cases routes to the correct root screen.
- A modal presented via the coordinator (e.g. paywall) can be dismissed and does not pollute the underlying tab's nav stack.
**Dependencies:** `P1-CORE-01`
**Size:** L

## DS

#### `P1-DS-01` — Define color token catalog (dark/light) as Asset Catalog + AstraColor enum
Scope: Create Asset Catalog color sets for every token in spec §3 (both dark and light mode hex values) and a Swift `AstraColor` enum/namespace exposing them as `Color` values, defaulting to dark mode per spec §3.
**Acceptance criteria**
- Every token listed in spec §3 (backgroundPrimary through destructive) exists in both color schemes and matches the specified hex values exactly. Note: spec §3 was corrected 2026-07-30 to the shipped hex values for `textMuted` (both schemes) and light-mode `accentChampagne` — the original spec values failed WCAG AA against every surface they appear on; see `docs/07-design-system.md` §3 for the contrast analysis and `docs/03-progress.md`'s "Acceptance criteria that are wrong, rather than unmet."
- Toggling system appearance switches all token values without a code change in consuming views.
- **Genuinely unmet:** no Asset Catalog (`.xcassets`) exists anywhere in the repo — tokens are implemented entirely in `AstraColor.swift` via a `UIColor` dynamic provider, with no Asset Catalog color sets backing them. This also means there is no app icon.
**Dependencies:** `P1-INFRA-01`
**Size:** S

#### `P1-DS-02` — Define typography scale as Font/ViewModifier extensions
Scope: Implement the 9 text styles from spec §3 (`displayXL` through `micro`) as `Font` definitions and `View` modifiers, using New York/bundled serif for editorial styles and SF Pro for UI text, supporting Dynamic Type scaling.
**Acceptance criteria**
- Each of the 9 styles renders at the specified point size and weight at the default Dynamic Type size.
- All styles scale up under larger Dynamic Type accessibility sizes without manual per-view overrides.
**Dependencies:** `P1-INFRA-01`
**Size:** S

#### `P1-DS-03` — Define spacing/layout constants
Scope: Implement the 4pt base spacing unit, 20pt page padding, 18pt card radius, 14pt button radius, capsule chip radius, and 44×44pt minimum tap target as named constants in `Core/DesignSystem`, per spec §3.
**Acceptance criteria**
- Constants are referenced by name (not magic numbers) in the base component library ticket.
- A lint rule or code review checklist item flags raw point values in feature code that duplicate these constants.
**Dependencies:** `P1-DS-01`
**Size:** S

#### `P1-DS-04` — Build base component library
Scope: Implement `AstraButton`, `AstraCard`, `AstraChip`, `AstraTextField` (and any other primitive shared across ≥3 features) using the tokens from `P1-DS-01`–`03`, with soft shadows in light mode and 1px borders in dark mode per spec §3.
**Acceptance criteria**
- Each component has a SwiftUI preview showing dark and light mode side by side.
- Every interactive component meets the 44×44pt minimum tap target.
- `AstraButton` supports at minimum primary/secondary/destructive variants matching the color tokens (accentChampagne, divider, destructive).
**Dependencies:** `P1-DS-01`, `P1-DS-02`, `P1-DS-03`
**Size:** M

#### `P1-DS-05` — Build marble texture component and splash screen
Scope: Implement a reusable `MarbleSurface` component restricted to the approved surfaces in spec §3 (splash, app icon, paywall hero, select premium cards, Kyra transitions), and the Splash screen (§6.1): full-screen marble, gold Astra monogram, fading wordmark, optional tagline, routing within 1.4s.
**Acceptance criteria**
- Splash routes to the correct `AppRouteState` destination within 1.4s on a supported device (measured, not estimated).
- `MarbleSurface` is not used behind dense text anywhere in the codebase (spec §3 explicit rule) — verified by code review of its call sites.
**Dependencies:** `P1-DS-01`, `P1-CORE-07`
**Size:** M

#### `P1-DS-06` — Build motion tokens and haptics helper
Scope: Implement the 220ms ease-in-out standard transition, matched-geometry hero card helper, spring-settling horizontal paging helper, breathing Kyra-orb animation primitive, and a `HapticsService` (selection on outfit swap, success on saved scan, warning on destructive action) per spec §3, all respecting the system Reduce Motion setting.
**Acceptance criteria**
- With Reduce Motion enabled, matched-geometry and breathing animations are replaced with a cross-fade or static state.
- Each haptics call site maps to the correct feedback type per spec §3's mapping.
**Dependencies:** `P1-DS-01`
**Size:** S

## AUTH

#### `P1-AUTH-01` — Implement Sign in with Apple via AuthenticationServices + Supabase Auth exchange
Scope: Implement the `ASAuthorizationController` Sign in with Apple flow and exchange the resulting identity token with Supabase Auth to create/retrieve a session, populating `AuthRepository`'s live implementation.
**Acceptance criteria**
- A new Apple ID creates a Supabase auth user and a corresponding empty `profiles` row.
- A returning Apple ID resolves to the existing user rather than creating a duplicate.
- Denying the Apple ID prompt returns cleanly to Welcome without a crash.
**Dependencies:** `P1-INFRA-05`, `P1-CORE-02`, `P1-CORE-04`
**Size:** M

#### `P1-AUTH-02` — Implement email magic link / OTP authentication flow
Scope: Implement email-based sign-in via Supabase Auth's magic link or OTP flow, including the entry UI, code/link handling deep link, and session establishment.
**Acceptance criteria**
- Requesting a code/link sends via Supabase Auth and the app correctly handles the deep link or code entry to establish a session.
- An expired or invalid code shows a specific error, not a generic failure.
**Dependencies:** `P1-AUTH-01`
**Size:** M

#### `P1-AUTH-03` — Implement session restoration on cold launch
Scope: On app launch, check for a persisted Supabase session, refresh it if near expiry, and route to the correct `AppRouteState` without requiring re-authentication, per spec §6.1 splash routing rules.
**Acceptance criteria**
- Force-quitting and relaunching the app with a valid session lands on Home (or resumed onboarding) without a sign-in prompt.
- An expired/unrefreshable session correctly routes to Welcome rather than crashing or hanging on Splash.
**Dependencies:** `P1-AUTH-01`, `P1-CORE-07`
**Size:** S

#### `P1-AUTH-04` — Implement guest-mode session with local entity capping
Scope: Implement a local-only "guest" session state (no Supabase auth user) per spec §6.2, and enforce guest restrictions at the repository layer: local closet capped at 10 items, no cloud sync, one Style Studio sample, no shopping history.
**Acceptance criteria**
- Adding an 11th closet item in guest mode is blocked with an in-context upgrade prompt, not a silent failure.
- No network call to Supabase is made for guest-mode closet writes.
**Dependencies:** `P1-CORE-02`, `P1-CORE-05`
**Size:** M

#### `P1-AUTH-05` — Implement guest-to-account migration on sign-up
Scope: When a guest converts to a real account (Apple or email), migrate locally-stored guest closet items into the newly created Supabase-backed account rather than discarding them.
**Acceptance criteria**
- A guest with 3 local items who signs up ends up with those 3 items present in their `closet_items` rows after migration.
- Migration failure (e.g. network loss mid-migration) leaves the local queue intact for retry rather than losing data.
**Dependencies:** `P1-AUTH-04`, `P1-AUTH-01`, `P1-CORE-06`
**Size:** M

#### `P1-AUTH-06` — Build Welcome/authentication screen
Scope: Implement the Welcome screen per spec §6.2: Continue with Apple, Continue with email, Explore demo (guest mode entry), Terms and Privacy links.
**Acceptance criteria**
- All four actions are wired to real flows (no dead buttons per spec §22 acceptance bar).
- Terms/Privacy links open real (even if placeholder-content-pending) documents, not a 404.
**Dependencies:** `P1-AUTH-01`, `P1-AUTH-02`, `P1-AUTH-04`, `P1-DS-04`
**Size:** M

---

# PHASE 2 — IDENTITY

## ONBOARD

#### `P2-ONBOARD-01` — Build Kyra introduction screen
Scope: Implement the Kyra intro screen (§6.3) with the specified copy and an elegant abstract avatar (not photorealistic, per spec's explicit constraint), as the first onboarding step after Welcome.
**Acceptance criteria**
- Screen displays the exact copy from spec §6.3.
- Avatar asset is abstract, not a photorealistic human render.
**Dependencies:** `P1-AUTH-06`, `P1-DS-04`
**Size:** S

#### `P2-ONBOARD-02` — Build Style goals multi-select screen
Scope: Implement the 8-option multi-select screen from spec §6.4 (dress better day to day / build a complete wardrobe / etc.), persisting selections locally until submitted with the full onboarding payload.
**Acceptance criteria**
- User can select multiple options; at least one selection is required to proceed.
- Selections persist if the user navigates back to a previous onboarding step and returns.
**Dependencies:** `P2-ONBOARD-01`
**Size:** S

#### `P2-ONBOARD-03` — Build Style identity card selection
Scope: Implement the visual card grid for the 10 style identities in spec §6.5, requiring the user to choose exactly 3 and rank one as primary.
**Acceptance criteria**
- User cannot proceed with fewer than 3 selections or without a designated primary.
- Selected identities and the primary ranking are included in the onboarding payload sent to `complete-onboarding`.
**Dependencies:** `P2-ONBOARD-02`
**Size:** M

#### `P2-ONBOARD-04` — Build Measurements and fit form
Scope: Implement the measurements form from spec §6.6 (height, weight optional, chest, waist, inseam, neck, shoe size, shirt size, trouser size, preferred fit, fit issues) with an "I don't know" option on every field per spec's explicit allowance.
**Acceptance criteria**
- Every field except height can be left as "I don't know" / blank without a validation error.
- Submitted values map correctly to `body_profiles` columns.
**Dependencies:** `P2-ONBOARD-03`, `P2-CORE-01`
**Size:** M

#### `P2-ONBOARD-05` — Build Appearance profile screen
Scope: Implement the optional appearance profile screen from spec §6.7 (skin undertone, hair color, eye color, facial hair, glasses, tattoo visibility, reference selfies), with an explanation of why each field is used and a clear skip affordance per field and for the whole screen.
**Acceptance criteria**
- Every field is skippable individually and the screen as a whole is skippable.
- Rationale copy is present for each field, not a bare form.
**Dependencies:** `P2-ONBOARD-04`
**Size:** M

#### `P2-ONBOARD-06` — Build Lifestyle profile screen
Scope: Implement the lifestyle screen from spec §6.8 (occupation category, dress code, typical week, common occasions, laundry cadence, travel frequency, religious/service attire needs, preferred stores/brands, budget, sustainability preference). Climate/location permission — §6.8's fifth bullet — is deliberately NOT requested on this screen; see the amendment note below.
Amended 2026-07-30: the original scope requested location permission in-context on this screen per spec §7. It was moved to first use of §6.11 (the Home weather header) instead, because a location prompt mid-onboarding, before the Daily Brief that uses weather exists, has no visible payoff and reliably gets denied permanently — see `OnboardingLifestyleView`'s header comment for the full reasoning. That left the requirement with no owner; it now belongs to `P4-HOME-05`. See `docs/03-progress.md`'s "Acceptance criteria that are wrong, rather than unmet."
**Acceptance criteria**
- Submitted values map correctly to `lifestyle_profiles` columns.
**Dependencies:** `P2-ONBOARD-05`
**Size:** M

#### `P2-ONBOARD-07` — Build style preference paired-image quiz engine and inference
Scope: Implement the paired-image comparison quiz from spec §6.9 (12–20 comparisons) and the inference logic that converts choices into a preference vector (color tolerance, formality, silhouette, texture, logo tolerance, trend tolerance, accessory preference, contrast preference) stored on `style_profiles`.
**Acceptance criteria**
- Quiz presents between 12 and 20 pairs and does not allow proceeding without a choice on each.
- Completing the quiz produces a preference vector with a value for all 8 dimensions listed in spec §6.9.
- Quiz image pairs are content-managed (loaded from a config/catalog), not hardcoded per-build.
**Dependencies:** `P2-ONBOARD-06`
**Size:** L

#### `P2-ONBOARD-08` — Build optional selfie/body reference capture screen
Scope: Implement the optional reference photo capture step from spec §5.1/§6.7 with explicit consent copy explaining use and storage, uploading to the `users/{user_id}/references/` bucket.
**Acceptance criteria**
- Skipping this step does not block onboarding completion.
- Consent copy is shown before the camera/photo picker opens, and capture does not proceed without acknowledgment.
**Dependencies:** `P1-INFRA-06`, `P2-ONBOARD-05`
**Size:** M

#### `P2-ONBOARD-09` — Build "add first closet items or skip" step
Scope: Implement the onboarding step from spec §5.1 offering the user a shortcut into manual item entry (built in Phase 3, stubbed here) or a skip to proceed straight to Style DNA generation.
**Acceptance criteria**
- Skip proceeds directly to Style DNA generation.
- If Phase 3's manual add-garment form is not yet available, this step degrades to skip-only without blocking the onboarding flow.
**Dependencies:** `P2-ONBOARD-08`
**Size:** S

#### `P2-ONBOARD-10` — Build Style DNA result screen
Scope: Implement the result screen from spec §6.10 showing primary style identity, secondary influences, preferred palette, best silhouette direction, signature item opportunities, and initial wardrobe priorities, with edit and regenerate actions.
**Acceptance criteria**
- All 6 sections from spec §6.10 render with real (non-placeholder) content from the `style-dna/generate` response.
- Regenerate produces a request to `POST /style-dna/generate` and updates the displayed result.
**Dependencies:** `P2-ONBOARD-09`, `P2-CORE-02`
**Size:** M

#### `P2-ONBOARD-11` — Implement onboarding flow coordinator with resumability
Scope: Build a router/coordinator that tracks onboarding step progress, persists the current step locally, and resumes a force-quit or interrupted onboarding session at the correct step on relaunch per spec §6.1 splash routing.
**Acceptance criteria**
- Force-quitting mid-onboarding and relaunching resumes at the same step, not step 1.
- Completing the final step transitions `AppRouteState` to `main`.
**Dependencies:** `P2-ONBOARD-02` through `P2-ONBOARD-10`, `P1-CORE-07`
**Size:** M

#### `P2-ONBOARD-12` — Implement POST /profile/complete-onboarding Edge Function
Scope: Implement the Edge Function that receives the full onboarding payload (goals, style identity, measurements, appearance, lifestyle, quiz vector), writes to `profiles`/`style_profiles`/`body_profiles`/`lifestyle_profiles`, and sets `profiles.onboarding_completed_at`.
**Acceptance criteria**
- Endpoint validates the JWT and rejects writes to a `user_id` other than the caller's.
- A successful call sets `onboarding_completed_at` to a non-null timestamp, verified by a subsequent read.
- Request schema validation rejects a malformed payload with a 4xx, not a 500.
**Dependencies:** `P1-INFRA-05`, `P1-CORE-04`
**Size:** M

## CORE

#### `P2-CORE-01` — Implement style/body/lifestyle profile repository CRUD
Scope: Implement the live `ProfileRepository` (or equivalent) methods backing onboarding forms, with SwiftData caching and Supabase sync, conforming to the protocol pattern from `P1-CORE-02`.
**Acceptance criteria**
- Reading a profile after a cold app launch returns cached local data before the network round-trip completes (optimistic local-first read).
- A local edit queues via `OfflineOperationQueue` if offline and syncs on reconnect.
**Dependencies:** `P1-CORE-02`, `P1-CORE-06`
**Size:** M

#### `P2-CORE-02` — Implement StylistReasoningProvider protocol and POST /style-dna/generate
Scope: Define the `StylistReasoningProvider` protocol per spec §8, implement a mock (fixture-based) and one live adapter, and implement the `POST /style-dna/generate` Edge Function that assembles the user's profile data into a prompt and returns structured Style DNA fields.
**Acceptance criteria**
- The Edge Function output maps 1:1 to the fields shown on the Style DNA result screen (`P2-ONBOARD-10`).
- Switching the live adapter to a different provider requires no client-side change (provider-neutral requirement, spec §8/§11).
- A profile with only required fields filled produces a coherent, non-empty result (graceful degradation with sparse input).
**Dependencies:** `P2-CORE-01`, `P2-INFRA-01`
**Size:** L

## HOME

#### `P2-HOME-01` — Build Home skeleton
Scope: Implement the Home tab's structural skeleton per spec §6.11 — header with greeting/Kyra avatar button/weather placeholder, hero card placeholder, and secondary module stack placeholders — without live data wiring (that lands in Phase 4).
**Acceptance criteria**
- Home tab renders without crashing for a freshly onboarded user with zero closet items.
- Layout matches the component list in spec §6.11 (header, hero, secondary modules).
**Dependencies:** `P1-CORE-07`, `P1-DS-04`, `P2-ONBOARD-11`
**Size:** M

#### `P2-HOME-02` — Build Home empty state
Scope: Implement the empty state defined in spec §6.11 and §21 ("Add five pieces and Kyra can begin building real outfits") shown when the user has no closet items, replacing the hero card placeholder.
**Acceptance criteria**
- Empty state displays the exact copy pattern from spec §21 and links to the add-garment flow.
- Empty state is replaced automatically once the user has ≥1 closet item (re-evaluated on Home appear).
**Dependencies:** `P2-HOME-01`
**Size:** S

## INFRA

#### `P2-INFRA-01` — Migration: enable pgvector and add embedding columns to style_profiles
Scope: Enable the `pgvector` extension and add the `embedding vector` column to `style_profiles` per spec §9, sized appropriately for the chosen `EmbeddingProvider`'s output dimensionality.
**Acceptance criteria**
- Migration applies cleanly; `pgvector` extension is listed as enabled.
- A test insert with a fixture embedding vector succeeds and a cosine-similarity query returns expected ordering against fixture data.
**Dependencies:** `P1-INFRA-05`
**Size:** S

---

# PHASE 3 — CLOSET

## SCAN

#### `P3-SCAN-01` — Build camera capture screen
Scope: Implement the scanner capture screen per spec §6.16 with AVFoundation: single-item capture mode, edge detection overlay, lighting quality indicator, blur warning, and optional auto-capture.
**Acceptance criteria**
- Camera permission is requested only when this screen is entered, not earlier (spec §7).
- Blur warning appears when the live preview is detectably blurred (tested with a deliberately shaken capture).
**Dependencies:** `P1-CORE-07`, `P1-DS-06`
**Size:** L

#### `P3-SCAN-02` — Implement device-side capture-quality pipeline
Scope: Implement Vision-based blur/exposure detection and garment-region foreground segmentation on-device per spec §12 steps 1–3, feeding the edge-detection/lighting/blur indicators in `P3-SCAN-01` and producing a segmented mask used for the initial cutout preview.
**Acceptance criteria**
- A clearly blurred photo is flagged before upload in ≥90% of a manual test set of 20 sample photos.
- Segmentation produces a usable foreground mask for a garment photographed on a neutral background.
**Dependencies:** `P3-SCAN-01`
**Size:** L

#### `P3-SCAN-03` — Implement device-side label OCR and dominant color extraction
Scope: Implement Vision text recognition for garment label OCR and dominant-color extraction from the segmented region, per spec §12 steps 4–5, to seed the analyze-item request with client-side hints.
**Acceptance criteria**
- OCR extracts readable brand/size text from a clear label photo in manual testing.
- Dominant color extraction returns a color that matches human judgment for a set of 10 solid-color test garments.
**Dependencies:** `P3-SCAN-02`
**Size:** M

#### `P3-SCAN-04` — Implement pre-upload image pipeline
Scope: Implement resize/compress/metadata-strip per spec §12 steps 6–7 before upload, targeting a size/quality tradeoff that keeps analysis latency within the spec §20 8-second target.
**Acceptance criteria**
- Uploaded images have EXIF/location metadata stripped (verified by inspecting the uploaded object).
- Compressed image size is reduced by a measurable factor from the original capture without visible quality loss in the review screen.
**Dependencies:** `P3-SCAN-03`
**Size:** S

#### `P3-SCAN-05` — Implement signed upload to closet storage path
Scope: Implement the signed-URL upload flow writing captured images to `users/{user_id}/closet/...` per spec §15, called after the pre-upload pipeline completes.
**Acceptance criteria**
- Upload succeeds and the resulting `storage_path` is retrievable via a signed URL scoped to the uploading user.
- A failed upload surfaces a retryable error state rather than silently discarding the capture.
**Dependencies:** `P3-SCAN-04`, `P1-INFRA-06`
**Size:** M

#### `P3-SCAN-06` — Build PhotosUI import as alternative to camera capture
Scope: Implement a PhotosUI-based import flow as an alternative entry point to scanning, feeding the same device-side pipeline (`P3-SCAN-02`–`04`) as camera capture, requesting Photos permission in-context per spec §7.
**Acceptance criteria**
- An imported photo goes through the same blur/segmentation/OCR/color pipeline as a camera capture before reaching the review screen.
- Photos permission is requested only when this import flow is triggered.
**Dependencies:** `P3-SCAN-04`
**Size:** S

#### `P3-SCAN-07` — Implement POST /closet/analyze-item Edge Function
Scope: Implement the server-side analysis Edge Function per spec §12 server-side steps, calling `VisionAnalysisProvider` (behind a protocol, mock + live adapter) to classify category/subtype, detect material/pattern, infer brand from OCR with confidence, generate a normalized title, estimate condition, and produce a searchable embedding.
**Acceptance criteria**
- Response includes a confidence value per inferred field, consumed by the review screen's low-confidence marking.
- P95 latency is under the spec §20 8-second target against a representative test image set.
- Switching the live `VisionAnalysisProvider` adapter requires no client change.
**Dependencies:** `P3-SCAN-05`, `P1-CORE-04`
**Size:** L

#### `P3-SCAN-08` — Implement POST /closet/batch-analyze Edge Function
Scope: Implement a batch variant of item analysis accepting multiple uploaded images in one request/job, for the multi-item batch closet scan capture mode, returning per-item results asynchronously or via polling.
**Acceptance criteria**
- Submitting 5 images in one batch returns 5 independent analysis results, each individually correctable.
- A failure on one item in the batch does not fail the entire batch.
**Dependencies:** `P3-SCAN-07`
**Size:** M

#### `P3-SCAN-09` — Build scan review screen with confidence indicators and correction UI
Scope: Implement the review screen per spec §6.16: segmented cutout preview, suggested metadata fields, visible confidence indicators per field (from `P3-SCAN-07`'s response), and full editability of every suggested field, with low-confidence fields visually marked per spec §12.
**Acceptance criteria**
- Every field suggested by analysis is editable before save.
- A field below a defined confidence threshold is visibly marked distinctly from high-confidence fields.
- Saving persists the user-corrected values, not the original AI suggestion, when they differ.
**Dependencies:** `P3-SCAN-07`, `P1-DS-04`
**Size:** L

#### `P3-SCAN-10` — Implement server-side background-removal fallback
Scope: Implement the server-side background-removal step per spec §12 step 7, triggered when the device-side segmentation result (`P3-SCAN-02`) is flagged inadequate, producing a normalized cutout asset stored to `closet_item_images.background_removed_path`.
**Acceptance criteria**
- A photo with poor device-side segmentation (e.g. non-neutral background) still produces an acceptable cutout via the server fallback.
- The fallback is only invoked when needed, not on every scan (cost control).
**Dependencies:** `P3-SCAN-07`
**Size:** M

#### `P3-SCAN-11` — Build "newly unlocked outfits" post-scan report
Scope: Implement the post-save screen/toast per spec §5.3 step 9 showing how many new outfit combinations the newly added item enables, using a simplified version of the unlock-count logic (full algorithm lands in `P4-OUTFIT-09`; this ticket may use a placeholder count until Phase 4 completes and should be revisited then).
**Acceptance criteria**
- Saving a scanned item shows a count of newly possible outfit combinations (even if computed with the Phase 3-era simplified logic).
- This screen is re-verified against the real Phase 4 unlock-count algorithm once `P4-OUTFIT-09` ships.
**Dependencies:** `P3-CLOSET-02`, `P3-SCAN-09`
**Size:** M

#### `P3-SCAN-12` — Build receipt/label and full-outfit-mirror capture modes
Scope: Implement the two remaining capture modes from spec §6.16: receipt/label capture (OCR-focused, feeding purchase metadata like retailer/price) and full outfit mirror photo (multi-garment context capture, stored but not auto-segmented per item in MVP).
**Acceptance criteria**
- Receipt capture extracts retailer/price/date text via OCR into editable fields on the item form.
- Mirror-photo capture saves the image and associates it as a reference, without requiring per-garment segmentation.
**Dependencies:** `P3-SCAN-03`
**Size:** S

## CLOSET

#### `P3-CLOSET-01` — Migration: closet_items, closet_item_images + RLS
Scope: Write the migration for `closet_items` and `closet_item_images` per the exact column lists in spec §9, with RLS scoping `closet_items` to `user_id = auth.uid()` and `closet_item_images` to ownership via its parent `closet_item_id`.
**Acceptance criteria**
- Migration applies cleanly.
- RLS blocks a cross-user read/write on both tables (automated test).
- `embedding vector` column exists on `closet_items` using the `pgvector` extension enabled in `P2-INFRA-01`.
**Dependencies:** `P2-INFRA-01`
**Size:** M

#### `P3-CLOSET-02` — Implement ClosetRepository
Scope: Implement the live `ClosetRepository` conforming to the protocol from `P1-CORE-02`, backed by SwiftData cache + Supabase sync + the `OfflineOperationQueue`, offline-first per spec §7 ("cached closet and outfits remain viewable... local edits queue for sync").
**Acceptance criteria**
- Reading the closet with no network connection returns the last-synced cached items.
- An item edit made offline appears immediately in the local UI and syncs automatically on reconnect.
**Dependencies:** `P3-CLOSET-01`, `P1-CORE-06`
**Size:** L

#### `P3-CLOSET-03` — Build Closet overview screen
Scope: Implement the Closet tab per spec §6.14: header (My Closet, search, filter, scan button) and category tiles (Tops/Bottoms/Outerwear/Shoes/Accessories/Watches/Fragrance/All items).
**Acceptance criteria**
- Tapping a category tile navigates to a filtered view of just that category.
- The scan button opens the scanner flow from `P3-SCAN-01`.
**Dependencies:** `P3-CLOSET-02`, `P1-CORE-07`, `P1-DS-04`
**Size:** L

#### `P3-CLOSET-04` — Implement closet metrics computation and view toggles
Scope: Implement the metrics row from spec §6.14 (total items, estimated closet value, average cost-per-wear, most/least worn, versatility) and the three view modes (editorial grid, compact list, color spectrum).
**Acceptance criteria**
- Metrics recompute correctly after adding, archiving, or marking an item worn.
- Color spectrum view visually orders items by dominant color, verified against a fixture set of items with known colors.
**Dependencies:** `P3-CLOSET-03`, `P3-CLOSET-10`
**Size:** L

#### `P3-CLOSET-05` — Build filter system
Scope: Implement the filter panel from spec §6.14 covering category, color, season, brand, condition, fit, availability, and wear frequency, composable together (AND semantics).
**Acceptance criteria**
- Combining 2+ filters (e.g. category=Tops, color=Blue) returns the correct intersected result set against a fixture closet.
- Clearing filters returns to the unfiltered view without a full screen reload flash.
**Dependencies:** `P3-CLOSET-03`
**Size:** M

#### `P3-CLOSET-06` — Build Item detail screen
Scope: Implement the item detail screen per spec §6.15 with all listed fields (cutout image, user photos, name, brand, category/subtype, colors, material, pattern, size, fit, condition, purchase date, price paid, retailer, product URL, wear count, last worn, cost per wear, outfit count, seasonality, care instructions, laundry state).
**Acceptance criteria**
- All fields from spec §6.15 render, and editable fields save correctly.
- Wear count and last-worn-at reflect real `outfit_wears` data once Phase 4 exists (initially zero/empty).
**Dependencies:** `P3-CLOSET-02`, `P1-DS-04`
**Size:** L

#### `P3-CLOSET-07` — Build item-detail insights
Scope: Implement the insights section on item detail per spec §6.15: best pairings, outfit gallery, redundancy score, replacement suggestion. Best-pairings and outfit-gallery are stubbed with closet-only heuristics until Phase 4's compatibility engine lands; redundancy score uses `P3-CLOSET-...` (see dependency).
**Acceptance criteria**
- Redundancy score renders a 0–100-style value backed by real logic (not a hardcoded placeholder).
- Best pairings/outfit gallery sections are marked to be revisited once `P4-OUTFIT-02` (CompatibilityScorer) ships.
**Dependencies:** `P3-CLOSET-06`, `P3-CLOSET-11` (redundancy calc dependency noted below)
**Size:** M

#### `P3-CLOSET-08` — Implement manual "add garment" form
Scope: Implement a non-scan manual entry form covering the core `closet_items` fields (name, brand, category, subcategory, primary color, size, fit, condition), used both as a first-class add path and as the vertical-slice dependency described in the roadmap.
**Acceptance criteria**
- A garment can be added end-to-end without ever opening the camera.
- Required fields (name, category) block submission when empty; all other fields are optional.
**Dependencies:** `P3-CLOSET-02`
**Size:** M

#### `P3-CLOSET-09` — Implement item actions: mark worn, add to laundry, edit, archive
Scope: Implement the item detail action row from spec §6.15: mark worn (writes to `outfit_wears`-adjacent tracking or a standalone wear event pending Phase 4, increments `wear_count`, updates `last_worn_at`), add to laundry (`laundry_state`), edit, and archive (`archived_at` soft delete).
**Acceptance criteria**
- Mark worn increments `wear_count` by 1 and sets `last_worn_at` to now.
- Archive sets `archived_at` and removes the item from default closet views without deleting the row.
**Dependencies:** `P3-CLOSET-06`
**Size:** M

#### `P3-CLOSET-10` — Implement cost-per-wear calculation utility
Scope: Implement a pure, unit-testable `costPerWear(pricePaid:currency:wearCount:)` utility used by item detail and closet metrics, handling the zero-wear case (undefined/∞ display, not divide-by-zero crash) and missing `price_paid`.
**Acceptance criteria**
- Unit test: price $100, 4 wears → $25.00 cost per wear.
- Unit test: 0 wears does not throw and renders a defined "not yet worn" state instead of a numeric value.
**Dependencies:** `P3-CLOSET-01`
**Size:** S

#### `P3-CLOSET-11` — Enforce tier-based closet item caps
Scope: Enforce the guest-mode 10-item cap (from `P1-AUTH-04`) and the free-tier 30-item cap (spec §16) at the `ClosetRepository` layer, showing an upgrade/limit prompt when a write would exceed the cap.
**Acceptance criteria**
- A free-tier user attempting to add a 31st item is blocked with a paywall prompt, not a silent failure or crash.
- A premium-tier user is never blocked by this cap (verified with a fixture subscription state).
**Dependencies:** `P3-CLOSET-02`, `P1-AUTH-04`
**Size:** S

## INFRA

#### `P3-INFRA-01` — Implement offline sync reconciliation engine
Scope: Extend `OfflineOperationQueue` (`P1-CORE-06`) with closet-specific conflict resolution: define and implement the rule for a local edit that conflicts with a remote change made on another device (last-write-wins by `updated_at`, or explicit merge — pick one and document it).
**Acceptance criteria**
- A documented conflict-resolution rule exists and is covered by a unit test simulating a conflicting local/remote edit.
- No conflict silently discards a user's local edit without at least a resolvable log/state.
**Dependencies:** `P1-CORE-06`, `P3-CLOSET-02`
**Size:** M

#### `P3-INFRA-02` — Implement queued-scan-while-offline capture-and-defer-analysis flow
Scope: Allow scan capture (`P3-SCAN-01`) to proceed while offline, queuing the captured image and deferring the `analyze-item` call until connectivity returns, per spec §7 ("New scans can be captured and queued").
**Acceptance criteria**
- A scan captured with airplane mode on is queued locally and visible in a "pending analysis" state.
- Reconnecting triggers analysis automatically without user re-initiation.
**Dependencies:** `P3-INFRA-01`, `P3-SCAN-07`
**Size:** M

## TEST

#### `P3-TEST-01` — Unit tests: cost-per-wear, redundancy score, offline queue replay
Scope: Write unit tests per spec §22 covering `costPerWear`, the redundancy score calculation, and `OfflineOperationQueue` replay ordering/failure handling.
**Acceptance criteria**
- Tests cover at minimum: zero-wear cost-per-wear, missing-price cost-per-wear, redundancy score for a duplicate-heavy fixture closet, and queue replay after a simulated failure.
- All tests pass in CI.
**Dependencies:** `P3-CLOSET-10`, `P3-CLOSET-07`, `P1-CORE-06`
**Size:** M

#### `P3-TEST-02` — UI test: complete "add a garment" flow end to end
Scope: Write the UI test from spec §22's required UI test list ("Add a garment"), covering the manual entry path (`P3-CLOSET-08`) end to end from Closet tab to item appearing in the grid.
**Acceptance criteria**
- Test passes in CI against a test Supabase project or a fully-mocked repository layer.
- Test asserts the new item is visible in the closet grid after save, not just that the form submitted without error.
**Dependencies:** `P3-CLOSET-08`, `P3-CLOSET-03`
**Size:** M

---

# PHASE 4 — OUTFIT INTELLIGENCE

## OUTFIT

#### `P4-OUTFIT-01` — Migration: outfits, outfit_items, outfit_wears + RLS
Scope: Write the migration for `outfits`, `outfit_items`, `outfit_wears` per the exact column lists in spec §9, with RLS on `outfits`/`outfit_wears` via `user_id` and on `outfit_items` via its parent `outfit_id`'s ownership.
**Acceptance criteria**
- Migration applies cleanly; `embedding vector` exists on `outfits`.
- RLS blocks cross-user access on all three tables (automated test).
**Dependencies:** `P3-CLOSET-01`
**Size:** M

#### `P4-OUTFIT-02` — Implement CompatibilityScorer.score(pairing:) weighted aggregate
Scope: Implement `CompatibilityScorer.score(pairing:)` returning a 0–100 value using the weighted formula in spec §10, reading weights from a server-provided config (fetched and cached) with a hardcoded fallback matching the spec's default weights (0.25/0.20/0.15/0.10/0.10/0.10/0.05/0.05) used when the config fetch fails.
**Acceptance criteria**
- Unit test confirms the 8 sub-scores are combined using the documented weights and sum to a 0–100 result.
- With the config-fetch mocked to fail, the scorer still produces a result using the hardcoded fallback weights, not a crash or nil.
**Dependencies:** `P4-OUTFIT-01`, `P4-OUTFIT-04`, `P4-OUTFIT-05`, `P4-OUTFIT-06`
**Size:** L

#### `P4-OUTFIT-03` — Implement server-side compatibility weight config
Scope: Implement a server-side config table/endpoint for the 8 compatibility weights per spec §10 ("weights should be configurable server-side"), with an admin-editable storage mechanism (even a simple config table editable via SQL for MVP, ahead of the full admin panel in spec §28).
**Acceptance criteria**
- Changing a weight value in the config and re-fetching changes `CompatibilityScorer`'s output for the same input pairing.
- Config endpoint validates that weights sum to 1.0 before accepting an update.
**Dependencies:** `P4-OUTFIT-01`
**Size:** M

#### `P4-OUTFIT-04` — Implement high-weight sub-scorers: color compatibility (25%) and formality alignment (20%)
Scope: Implement the color-compatibility sub-scorer (using `closet_items.primary_color`/`secondary_colors` and a color-harmony rule set) and formality-alignment sub-scorer (using `closet_items.formality_score` and `style_profiles.formality_preference`), each as independently unit-testable pure functions per spec §10.
**Acceptance criteria**
- Color sub-scorer scores a monochrome pairing higher than a clashing-color pairing in a unit test fixture.
- Formality sub-scorer scores a same-formality-tier pairing higher than a mismatched-tier pairing.
**Dependencies:** `P4-OUTFIT-01`, `P3-CLOSET-01`
**Size:** L

#### `P4-OUTFIT-05` — Implement mid-weight sub-scorers: silhouette (15%), season/weather (10%), user preference (10%)
Scope: Implement the silhouette-compatibility, season/weather-suitability, and user-preference sub-scorers per spec §10, the last of which reads `style_profiles`'s preference vector from `P2-ONBOARD-07`.
**Acceptance criteria**
- Season/weather sub-scorer scores a winter coat + shorts pairing lower than a coat + trouser pairing for a cold-weather context.
- User-preference sub-scorer produces different scores for two users with different preference vectors given the same garment pairing.
**Dependencies:** `P4-OUTFIT-01`, `P2-ONBOARD-07`
**Size:** L

#### `P4-OUTFIT-06` — Implement low-weight sub-scorers: historical co-wear (10%), occasion relevance (5%), availability/laundry (5%)
Scope: Implement the historical co-wear/feedback sub-scorer (using `outfit_wears` and `style_feedback`), occasion-relevance sub-scorer, and availability/laundry sub-scorer (using `closet_items.laundry_state`/`availability_state`) per spec §10.
**Acceptance criteria**
- Availability sub-scorer scores a pairing containing a `laundry_state = laundry` item at zero or near-zero for that component.
- Historical co-wear sub-scorer returns a neutral default for a user with no wear history (cold start), not an error.
**Dependencies:** `P4-OUTFIT-01`, `P4-OUTFIT-15`
**Size:** M

#### `P4-OUTFIT-07` — Implement POST /outfits/generate Edge Function
Scope: Implement the Edge Function producing 3 ranked `OutfitRecommendation` objects (spec §26 shape) from owned closet items, weather, schedule, laundry availability, fit, and preferences, per spec §5.4, using `CompatibilityScorer` to rank candidate combinations and generating a concise reason string for the primary recommendation via `StylistReasoningProvider`.
**Acceptance criteria**
- For a fixture closet with ≥5 items spanning tops/bottoms/shoes, the endpoint returns exactly 3 outfits, each with a non-empty `itemIDs` list and a non-generic `reason`.
- Response latency is reasonable for interactive use (target sub-few-seconds for typical closet sizes); document the measured P95 for a 50-item closet.
**Dependencies:** `P4-OUTFIT-02`, `P3-CLOSET-02`
**Size:** L

#### `P4-OUTFIT-08` — Implement POST /outfits/rank Edge Function
Scope: Implement a re-ranking endpoint accepting a candidate outfit set (e.g. after the user locks items in the builder) and returning the set reordered/filtered by `CompatibilityScorer`, per spec §14.
**Acceptance criteria**
- Passing a set of candidates with one locked item returns results that all include the locked item.
- Ranking order matches the `CompatibilityScorer` score ordering for the same inputs.
**Dependencies:** `P4-OUTFIT-02`, `P4-OUTFIT-07`
**Size:** M

#### `P4-OUTFIT-09` — Implement purchase-unlock-count algorithm
Scope: Implement the 5-step algorithm from spec §10: generate plausible combinations using owned items plus a candidate item, remove combinations below the compatibility threshold, remove near-duplicates, count combinations that fill a wardrobe gap or pass a quality bar, and cache the result (revisit/replace the placeholder used in `P3-SCAN-11`).
**Acceptance criteria**
- Unit test against a fixture wardrobe produces a deterministic, reproducible unlock count for a given candidate item.
- A cached result is reused (not recomputed) for an unchanged closet + candidate pairing, verified by call-count assertion in a test.
- Result correctly changes when a new item is added to the closet between calls.
**Dependencies:** `P4-OUTFIT-02`, `P3-CLOSET-02`
**Size:** L

#### `P4-OUTFIT-10` — Implement Wardrobe Score composite calculation
Scope: Implement the 7-component Wardrobe Score per spec §10 (versatility 25%, fit confidence 15%, occasion coverage 15%, color cohesion 10%, wear utilization 15%, condition 10%, redundancy control 10%), as a pure, unit-testable function.
**Acceptance criteria**
- Unit test confirms a fixture wardrobe with one very expensive but low-versatility item does not score higher than an equivalent wardrobe with a cheaper, more versatile substitute (spec §10 explicit non-goal: "do not equate expensive clothing with a higher score").
- Score is bounded 0–100 across a range of fixture wardrobes including empty/near-empty closets.
**Dependencies:** `P4-OUTFIT-09`, `P3-CLOSET-01`
**Size:** M

#### `P4-OUTFIT-11` — Build Outfit detail screen
Scope: Implement the Outfit detail screen per spec §6.12: full-height hero, outfit name, occasion tags, weather range, item strip, why-it-works, fit notes, color story, actions (Mark Worn, Schedule, Edit, Visualize, Share), and "Complete this look" missing-item CTA.
**Acceptance criteria**
- All action buttons are wired (no dead buttons per spec §22).
- Visualize opens the Studio flow entry point (stubbed until Phase 6, but the navigation hook exists).
**Dependencies:** `P4-OUTFIT-07`, `P1-DS-04`
**Size:** L

#### `P4-OUTFIT-12` — Build Outfit builder screen
Scope: Implement the Outfit builder per spec §6.13: flat-lay canvas (optional mannequin/avatar preview), category rail (Tops/Bottoms/Outerwear/Shoes/Watches/Accessories/Fragrance), tap-to-replace, long-press-to-lock, swipeable category suggestions, live-updating compatibility meter, "Ask Kyra to finish" action (wired to a stub call until Phase 5's `create_outfit` tool exists — revisit and re-wire in `P5-KYRA-06`), and Save as outfit.
**Acceptance criteria**
- Locking an item and triggering regenerate (via `P4-OUTFIT-08`) changes only unlocked slots.
- The compatibility meter updates live as items are swapped, calling `CompatibilityScorer` for the current combination.
- "Ask Kyra to finish" is visibly present and functional once `P5-KYRA-06` lands; before then it may show a "coming soon" state rather than a silently broken button.
**Dependencies:** `P4-OUTFIT-08`, `P1-DS-04`
**Size:** L

#### `P4-OUTFIT-13` — Build Alternative looks carousel component
Scope: Implement a shared horizontal-paging carousel component (spring-settling per spec §3 motion tokens) for alternative outfit looks, reused on both the Daily Brief (`P4-HOME-04`) and Outfit detail.
**Acceptance criteria**
- Swiping between alternatives uses spring physics matching spec §3's motion spec, not a linear animation.
- Component is a shared reusable view, not duplicated per screen.
**Dependencies:** `P4-OUTFIT-07`, `P1-DS-06`
**Size:** M

#### `P4-OUTFIT-14` — Implement wear feedback capture
Scope: Implement the Mark Worn flow writing to `outfit_wears` (worn_at, occasion, rating, feedback, weather_snapshot) and `style_feedback` (signal enum from spec §9: like/dislike/wore/skipped/saved/purchased/returned/too_formal/too_casual/bad_fit/wrong_color), incrementing each constituent item's `wear_count`.
**Acceptance criteria**
- Marking an outfit worn writes exactly one `outfit_wears` row and increments `wear_count` on every item in `outfit_items` for that outfit.
- A subsequent "skip" or "dislike" action on a different outfit writes a `style_feedback` row with the correct signal value.
**Dependencies:** `P4-OUTFIT-01`, `P3-CLOSET-09`
**Size:** M

#### `P4-OUTFIT-15` — Implement OutfitRepository
Scope: Implement the live `OutfitRepository` conforming to the Phase 1 protocol, with SwiftData caching, Supabase sync, and embedding storage for generated outfits.
**Acceptance criteria**
- Reading outfits with no network connection returns cached results (spec §7 offline requirement).
- Saving an outfit persists `outfit_items` rows with correct `role`/`sort_order`/`is_required` values.
**Dependencies:** `P4-OUTFIT-01`, `P1-CORE-06`
**Size:** M

## HOME

#### `P4-HOME-01` — Migration: daily_briefs
Scope: Write the migration for `daily_briefs` per spec §9 column list, with RLS via `user_id`.
**Acceptance criteria**
- Migration applies cleanly; RLS blocks cross-user access (automated test).
**Dependencies:** `P4-OUTFIT-01`
**Size:** S

#### `P4-HOME-02` — Implement POST /daily-brief/generate Edge Function
Scope: Implement the Edge Function assembling weather, schedule (manual occasions in MVP), and wardrobe context to produce a `daily_briefs` row referencing a `primary_outfit_id` (via `P4-OUTFIT-07`) and alternatives, with a Kyra-authored brief message.
**Acceptance criteria**
- Calling this endpoint for a user with a populated closet returns a primary outfit and at least one alternative.
- The endpoint is idempotent for a given `brief_date` — calling twice in one day returns the same brief unless explicitly regenerated.
**Dependencies:** `P4-HOME-01`, `P4-OUTFIT-07`, `P4-CORE-01`
**Size:** L

#### `P4-HOME-03` — Build Daily Brief hero card
Scope: Implement the hero card per spec §6.11: large outfit image, occasion, weather suitability, confidence score, "why this works," and actions (Wear This, Alternatives, Edit, Visualize).
**Acceptance criteria**
- Confidence score displayed matches the `outfits.compatibility_score` of the primary outfit.
- All four hero actions are wired (Wear This → mark worn flow, Alternatives → carousel, Edit → builder, Visualize → Studio stub).
**Dependencies:** `P4-HOME-02`, `P4-OUTFIT-11`, `P4-OUTFIT-13`
**Size:** L

#### `P4-HOME-04` — Build Home secondary modules
Scope: Implement the secondary Home modules per spec §6.11: alternative looks carousel (reusing `P4-OUTFIT-13`), Wardrobe Score, Kyra's Insight, purchase opportunity with unlock count, upcoming occasions, laundry/availability alert, monthly progress (stub summary until `P7-HOME-03` builds the full Monthly review).
**Acceptance criteria**
- Wardrobe Score module displays the real `P4-OUTFIT-10` value, not a placeholder.
- Purchase opportunity module shows a real unlock count from `P4-OUTFIT-09` for at least one candidate.
**Dependencies:** `P4-HOME-03`, `P4-OUTFIT-09`, `P4-OUTFIT-10`
**Size:** L

#### `P4-HOME-05` — Integrate weather provider into Home header and brief generation
Scope: Wire the live `WeatherService` adapter (`P4-CORE-01`) into the Home header display and into `daily-brief/generate`'s weather context, requesting Location permission in-context per spec §7.
**Acceptance criteria**
- Home header shows real current-location weather once permission is granted.
- Denying location permission does not block Home from rendering; it falls back to a manual-location or no-weather state.
- Location permission is requested only on first use of this screen (§6.11), not during onboarding. Added 2026-07-30: this requirement moved here from `P2-ONBOARD-06`'s §6.8 screen — a mid-onboarding prompt with no visible payoff reliably gets denied permanently — and this ticket is now its sole owner. See `docs/03-progress.md`'s "Acceptance criteria that are wrong, rather than unmet."
**Dependencies:** `P4-CORE-01`, `P4-HOME-02`
**Size:** M

#### `P4-HOME-06` — Implement occasions table and manual occasion creation UI
Scope: Write the `occasions` migration per spec §9, and build a manual "add planned occasion" UI (global action per spec §4) that does not depend on Calendar/EventKit integration (deferred to a later or cut phase per the roadmap's cut-line analysis).
**Acceptance criteria**
- A manually created occasion is usable as context by `daily-brief/generate` and by Kyra's `get_schedule` tool once Phase 5 lands.
- RLS blocks cross-user access to `occasions` (automated test).
**Dependencies:** `P4-OUTFIT-01`
**Size:** M

## CORE

#### `P4-CORE-01` — Implement WeatherService live adapter
Scope: Implement the live `WeatherService` conforming to the Phase 1 protocol using WeatherKit or a server-side weather provider per spec §8, including graceful fallback (cached last-known weather) on provider failure.
**Acceptance criteria**
- A simulated provider outage falls back to the last successfully fetched forecast rather than blocking the Daily Brief.
- Live weather data matches a manual spot-check against a known location/date.
**Dependencies:** `P1-CORE-03`
**Size:** M

## TEST

#### `P4-TEST-01` — Unit tests: CompatibilityScorer sub-scorers and weighted aggregate
Scope: Write unit tests per spec §22 for each of the 8 sub-scorers and the weighted aggregate, using fixture garment pairings with known expected relative orderings.
**Acceptance criteria**
- Tests cover at least one clear-pass and one clear-fail fixture per sub-scorer.
- Tests verify the aggregate uses the documented weights, not just that it returns a number in range.
**Dependencies:** `P4-OUTFIT-02`, `P4-OUTFIT-04`, `P4-OUTFIT-05`, `P4-OUTFIT-06`
**Size:** L

#### `P4-TEST-02` — Unit tests: Wardrobe Score and purchase-unlock-count
Scope: Write unit tests per spec §22 for `P4-OUTFIT-10` and `P4-OUTFIT-09` against multiple fixture wardrobes, including the "expensive but low-versatility item should not raise score" case explicitly.
**Acceptance criteria**
- At least one test explicitly asserts the anti-goal from spec §10 (expensive ≠ higher score).
- Unlock-count tests assert reproducibility and cache reuse.
**Dependencies:** `P4-OUTFIT-09`, `P4-OUTFIT-10`
**Size:** M

#### `P4-TEST-03` — Integration test: Daily Brief generation end to end
Scope: Write an integration test per spec §22 seeding a test closet, calling `daily-brief/generate`, and asserting a coherent response (primary outfit exists, references real closet items, weather context is present).
**Acceptance criteria**
- Test runs against a real (test/staging) Supabase project and Edge Function deployment, not only mocks.
- Test asserts the primary outfit's items are all present in the seeded closet.
**Dependencies:** `P4-HOME-02`
**Size:** M

#### `P4-TEST-04` — UI test: generate outfit and mark worn
Scope: Write the two UI tests from spec §22's required list ("Generate outfit", "Mark worn"), covering the Outfit builder/detail flow from generation through the Mark Worn action.
**Acceptance criteria**
- Test asserts `outfit_wears` (or the local cached equivalent) reflects the worn event after the UI action completes.
- Test passes in CI.
**Dependencies:** `P4-OUTFIT-14`, `P4-OUTFIT-11`
**Size:** M

---

# PHASE 5 — KYRA

## KYRA

#### `P5-KYRA-01` — Migration: kyra_threads, kyra_messages, style_memories + RLS
Scope: Write the migration per spec §9 column lists, with RLS via `user_id` on `kyra_threads` and `style_memories`, and via parent `thread_id` ownership on `kyra_messages`.
**Acceptance criteria**
- Migration applies cleanly; RLS blocks cross-user access (automated test).
- `embedding vector` exists on `style_memories`.
**Dependencies:** `P4-OUTFIT-01`, `P2-INFRA-01`
**Size:** M

#### `P5-KYRA-02` — Implement POST /kyra/respond Edge Function
Scope: Implement the core Kyra orchestration endpoint per spec §11: accepts a context packet and user message, calls `StylistReasoningProvider` with tool-calling enabled, and returns the structured response schema (`message`/`intent`/`cards`/`suggested_actions`/`memory_proposals`/`confidence`) verbatim per spec §11.
**Acceptance criteria**
- Response always conforms to the documented JSON schema; a schema-validation test against sample outputs passes.
- `intent` is always one of the 6 documented values (`daily_outfit | product_advice | outfit_review | packing | education | general`).
**Dependencies:** `P5-KYRA-01`, `P5-KYRA-03`
**Size:** XL

#### `P5-KYRA-03` — Implement Kyra context-packet builder
Scope: Implement the server-side assembly of the context packet from spec §11 (style profile, relevant body/fit profile, current weather, relevant occasions, available closet items, recent feedback, budget constraints, durable memories, requested task), scoped and truncated to avoid an unbounded data dump per spec §11's explicit design goal.
**Acceptance criteria**
- Context packet size is bounded (documented max token/item budget) regardless of closet size.
- Packet includes only `style_memories` above a confidence threshold and marked `is_user_visible` where relevant.
**Dependencies:** `P5-KYRA-01`, `P4-OUTFIT-01`, `P3-CLOSET-01`
**Size:** L

#### `P5-KYRA-04` — Implement server tool: search_closet
Scope: Implement the `search_closet` tool per spec §11, callable by Kyra during `/kyra/respond`, querying `ClosetRepository`-equivalent server-side data with filters (category, color, availability, etc.).
**Acceptance criteria**
- A tool call for "blue tops" returns only items matching category=top AND color≈blue from the seeded closet.
- Tool respects `laundry_state`/`availability_state` when the query implies availability.
**Dependencies:** `P5-KYRA-02`, `P3-CLOSET-01`
**Size:** M

#### `P5-KYRA-05` — Implement server tool: rank_outfits
Scope: Implement the `rank_outfits` tool wrapping `POST /outfits/rank` (`P4-OUTFIT-08`), callable by Kyra.
**Acceptance criteria**
- Tool call output matches a direct call to `/outfits/rank` for equivalent input.
**Dependencies:** `P5-KYRA-02`, `P4-OUTFIT-08`
**Size:** S

#### `P5-KYRA-06` — Implement server tool: create_outfit
Scope: Implement the `create_outfit` tool wrapping `POST /outfits/generate` (`P4-OUTFIT-07`), callable by Kyra, and re-wire the Outfit builder's "Ask Kyra to finish" action (from `P4-OUTFIT-12`) to invoke this tool via `/kyra/respond` instead of its Phase 4 stub.
**Acceptance criteria**
- "Ask Kyra to finish" in the Outfit builder produces a real Kyra-authored outfit completion, not the Phase 4 placeholder state.
- Tool call output includes a `reason` string, matching `/outfits/generate`'s shape.
**Dependencies:** `P5-KYRA-02`, `P4-OUTFIT-07`, `P4-OUTFIT-12`
**Size:** M

#### `P5-KYRA-07` — Implement server tool: get_weather
Scope: Implement the `get_weather` tool wrapping the live `WeatherService` (`P4-CORE-01`), callable by Kyra for occasion/packing-style questions.
**Acceptance criteria**
- Tool call returns the same forecast data as the Home header for the same location/date.
**Dependencies:** `P5-KYRA-02`, `P4-CORE-01`
**Size:** S

#### `P5-KYRA-08` — Implement server tool: get_schedule
Scope: Implement the `get_schedule` tool, backed by manually-created `occasions` (`P4-HOME-06`) with an EventKit-backed path as a future enhancement, callable by Kyra for occasion-aware questions.
**Acceptance criteria**
- A question like "what should I wear for my Friday dinner" resolves against a manually created occasion with a matching title/date.
- No occasions returns an empty result the tool handles gracefully, not an error.
**Dependencies:** `P5-KYRA-02`, `P4-HOME-06`
**Size:** M

#### `P5-KYRA-09` — Implement server tool: save_preference
Scope: Implement the `save_preference` tool per spec §11, writing to `style_memories` with a `memory_type`, `content`, `confidence`, and `is_user_visible` flag, only for durable preferences per spec §6.20's "save durable preferences only when relevant" rule.
**Acceptance criteria**
- A one-off statement ("I don't love this specific jacket") does not get persisted as a durable memory; a repeated/explicit preference does.
- Every memory written via this tool is `is_user_visible = true` by default so it appears in the memory inspection UI (`P5-KYRA-17`).
**Dependencies:** `P5-KYRA-02`, `P5-KYRA-01`
**Size:** M

#### `P5-KYRA-10` — Implement server tool: mark_item_worn
Scope: Implement the `mark_item_worn` tool wrapping the wear feedback capture logic from `P4-OUTFIT-14`, callable by Kyra (e.g. "I wore the navy blazer today").
**Acceptance criteria**
- Tool call correctly identifies the referenced closet item via `search_closet` and writes the same `outfit_wears`/`wear_count` effects as the manual UI action.
**Dependencies:** `P5-KYRA-04`, `P4-OUTFIT-14`
**Size:** M

#### `P5-KYRA-11` — Implement stub interfaces for Phase-6+ Kyra tools
Scope: Implement server-side stub/no-op interfaces for `analyze_product`, `search_products`, `generate_studio_preview`, and `create_packing_list` per spec §11's tool list, so `/kyra/respond`'s tool-calling surface is complete and Kyra can gracefully decline these requests ("I can help with that once Style Studio is available") until Phase 6 replaces them with real implementations.
**Acceptance criteria**
- Calling any of these 4 tools returns a defined "not yet available" response rather than a 500 or hallucinated result.
- Each stub has the same input schema its real Phase 6 implementation will use, to avoid a breaking change later.
**Dependencies:** `P5-KYRA-02`
**Size:** M

#### `P5-KYRA-12` — Implement guardrail layer
Scope: Implement the guardrails from spec §11: no sensitive-trait inference, no medical body-change advice, no fit-certainty claims from imagery alone, generated-image labeling requirement (enforced at the schema/prompt level), affiliate disclosure enforcement, and sponsored/organic ranking separation, as a validation/prompt-engineering layer wrapping `/kyra/respond`.
**Acceptance criteria**
- A test prompt designed to elicit a medical body-change claim ("how do I lose weight to fit this") produces a response that redirects to styling, not medical advice.
- A test prompt asking Kyra to guarantee exact fit from a photo produces a hedged, non-certain response.
**Dependencies:** `P5-KYRA-02`
**Size:** L

#### `P5-KYRA-13` — Build Kyra conversation screen
Scope: Implement the conversation UI per spec §6.20: text/voice/photo/product-link/closet-item/outfit input types, message list, and integration with `/kyra/respond`.
**Acceptance criteria**
- All 6 input types are selectable and produce a request to `/kyra/respond` with the correct payload shape.
- Sending a message shows a loading state and the response within the spec §20 2.5s-first-card target on a good connection.
**Dependencies:** `P5-KYRA-02`, `P1-DS-04`
**Size:** L

#### `P5-KYRA-14` — Build structured response card renderer
Scope: Implement the card renderer consuming `/kyra/respond`'s `cards` array per spec §11: outfit cards, product cards, closet item cards, comparison tables, and action buttons, dispatched by card type.
**Acceptance criteria**
- An outfit-type card renders using the same visual components as the Outfit detail/carousel where reasonable (component reuse, not a parallel implementation).
- An unrecognized/future card type degrades to a safe fallback rendering rather than crashing.
**Dependencies:** `P5-KYRA-13`, `P4-OUTFIT-11`
**Size:** L

#### `P5-KYRA-15` — Build suggested prompts UI
Scope: Implement the suggested-prompts row per spec §6.20 ("What should I wear tonight?", "Does this fit correctly?", "Should I buy this?", "Build me a $500 capsule", "Pack for a four-day trip"), tappable to pre-fill/send.
**Acceptance criteria**
- Tapping a suggested prompt sends it as a real message to `/kyra/respond`, not a decorative element.
**Dependencies:** `P5-KYRA-13`
**Size:** S

#### `P5-KYRA-16` — Implement voice input
Scope: Implement microphone-based voice input for the conversation screen, requesting microphone permission in-context per spec §7, transcribing to text via on-device speech recognition before sending through the same text path.
**Acceptance criteria**
- Microphone permission is requested only when voice input is tapped, not earlier.
- A transcribed voice message produces an identical `/kyra/respond` request shape to typing the same text.
**Dependencies:** `P5-KYRA-13`
**Size:** M

#### `P5-KYRA-17` — Build memory inspection/deletion UI
Scope: Implement the UI (likely under Profile/Privacy) to list a user's `style_memories` where `is_user_visible = true` and allow deletion, per spec §6.20 and §29's explicit user-inspection/deletion requirement.
**Acceptance criteria**
- Deleting a memory removes the row and Kyra's subsequent responses no longer reference it (verified by a before/after test conversation).
- The list only shows `is_user_visible = true` memories, not internal-only ones.
**Dependencies:** `P5-KYRA-09`
**Size:** M

#### `P5-KYRA-18` — Implement KyraRepository
Scope: Implement the live `KyraRepository` conforming to the Phase 1 protocol, persisting `kyra_threads`/`kyra_messages` locally for offline read access and syncing new messages.
**Acceptance criteria**
- Reopening a past conversation thread with no network shows cached message history.
- New messages sent while offline are clearly marked as failed/pending rather than silently lost (generative features require network per spec §7, so this should surface an explicit "Kyra needs a connection" state, not a silent queue-and-hope).
**Dependencies:** `P5-KYRA-01`, `P1-CORE-06`
**Size:** M

#### `P5-KYRA-19` — Implement Kyra conversation rate limiting per subscription tier
Scope: Implement server-side enforcement of the free-tier 3-conversations-per-day limit from spec §16, driven by a configurable limit value (not a hardcoded constant, per the roadmap's risk note about unknown LLM cost).
**Acceptance criteria**
- A free-tier user's 4th conversation attempt in a day is blocked server-side with a clear upgrade prompt, even if the client is bypassed/tampered with.
- Premium-tier users are never blocked by this limit.
**Dependencies:** `P5-KYRA-02`
**Size:** M

## CORE

#### `P5-CORE-01` — Implement structured JSON response parsing and schema validation
Scope: Implement client-side Codable models and validation for the `/kyra/respond` response schema (spec §11), including defensive handling of a malformed or partially-invalid payload (missing optional fields, unexpected card type).
**Acceptance criteria**
- A payload missing `suggested_actions` (optional) parses successfully with an empty array default.
- A payload with an unrecognized `intent` value does not crash the client; it degrades to `general`.
**Dependencies:** `P5-KYRA-02`
**Size:** M

## TEST

#### `P5-TEST-01` — Unit tests: Kyra structured response parsing
Scope: Write unit tests per spec §22 for the parsing logic in `P5-CORE-01`, including a fixture set of valid, partially-invalid, and malformed payloads.
**Acceptance criteria**
- Tests cover at least one case per documented `intent` value and one deliberately malformed payload.
- All tests pass in CI.
**Dependencies:** `P5-CORE-01`
**Size:** M

#### `P5-TEST-02` — UI test: Ask Kyra flow
Scope: Write the UI test from spec §22's required list ("Ask Kyra"), sending a message and asserting an outfit card renders in the response.
**Acceptance criteria**
- Test passes in CI against a test/staging deployment of `/kyra/respond`.
- Test asserts the rendered card's item references match closet items seeded for the test user.
**Dependencies:** `P5-KYRA-14`
**Size:** M

---

# PHASE 6 — STUDIO AND COMMERCE

## STUDIO

#### `P6-STUDIO-01` — Migration: studio_generations + RLS
Scope: Write the migration per spec §9 column list, with RLS via `user_id`.
**Acceptance criteria**
- Migration applies cleanly; RLS blocks cross-user access (automated test).
**Dependencies:** `P4-OUTFIT-01`
**Size:** S

#### `P6-STUDIO-02` — Build reference image capture/selection screen
Scope: Implement the reference image step per spec §13 step 1–2: select a saved selfie/avatar or capture a new one, with explicit consent/ownership validation before any generation request is allowed (spec §6.17 safety requirement).
**Acceptance criteria**
- Generation cannot be initiated without a completed consent acknowledgment for the specific reference image being used.
- Reference images are stored under `users/{user_id}/references/` per spec §15.
**Dependencies:** `P2-ONBOARD-08`, `P1-INFRA-06`
**Size:** M

#### `P6-STUDIO-03` — Implement ImageGenerationProvider protocol
Scope: Define the `ImageGenerationProvider` protocol per spec §8 with a mock implementation (returns a static placeholder image with correct metadata shape) and one live adapter.
**Acceptance criteria**
- Mock and live adapters conform to an identical protocol; switching between them requires no caller-side change.
**Dependencies:** `P1-CORE-01`
**Size:** M

#### `P6-STUDIO-04` — Implement POST /studio/generate Edge Function
Scope: Implement the generation endpoint per spec §13: build a structured outfit prompt from exact garments (using the outfit's `outfit_items`), assemble the prompt template from spec §13 exactly (preserving facial features/proportions/skin tone/hair per the template), and queue a generation job with `ImageGenerationProvider`. Includes wiring the `generate_studio_preview` Kyra tool stub from `P5-KYRA-11` to this real endpoint.
**Acceptance criteria**
- Submitted prompt to the provider matches the exact template structure from spec §13, with garment list populated from real `outfit_items`.
- A job row is created in `studio_generations` with `status = queued` before returning to the client.
- The `generate_studio_preview` Kyra tool now returns a real job reference instead of the Phase 5 stub response.
**Dependencies:** `P6-STUDIO-01`, `P6-STUDIO-02`, `P6-STUDIO-03`, `P4-OUTFIT-01`, `P5-KYRA-11`
**Size:** XL

#### `P6-STUDIO-05` — Implement prompt template assembly
Scope: Implement the structured prompt builder producing the exact template from spec §13 ("Create a realistic editorial menswear visualization...") parameterized by garment list, pose, background, and lighting selections from the Studio UI.
**Acceptance criteria**
- Unit test confirms the assembled prompt string matches the spec §13 template with placeholders correctly substituted.
- Missing optional parameters (pose/background/lighting) fall back to documented defaults rather than leaving a literal placeholder in the prompt.
**Dependencies:** `P6-STUDIO-04`
**Size:** M

#### `P6-STUDIO-06` — Implement GET /studio/status/:id polling endpoint and job queue states
Scope: Implement the status-polling endpoint and the queued/generating/complete/failed state machine per spec §6.17, persisted on `studio_generations.status`.
**Acceptance criteria**
- Polling a job in progress returns `generating`; polling after provider completion returns `complete` with a populated `result_image_path`.
- Polling an unowned job ID (another user's) returns a 403/404, not the job data.
**Dependencies:** `P6-STUDIO-04`
**Size:** M

#### `P6-STUDIO-07` — Implement generation cost controls and retention job
Scope: Implement the cost controls from spec §13: job queuing, rate limiting by subscription tier, caching of repeated garment-combination requests, and draft-before-hi-res generation tiering; and the abandoned-source-image retention/deletion job (configurable retention window).
**Acceptance criteria**
- Two identical generation requests (same outfit, same reference image, same options) for the same user reuse a cached result instead of double-billing a provider call.
- A source image with no completed generation after the configured retention window is deleted by the retention job, verified in a test with an artificially short window.
**Dependencies:** `P6-STUDIO-04`, `P6-STUDIO-06`
**Size:** L

#### `P6-STUDIO-08` — Build Style Studio main screen
Scope: Implement the Studio screen per spec §6.17: top controls (Outfit/Top/Bottom/Shoes/Accessories), main viewport (avatar/reference image, before/after compare, generated-image label), and generation trigger.
**Acceptance criteria**
- Generated images always display the "estimate" disclaimer label per spec §6.17 and §11 guardrails, non-dismissable/persistent on the image.
- Before/after compare is functional with a real generated result.
**Dependencies:** `P6-STUDIO-06`, `P1-DS-04`
**Size:** L

#### `P6-STUDIO-09` — Build prompt presets and advanced controls UI
Scope: Implement the 8 prompt presets (smart casual, date night, wedding, vacation, executive, old-money inspired, minimalist, night out) and the advanced controls (preserve face/body/hair, background, pose, formality, season, color palette) per spec §6.17.
**Acceptance criteria**
- Selecting a preset populates the advanced controls with sensible defaults that the user can still override.
- Every advanced control maps to a parameter consumed by `P6-STUDIO-05`'s prompt assembly.
**Dependencies:** `P6-STUDIO-08`, `P6-STUDIO-05`
**Size:** L

#### `P6-STUDIO-10` — Build generation state UI
Scope: Implement queued/generating/complete/failed-with-retry states in the Studio UI per spec §6.17 and §21, ensuring a provider-side failure does not consume a user's generation credit/quota (spec §21 explicit requirement) and the original prompt is preserved for retry.
**Acceptance criteria**
- A simulated provider failure shows a retry action, preserves the original prompt/options, and does not decrement the user's remaining quota.
- Queued/generating states show real progress feedback, not an indefinite spinner with no state distinction.
**Dependencies:** `P6-STUDIO-06`, `P6-STUDIO-08`
**Size:** M

#### `P6-STUDIO-11` — Build results gallery and save-to-lookbook
Scope: Implement a gallery of a user's past Studio generations with save/delete actions, per spec §5.6 step 6.
**Acceptance criteria**
- Deleting a result from the gallery removes the underlying storage object, not just the local reference (ties to `P7-PRIVACY-04`).
- Gallery loads incrementally/paginated for users with many generations, not all at once.
**Dependencies:** `P6-STUDIO-08`
**Size:** M

#### `P6-STUDIO-12` — Implement StudioRepository
Scope: Implement the live `StudioRepository` conforming to the Phase 1 protocol: job submission, status polling, local caching of results, and deletion controls.
**Acceptance criteria**
- Polling is implemented with reasonable backoff, not a tight loop.
- Deletion controls call through to the same underlying deletion path used by `P6-STUDIO-11`.
**Dependencies:** `P6-STUDIO-04`, `P6-STUDIO-06`
**Size:** M

## SHOP

#### `P6-SHOP-01` — Migration: product_candidates, user_product_evaluations + RLS
Scope: Write the migration per spec §9 column lists. `product_candidates` is not strictly per-user (shared catalog entries) — apply RLS appropriate to a shared-read/service-write table, while `user_product_evaluations` is scoped via `user_id`.
**Acceptance criteria**
- Migration applies cleanly.
- A user cannot write/modify another user's `user_product_evaluations` row (automated RLS test); `product_candidates` reads are available to any authenticated user, writes are service-role only.
**Dependencies:** `P4-OUTFIT-01`
**Size:** M

#### `P6-SHOP-02` — Implement ProductExtractionProvider protocol
Scope: Define the `ProductExtractionProvider` protocol per spec §8 with a mock and one live adapter (either a scraping-based extractor for pasted URLs or an API-based retailer integration).
**Acceptance criteria**
- Mock and live adapters conform to an identical protocol.
- Live adapter extracts brand, name, price, category, and image URL from at least 3 different real retailer product pages in manual testing.
**Dependencies:** `P1-CORE-01`
**Size:** M

#### `P6-SHOP-03` — Implement POST /products/extract Edge Function
Scope: Implement the endpoint accepting a pasted product URL, calling `ProductExtractionProvider`, and upserting a `product_candidates` row per spec §5.5 step 1–2.
**Acceptance criteria**
- Submitting a supported retailer URL creates or updates a `product_candidates` row with `last_checked_at` refreshed.
- An unsupported/unparseable URL returns a clear error, not a partially-populated row.
**Dependencies:** `P6-SHOP-01`, `P6-SHOP-02`
**Size:** L

#### `P6-SHOP-04` — Implement POST /products/evaluate Edge Function
Scope: Implement the evaluation endpoint per spec §5.5/§6.19/§10: compatibility score, redundancy risk, outfits-unlocked count (reusing `P4-OUTFIT-09`'s algorithm), color fit, lifestyle fit, budget fit, expected cost-per-wear, and a Kyra verdict (buy/consider/wait for sale/skip), writing to `user_product_evaluations`. Includes wiring the `analyze_product`/`search_products` Kyra tool stubs from `P5-KYRA-11` to this real endpoint.
**Acceptance criteria**
- Evaluating a near-duplicate of an owned item returns a high redundancy risk and a `skip` or `wait_for_sale` verdict.
- Sponsored/affiliate availability of the product does not change the verdict, verified with a test case where a non-affiliate identical-scoring alternative is still surfaced (spec §11 guardrail).
- The `analyze_product`/`search_products` Kyra tools now call this real endpoint instead of the Phase 5 stub.
**Dependencies:** `P6-SHOP-01`, `P6-SHOP-03`, `P4-OUTFIT-09`, `P5-KYRA-11`
**Size:** L

#### `P6-SHOP-05` — Build Product decision page
Scope: Implement the decision page per spec §6.19 with all scores and the Kyra verdict, plus the alternatives listed in spec §5.5 step 3 (lower-cost alternative, higher-quality alternative).
**Acceptance criteria**
- All scores from `P6-SHOP-04`'s response render with labels matching spec §6.19.
- The verdict is visually distinct per value (buy/consider/wait/skip use different treatment, not just different text).
**Dependencies:** `P6-SHOP-04`, `P1-DS-04`
**Size:** M

#### `P6-SHOP-06` — Build Shop the look screen
Scope: Implement the screen per spec §6.18: outfit preview with owned items clearly marked, missing items listed with retailer/price/sizes, and affiliate disclosure.
**Acceptance criteria**
- Owned vs missing items are visually distinguishable at a glance, not just via a label a user could miss.
- Affiliate disclosure text is present on every listed product, per spec §17.
**Dependencies:** `P6-SHOP-04`, `P4-OUTFIT-11`
**Size:** M

#### `P6-SHOP-07` — Implement affiliate redirect and wishlist/purchased actions
Scope: Implement the retailer redirect via `SFSafariViewController`/universal link per spec §17, and the add-to-wishlist / mark-purchased actions per spec §5.5 step 6 and §6.18.
**Acceptance criteria**
- Tapping "open retailer" opens `SFSafariViewController` (or a universal link handoff), not an in-app WebView masquerading as the retailer.
- Marking a wishlist item as purchased updates its state and is reflected in Profile stats.
**Dependencies:** `P6-SHOP-06`
**Size:** M

#### `P6-SHOP-08` — Implement curated product catalog admin-fed ingestion path
Scope: Implement the minimal curated-catalog ingestion path from spec §17 option 1 — a service-role-writable `product_candidates` insert/update path, ahead of the full admin web tool in spec §28 — so launch is not solely dependent on user-pasted links or unrestricted scraping (spec §17 explicit requirement).
**Acceptance criteria**
- A curated product can be inserted via a service-role script/SQL and appears in search/evaluation flows identically to a user-extracted product.
- No client-side path can write directly to `product_candidates` (service-role only, enforced by RLS).
**Dependencies:** `P6-SHOP-01`
**Size:** M

#### `P6-SHOP-09` — Implement sponsored-vs-organic ranking separation and labeling
Scope: Implement the explicit separation from spec §17: sponsored products are labeled and never influence Kyra's ranking/verdict logic, verified as a distinct code path from organic ranking in `P6-SHOP-04`.
**Acceptance criteria**
- A code-level test confirms `sponsored` flag has zero weight in the compatibility/verdict calculation.
- UI clearly labels any sponsored placement, distinct from organic recommendations.
**Dependencies:** `P6-SHOP-04`
**Size:** S

#### `P6-SHOP-10` — Implement ShoppingRepository
Scope: Implement the live `ShoppingRepository` conforming to the Phase 1 protocol: product extraction, evaluation, wishlist state, and purchase history.
**Acceptance criteria**
- Repository caches recent evaluations locally for offline viewing (spec §7 offline requirement for cached content).
**Dependencies:** `P6-SHOP-04`, `P1-CORE-06`
**Size:** M

## CORE

#### `P6-CORE-01` — Build Discover screen sections
Scope: Implement the Discover tab per spec §6.21: Kyra-curated lookbooks, style education, seasonal guides, fit guides, brand spotlights — explicitly not a generic shopping feed per spec's constraint.
**Acceptance criteria**
- Content is sourced from an editorial content table/config, not hardcoded shopping product cards.
- No section presents unlabeled sponsored content (ties to `P6-SHOP-09`'s labeling requirement).
**Dependencies:** `P1-CORE-07`, `P1-DS-04`
**Size:** L

## TEST

#### `P6-TEST-01` — Integration test: Studio job polling lifecycle
Scope: Write an integration test per spec §22 covering job submission through polling to completion, and a simulated provider failure through the retry path.
**Acceptance criteria**
- Test covers queued → generating → complete, and separately queued → generating → failed → retry-without-quota-loss.
**Dependencies:** `P6-STUDIO-06`, `P6-STUDIO-10`
**Size:** M

#### `P6-TEST-02` — Integration test: product evaluation end to end
Scope: Write an integration test per spec §22 seeding a closet and a candidate product, calling `/products/evaluate`, and asserting a coherent verdict and score set.
**Acceptance criteria**
- Test asserts a near-duplicate candidate produces high redundancy risk and a non-buy verdict.
**Dependencies:** `P6-SHOP-04`
**Size:** M

---

# PHASE 7 — MONETIZATION AND HARDENING

## SUB

#### `P7-SUB-01` — Migration: subscriptions + App Store product configuration
Scope: Write the `subscriptions` migration per spec §9, and configure App Store Connect product IDs for the monthly ($12.99) and annual ($79.99) plans per spec §16.
**Acceptance criteria**
- Migration applies cleanly; RLS via `user_id`.
- Product IDs are configured and fetchable via StoreKit in a sandbox test.
**Dependencies:** `P1-INFRA-05`
**Size:** M

#### `P7-SUB-02` — Implement StoreKit 2 purchase flow
Scope: Implement the StoreKit 2 purchase flow for both plans, including transaction verification and local entitlement update on successful purchase.
**Acceptance criteria**
- A sandbox purchase of either plan updates local entitlement state immediately without requiring app restart.
- Transaction verification rejects an unverified/tampered transaction.
**Dependencies:** `P7-SUB-01`
**Size:** L

#### `P7-SUB-03` — Implement subscription server reconciliation
Scope: Implement `POST /subscriptions/sync` (client-triggered reconciliation) and `POST /app-store/webhook` (App Store Server Notifications) per spec §14, writing/updating `subscriptions` rows as the source of truth for entitlement.
**Acceptance criteria**
- A renewal notification from the webhook correctly extends `expires_at` without requiring the client to be open.
- A cancellation notification correctly updates `status` and the next entitlement check reflects it.
**Dependencies:** `P7-SUB-01`, `P7-SUB-02`
**Size:** L

#### `P7-SUB-04` — Implement subscription entitlement logic
Scope: Implement the unified entitlement-check logic per spec §16 gating: closet item cap (30 free / unlimited premium), outfit generation limits, Kyra conversation limits (3/day free, tied to `P5-KYRA-19`), and Studio quota (1 trial / higher premium quota), reading from `subscriptions.status`.
**Acceptance criteria**
- Unit tests cover every documented free-tier limit and confirm premium removes each one.
- A lapsed/expired subscription correctly reverts to free-tier limits without requiring app reinstall.
**Dependencies:** `P7-SUB-03`, `P3-CLOSET-11`, `P5-KYRA-19`, `P6-STUDIO-07`
**Size:** L

#### `P7-SUB-05` — Build Paywall screen
Scope: Implement the paywall per spec §16: marble hero, clear benefit list, monthly and annual plans, restore purchases, manage subscription, legal links.
**Acceptance criteria**
- Both plans display correct localized pricing from StoreKit, not hardcoded strings.
- "Manage subscription" deep-links to the system subscription management screen.
**Dependencies:** `P7-SUB-02`, `P1-DS-05`
**Size:** L

#### `P7-SUB-06` — Implement restore purchases flow and StoreKit sandbox test configuration
Scope: Implement the restore-purchases action and the `.storekit` sandbox test configuration file used by CI/local testing per spec §22 integration test requirement.
**Acceptance criteria**
- A fresh install with a prior sandbox purchase correctly restores premium entitlement via the restore action.
- `.storekit` configuration file is checked into the repo and referenced by the test scheme.
**Dependencies:** `P7-SUB-02`
**Size:** M

#### `P7-SUB-07` — Implement SubscriptionRepository
Scope: Implement the live `SubscriptionRepository` conforming to the Phase 1 protocol, exposing current entitlement state to the rest of the app for gating checks (`P7-SUB-04`).
**Acceptance criteria**
- Repository state updates immediately after a purchase or restore without requiring a manual refresh elsewhere in the app.
**Dependencies:** `P7-SUB-04`
**Size:** M

## PRIVACY

#### `P7-PRIVACY-01` — Implement DELETE /account cascading deletion
Scope: Implement the account-deletion Edge Function per spec §15: remove all rows across every user-owned table created in Phases 1–6, all Storage objects under `users/{user_id}/`, embeddings, style memories, and the Supabase Auth identity, using an async deletion job with user-visible status if it cannot complete synchronously.
**Acceptance criteria**
- After deletion, a direct database query for the deleted `user_id` returns zero rows across every table listed in spec §9.
- After deletion, listing the `users/{user_id}/` storage prefix returns zero objects.
- The deletion job's status is queryable and reaches a terminal "complete" state.
**Dependencies:** every schema migration ticket in Phases 1–6 (`P1-INFRA-05`, `P1-INFRA-06`, `P3-CLOSET-01`, `P4-OUTFIT-01`, `P4-HOME-01`, `P5-KYRA-01`, `P6-STUDIO-01`, `P6-SHOP-01`, `P7-SUB-01`)
**Size:** XL

#### `P7-PRIVACY-02` — Build in-app account deletion UI
Scope: Implement the deletion confirmation flow and user-visible deletion job status screen per spec §7 ("Account deletion inside app").
**Acceptance criteria**
- Deletion requires an explicit confirmation step (not a single accidental tap).
- User sees a status indicator until deletion completes, then is signed out automatically.
**Dependencies:** `P7-PRIVACY-01`
**Size:** M

#### `P7-PRIVACY-03` — Implement personal data export
Scope: Implement a data export feature per spec §29, producing a user-readable export (e.g. JSON or PDF) of the user's profile, closet, outfits, and Kyra conversation history.
**Acceptance criteria**
- Export includes data from every major user-owned table, not just profile fields.
- Export excludes other users' data and any service-role-only fields.
**Dependencies:** `P7-PRIVACY-01`
**Size:** M

#### `P7-PRIVACY-04` — Implement delete-individual reference/generated-image controls
Scope: Implement per-image deletion controls per spec §29 for reference photos and Studio generations, distinct from full account deletion, reusing the deletion path from `P6-STUDIO-11`.
**Acceptance criteria**
- Deleting a single reference image removes the storage object and any `studio_generations` rows are updated/handled consistently (not left pointing at a deleted file).
**Dependencies:** `P6-STUDIO-11`
**Size:** S

#### `P7-PRIVACY-05` — Write Privacy Policy and Terms of Service content
Scope: Write the Privacy Policy (describing image processing, model providers, retention, affiliate relationships per spec §29) and Terms of Service (prohibiting uploading images without permission per spec §29), and wire them into the Welcome/Profile legal links from `P1-AUTH-06`.
**Acceptance criteria**
- Privacy Policy explicitly names the categories of data processed and each model-provider category (`StylistReasoningProvider`, `VisionAnalysisProvider`, `ImageGenerationProvider`, etc.) without necessarily naming the specific vendor.
- Legal links in the app open this real content, not a placeholder.
**Dependencies:** `P1-AUTH-06`
**Size:** M

#### `P7-PRIVACY-06` — Implement training opt-out default and ATT prompt
Scope: Implement the opt-out-of-model-training preference per spec §29 (default: no training on user images without explicit consent), and implement the App Tracking Transparency prompt only if cross-app tracking is actually implemented per spec §7/§29 conditional requirement.
**Acceptance criteria**
- Default state for a new user is "no training," verified by inspecting the stored preference immediately after onboarding.
- If no cross-app tracking exists in the shipped build, no ATT prompt is shown (avoiding an unnecessary permission request per spec §22 acceptance bar).
**Dependencies:** `P2-ONBOARD-12`
**Size:** M

#### `P7-PRIVACY-07` — Audit analytics_events and Edge Function logs for sensitive data leakage
Scope: Audit every `analytics_events` emission point and every Edge Function's request logging (spec §14, §18) to confirm no private images or free-text prompt content is logged, per spec's explicit requirement.
**Acceptance criteria**
- Grepping a sample of production-equivalent logs for image URLs or raw prompt text returns nothing.
- Every analytics event in the spec §18 list is verified to carry only non-sensitive metadata.
**Dependencies:** `P5-KYRA-02`, `P6-STUDIO-04`
**Size:** M

## DS

#### `P7-DS-01` — Full Dynamic Type audit and remediation
Scope: Audit every screen against Dynamic Type accessibility sizes per spec §19, fixing truncation/overlap issues, prioritizing the spec §30 Definition-of-Done critical-path screens first per the roadmap's cut-line guidance.
**Acceptance criteria**
- At the largest accessibility Dynamic Type size, Home, Closet, Outfit detail, Kyra conversation, and Paywall show no truncated or overlapping primary text.
**Dependencies:** every prior-phase screen ticket
**Size:** L

#### `P7-DS-02` — VoiceOver label audit
Scope: Audit every screen for VoiceOver labels on outfit imagery and controls with a logical read order per spec §19, adding accessibility labels/traits/hints where missing.
**Acceptance criteria**
- VoiceOver can complete the full spec §30 DoD flow (items 1–14) without an unlabeled or unreachable control.
- Outfit item strips read in the correct logical order (not raw z-index/view-tree order) per spec §19's explicit requirement.
**Dependencies:** every prior-phase screen ticket
**Size:** L

#### `P7-DS-03` — High-contrast champagne-text alternative and color-independent-meaning audit
Scope: Implement a high-contrast alternative for champagne-colored text per spec §19, and audit every screen for color-only signaling (e.g. compatibility meter, confidence score) adding a non-color indicator (icon/text) alongside.
**Acceptance criteria**
- A WCAG-AA-compliant champagne alternative (`accentChampagneAccessible`) is used everywhere champagne meaning is conveyed as text or a border/stroke. Amended 2026-07-30: this originally specified the alternative behind a "High Contrast" accessibility toggle; the shipped app applies it unconditionally by default instead, which is strictly better — no user has to discover and enable a setting to get legible champagne text — and made the toggle-gated criterion unreachable. See `docs/03-progress.md`'s "Acceptance criteria that are wrong, rather than unmet."
- Every color-coded status (verdict, confidence, laundry state) has an accompanying text or icon indicator.
**Dependencies:** `P1-DS-01`
**Size:** M

#### `P7-DS-04` — Reduce Motion audit and editable alt-description UI
Scope: Audit every animated component against Reduce Motion per spec §19, and implement editable alt-text descriptions for generated Studio images per spec §19's explicit requirement.
**Acceptance criteria**
- Reduce Motion enabled removes matched-geometry transitions, spring paging, and the breathing Kyra orb across every screen that uses them.
- A generated Studio image has an editable alt-description field, defaulted to a reasonable auto-generated description.
**Dependencies:** `P1-DS-06`, `P6-STUDIO-08`
**Size:** M

## HOME

#### `P7-HOME-01` — Implement notification scheduling
Scope: Implement local/push notification scheduling per spec §7: daily outfit ready, upcoming occasion, laundry reminder, monthly review, packing reminder (excluding price-drop, deferred per spec §7's "future" label), requesting Notifications permission only after the user has seen value per spec §7.
**Acceptance criteria**
- Notifications permission is requested contextually (e.g. after the first successful Daily Brief), not on first launch.
- No more than the documented notification types fire; there is no shopping-notification spam (spec §7 explicit constraint).
**Dependencies:** `P4-HOME-02`
**Size:** L

#### `P7-HOME-02` — Audit in-context permission request timing
Scope: Audit every permission request (camera, photos, location, calendar, notifications, microphone) across the whole app against spec §7's "request only in context" rule, fixing any that fire prematurely.
**Acceptance criteria**
- A fresh install triggers zero permission prompts before the user reaches the specific feature that needs each permission.
- This is verified against every permission type listed in spec §7, not just camera/location.
**Dependencies:** every permission-requesting ticket (`P3-SCAN-01`, `P3-SCAN-06`, `P4-HOME-05`, `P5-KYRA-16`, `P7-HOME-01`). `P2-ONBOARD-06` dropped 2026-07-30 — it no longer requests any permission; that requirement moved to `P4-HOME-05`, already listed.
**Size:** M

#### `P7-HOME-03` — Build Monthly review screen
Scope: Implement the Monthly review per spec §6.23: new items, spend, wears, best purchase, underused items, versatility change, next priority, one challenge for next month, authored via `StylistReasoningProvider`.
**Acceptance criteria**
- Content is generated from real `outfit_wears`/`closet_items`/`user_product_evaluations` data for the elapsed month, not static placeholder text.
- Replaces the Home "monthly progress" stub module from `P4-HOME-04`.
**Dependencies:** `P4-OUTFIT-14`, `P4-OUTFIT-10`, `P2-CORE-02`
**Size:** M

#### `P7-HOME-04` — Build Packing assistant screen
Scope: Implement the Packing assistant per spec §6.24: inputs (destination, dates, activities, dress codes, luggage constraints, laundry access) and outputs (packing list, daily outfit plan, rewear map, missing essentials, weather contingencies), wiring the `create_packing_list` Kyra tool stub from `P5-KYRA-11`.
**Acceptance criteria**
- Submitting inputs produces a daily outfit plan drawing from real closet items via `create_outfit`/`search_closet`-equivalent logic.
- The `create_packing_list` tool now returns a real result instead of the Phase 5 stub.
**Dependencies:** `P5-KYRA-11`, `P4-OUTFIT-07`, `P4-CORE-01`
**Size:** L

#### `P7-HOME-05` — Build full Profile and stats screen
Scope: Implement the complete Profile screen per spec §6.22: profile image, Style DNA, Wardrobe Score, items owned, outfits created, cost per wear, most-worn colors, monthly spend, Style Journey timeline, subscription, preferences, privacy/data controls (linking to `P7-PRIVACY-02/03/04` and `P5-KYRA-17`).
**Acceptance criteria**
- Every stat shown is computed from real data (Wardrobe Score, cost per wear, etc.), not placeholder values.
- Privacy and data controls section links correctly to account deletion, data export, and memory management.
**Dependencies:** `P4-OUTFIT-10`, `P5-KYRA-17`, `P7-PRIVACY-02`, `P7-PRIVACY-03`, `P7-SUB-05`
**Size:** M

## INFRA

#### `P7-INFRA-01` — Implement per-endpoint rate limiting and privacy-safe request logging
Scope: Implement rate limiting on every Edge Function listed in spec §14, and request-ID/latency logging that explicitly excludes private images and full prompt contents per spec §14's requirement.
**Acceptance criteria**
- Exceeding a documented rate limit on any endpoint returns a 429 with a retry-after hint, not a silent failure or crash.
- Logs are inspected (ties to `P7-PRIVACY-07`) and confirmed free of image data and raw prompt text.
**Dependencies:** every Edge Function ticket in Phases 2–6
**Size:** M

#### `P7-INFRA-02` — Performance pass against spec §20 targets
Scope: Measure and optimize against every numeric target in spec §20: cold launch <2.5s, cached Home render <500ms, closet grid 60fps, item analysis <8s, Kyra first token/card <2.5s, draft Studio generation <30s.
**Acceptance criteria**
- Each of the 6 targets is measured on a representative supported device and documented with the measured value alongside the target.
- Any target missed has a documented root cause and either a fix or an explicit accepted-risk note.
**Dependencies:** every feature ticket contributing to each measured flow
**Size:** L

#### `P7-INFRA-03` — Image pipeline optimization
Scope: Implement HEIF/WebP-equivalent thumbnails, eliminate full-resolution image rendering in grids (spec §20 explicit rule), implement next-outfit-image prefetching, and audit image caches for memory-awareness.
**Acceptance criteria**
- Closet grid never loads a full-resolution original for thumbnail display, verified by inspecting network/asset requests during scrolling.
- Memory usage during extended closet-grid scrolling (100+ items) stays within a documented bound without app termination.
**Dependencies:** `P3-CLOSET-04`, `P4-OUTFIT-13`
**Size:** M

#### `P7-INFRA-04` — Zero-warnings build pass and dependency audit
Scope: Resolve every compiler warning across the project and audit third-party dependencies for necessity/licensing per spec §31's "build without warnings" requirement.
**Acceptance criteria**
- A clean build produces zero warnings.
- Every third-party dependency in use is documented with its purpose and license.
**Dependencies:** all tickets
**Size:** M

#### `P7-INFRA-05` — Author README and App Store submission assets
Scope: Write the README per spec §31 (setup, environment variables, Supabase migrations, Edge Function deployment, StoreKit configuration, test instructions), and prepare App Store Connect assets (screenshots, listing copy, privacy nutrition labels reflecting the actual data collected).
**Acceptance criteria**
- A developer unfamiliar with the project can follow the README to get a local build running against a fresh Supabase project.
- Privacy nutrition labels accurately reflect every data category actually collected (cross-checked against `P7-PRIVACY-05`'s Privacy Policy).
**Dependencies:** all tickets
**Size:** M

## TEST

#### `P7-TEST-01` — Unit tests: subscription entitlement logic
Scope: Write unit tests per spec §22 covering `P7-SUB-04`'s entitlement logic across every tier boundary and edge case (exactly-at-limit, expired-mid-session, guest-to-free transition).
**Acceptance criteria**
- Tests cover at minimum: free-tier at-limit, premium-unlimited, expired-subscription-reverts-to-free, and guest-mode caps.
**Dependencies:** `P7-SUB-04`
**Size:** M

#### `P7-TEST-02` — Integration test: full auth lifecycle
Scope: Write the integration test from spec §22's required list, covering sign in, session restore, sign out, and account deletion in one continuous test.
**Acceptance criteria**
- Test runs against a real test Supabase project and confirms the account no longer exists after the deletion step.
**Dependencies:** `P7-PRIVACY-01`, `P1-AUTH-03`
**Size:** M

#### `P7-TEST-03` — Integration test: StoreKit sandbox purchase lifecycle
Scope: Write the integration test from spec §22's required list, covering sandbox purchase, renewal simulation, and cancellation using the `.storekit` config from `P7-SUB-06`.
**Acceptance criteria**
- Test confirms entitlement state transitions correctly through purchase → active → cancelled → expired.
**Dependencies:** `P7-SUB-06`, `P7-SUB-04`
**Size:** L

#### `P7-TEST-04` — UI test: complete onboarding end to end
Scope: Write the UI test from spec §22's required list, covering the full onboarding flow from Welcome through Style DNA result to Home.
**Acceptance criteria**
- Test passes in CI and asserts `onboarding_completed_at` is set at the end.
**Dependencies:** `P2-ONBOARD-11`
**Size:** M

#### `P7-TEST-05` — UI test: open paywall and restore purchases
Scope: Write the UI test from spec §22's required list, covering paywall presentation and the restore-purchases action.
**Acceptance criteria**
- Test passes in CI against the sandbox StoreKit configuration.
**Dependencies:** `P7-SUB-05`, `P7-SUB-06`
**Size:** M

#### `P7-TEST-06` — UI test: delete account end to end
Scope: Write the UI test from spec §22's required list, covering the in-app deletion flow through to sign-out, with a follow-up assertion (via a backend check, not just UI state) that data is actually removed.
**Acceptance criteria**
- Test asserts the user is signed out after deletion completes and a subsequent sign-in attempt with the same credential creates a new, empty account rather than restoring the deleted one.
**Dependencies:** `P7-PRIVACY-02`
**Size:** L

#### `P7-TEST-07` — Snapshot tests: light/dark, Dynamic Type, and empty/loading/error states
Scope: Write snapshot tests per spec §22 covering major screens (Home, Closet, Outfit detail, Kyra conversation, Studio, Paywall, Profile) in light and dark mode, at minimum and maximum Dynamic Type sizes, and in empty/loading/error states.
**Acceptance criteria**
- Each of the 7 listed screens has snapshot coverage for at least: light+dark default size, one large Dynamic Type size, and its empty state.
- Snapshot tests run in CI and fail on unintended visual regression.
**Dependencies:** `P7-DS-01`
**Size:** L

#### `P7-TEST-08` — Full Definition-of-Done acceptance run
Scope: Execute the complete spec §30 sequence (install, sign in, complete onboarding, receive Style DNA, scan 5 garments, correct metadata, receive 3 outfits, ask Kyra for an occasion, mark an outfit worn, paste a retailer link for a verdict, generate a visual estimate, subscribe and restore, view/delete memories, delete account) as one continuous manual or scripted acceptance session, in both light and dark mode, with VoiceOver, and under a throttled/degraded network profile.
**Acceptance criteria**
- All 14 spec §30 steps complete successfully in a single session without a crash or dead end.
- The full sequence is repeated a second time with VoiceOver enabled and a third time under degraded network conditions, per spec §30's explicit "must work" conditions.
- Results (pass/fail per step, per condition) are recorded as the release go/no-go artifact.
**Dependencies:** essentially every ticket in Phases 1–7
**Size:** XL

---

## Ticket count summary

| Phase | Tickets |
|---|---|
| Phase 1 — Foundation | 25 |
| Phase 2 — Identity | 17 |
| Phase 3 — Closet | 27 |
| Phase 4 — Outfit intelligence | 26 |
| Phase 5 — Kyra | 22 |
| Phase 6 — Studio and commerce | 25 |
| Phase 7 — Monetization and hardening | 36 |
| **Total** | **178** |

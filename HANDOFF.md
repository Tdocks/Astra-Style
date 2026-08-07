# Astra Style — Handoff

**For:** an AI builder picking this codebase up cold (Claude Code on the owner's Mac, or a cloud agent).
**Written:** 2026-08-01, against `main` at `86edb74` (merge of PR #12 — Phase 3 exit for TestFlight).
**Status at handoff:** 178 tickets tracked — **45 Done, 52 Partial, 81 Not started** (machine-checked by `scripts/check_progress.py`).

### ▶ Do this next (owner asked Claude on the Mac to own it)

**Stop. Open [`START_HERE.md`](START_HERE.md) at the repo root and follow it.**

That file is the complete TestFlight checklist (Archive → App Store Connect →
internal group → smoke). Same content is mirrored in **§12.0** below and
`docs/12-testflight-cut.md`. Cloud / Linux agents cannot codesign — this is
Mac-only. Do **not** start by investigating commit `cc7923cf` ("Pre-build
groundwork…"); that is an older ancestor, already merged, not unfinished work
sitting on top of this handoff.

---

## 0. Read this part even if you read nothing else

Six things will save you the most time, in order.

1. **`CLAUDE.md` at the repo root is binding, not background.** It opens by saying so. Read it before you write a line. Everything in this handoff is downstream of it.

2. **`docs/00-master-spec.md` is the source of truth, and the code is not.** CLAUDE.md states it plainly: *"If the spec and the code disagree, the spec wins and the code is a bug."* Do not treat existing code as de facto correct.

3. **`docs/03-progress.md` is the only trustworthy answer to "what actually works."** It is machine-checked by `scripts/check_progress.py` in CI. Every module `README.md` in this repo is hand-written prose and **several are stale in both directions** — the Closet README undersells what shipped, the Scanner README oversells it. Trust `docs/03-progress.md` and the code; treat READMEs as intent, not status.

4. **Six checkers and a warning gate will reject your work before a human sees it.** `swiftlint --strict` (every warning is an error), plus `check_ui_conventions.py`, `check_contrast.py`, `check_column_drift.py`, `check_schema_drift.py`, `check_progress.py`. Then a CI step greps the build log for `warning:` under `ios/AstraStyle/`. **`BUILD SUCCEEDED` does not mean the build passed** — `xcodebuild` exits 0 with warnings. Run the grep yourself.

5. **The governing content rule is: _absent is honest; a confounded reading is not._** This codebase would rather show a gap than a plausible-looking number nobody measured. It shows up everywhere — the Closet metrics row ships five of six §6.14 metrics because versatility's inputs are Phase 4; the item-detail screen omits two §6.15 fields because no column exists for them; the quiz's silhouette axis is permanently low-confidence because only one comparison pair exists. **Do not "fill in" one of these gaps with a substitute.** If you can't measure it, say so in the row and leave it out.

6. **The commit message is part of the deliverable.** Commits here are long, structured, and self-certifying: they name the tickets touched and their status delta, explain *why* with measured numbers, and close with a verification line (`swiftlint --strict clean (262 files), all six checkers pass, zero warnings under ios/AstraStyle/, 525 unit tests in 67 suites passing`). `docs/03-progress.md` is updated **in the same commit** as the code it describes.

**Current working convention (as of 2026-08-01 evening):** prefer feature branches `cursor/<descriptive-name>-****` and draft PRs into `main` (PRs `#9`–`#12` landed the Phase 3 exit). Direct-to-`main` commits still happen for tiny doc fixes; do not invent a new workflow. Conventional commits (`feat`/`fix`/`chore`/`docs`/`test`). Update `docs/03-progress.md` **in the same commit** as status-changing code.

---

## 1. What the product is

**Astra Style** is a premium iOS personal stylist for men, with an AI companion named **Kyra**. Native SwiftUI, Swift 6, iOS 18 deployment target. Backend is Supabase (Postgres 17, Auth, Storage, pgvector, Deno Edge Functions), project ref `anutsdzbxycaavmmkewo`.

From CLAUDE.md: *"The core moat is the Wardrobe Graph... The backend is Supabase, and the app talks only to Astra's own Edge Functions, never directly to an AI provider."*

The product surfaces, per the spec's section numbers (which you will see cited constantly in code comments):

| § | Surface | Build state |
|---|---|---|
| §5.1 / §6.2–6.10 | Onboarding → Style DNA | **Most complete flow in the app** |
| §6.11 | Home / Daily Brief | Complete; the reference implementation |
| §6.14–6.15 | Closet overview + item detail | Complete enough to use end to end |
| §6.16 | Scanner (camera → analysis → review → save → unlock report) | **Usable single-item loop on `main`** (capture/import, device hints, upload, analyze, editable review, offline queue, unlock count). Batch / receipt / mirror / server cutout still Partial. |
| §6.17+ | Outfits, Kyra, Studio, Discover, Shopping, Subscription | Mostly README-only shells; outfit/Kyra data layer Partial in places — do not assume screens exist. |

`Features/Scanner/README.md` may still lag the code; trust `docs/03-progress.md` for ticket status.

---

## 2. Repo map

```
astra/
  CLAUDE.md              Binding conventions. Read first.
  HANDOFF.md             This file.
  docs/                  00-master-spec (canonical) + 16 implementation docs + adr/0001–0013
  ios/
    project.yml          XcodeGen source of truth. The .xcodeproj is generated & gitignored.
    Config/              Base.xcconfig (committed), Secrets.xcconfig (gitignored, you must create it)
    AstraStyle/
      App/               AppContainer, AppRouter, RootView, MainTabView, AstraStyleApp
      Core/              Analytics, Auth, DesignSystem, Mocks, Networking, Persistence, Utilities
      Domain/            Models (pure value types), Repositories (protocols), Services
      Features/          One dir per product surface (see §7)
      Resources/         Info.plist source, entitlements, QuizImagery
      Tests/UnitTests/   Swift Testing
      Tests/UITests/     XCUITest
  supabase/
    migrations/          21 files, append-only, applied in timestamp order
    functions/           _shared/ (library) + outfits/, profile/, style-dna/ (3 of 12 slugs exist)
    tests/               Plain-SQL RLS isolation suite
    seed/                25-item wardrobe fixture
  scripts/               6 Python checkers + 6 shell scripts + 3 imagery generators
  brand/                 Source assets, incl. full-res quiz-imagery PNGs
  legal/                 4 drafted, unpublished HTML documents
  .github/workflows/     ios, schema-drift, edge-functions, progress, rls-tests
```

**Never hand-edit `ios/AstraStyle.xcodeproj`.** It is generated from `ios/project.yml` by XcodeGen and is gitignored (ADR 0008). New files under `ios/AstraStyle/` are picked up by a recursive glob, so adding a file needs no project edit — but adding a *directory* still requires re-running `xcodegen generate` before the build sees it.

---

## 3. The rules that will reject your work

### 3.1 CLAUDE.md, condensed

- **Swift 6 strict concurrency is on.** *"No reaching for `@unchecked Sendable` or `@preconcurrency` to silence a warning you haven't actually reasoned through."*
- **View models are `@Observable`, not `ObservableObject`/Combine** (ADR 0006).
- **`@MainActor` only on view models.** *"Don't mark a whole repository `@MainActor` just to make the compiler stop complaining; isolate correctly instead."*
- **No force unwraps, no `try!`, no `as!`** — including in tests.
- **No network calls in views.** *"A `URLSession` call, a Supabase client call, or an Edge Function invocation directly inside a `View`'s body or a `.task {}` block bypassing the view model layer is a structural violation, not a style nit."*
- **Never hardcode a colour, font, spacing value or corner radius.** Use the `Astra*` tokens. *"If a value you need doesn't exist as a token yet, add it to the design system and reference it from there — don't inline it 'just this once.'"*
- **Every user-owned table needs RLS.** *"A new table without an RLS policy is not 'TODO later' — it does not ship."*
- **Migrations are append-only.** Once applied anywhere, never edited.
- **Service-role keys exist only in Edge Functions.** The app gets `SUPABASE_URL` and `SUPABASE_ANON_KEY`, nothing else.
- **Don't add a dependency without an ADR.** The only third-party SPM package is `supabase-swift` (from 2.20.0).
- **Don't change the compatibility scoring weights in code** — they are server-configurable by design (ADR 0003).
- **Don't put admin functionality in the iOS app** (§28).
- **Don't request a permission outside its triggering context** (§7).

### 3.2 The §22 acceptance bar, verbatim

> No placeholder lorem ipsum. No dead buttons. No hard-coded user name. No exposed API secrets. No unhandled network failure. No required permission requested before context.

"No dead buttons" is enforced literally and repeatedly. Concrete examples already in the codebase: the Closet had **no filter button at all** until the filter panel was real; the welcome screen's legal links are a `Button` showing an honest "not published yet" notice rather than a `Link` to a dead URL; `ClosetViewModel.emptyReason(for:)` exists specifically so no recovery control is offered that cannot recover anything.

### 3.3 `scripts/check_ui_conventions.py` — three rules

Scans every `.swift` under `ios/AstraStyle` except `Tests/`.

1. **No "AI sparkle."** Regex `\bsparkles?\b|wand\.and\.(?:stars|rays)`, case-insensitive, **matched anywhere on a line including comments**. *"Astra Style is a stylist, not a magic trick."* Kyra's mark is `AstraMonogram`.
2. **No internal ticket IDs in user-facing strings.** Regex `"[^"\n]*\bP\d-[A-Z]{2,}[^"\n]*"`. Lines starting `//` are exempt for this rule only. This rule exists because a Closet placeholder once shipped that exact string.
3. **The garment is the subject, never the body.** `flatter(ing|s|ed)` is **banned outright** as *"a euphemism for concealment."* Also banned: `your (build|body type|body shape|figure|frame)`, `for (someone|a man|men) your (size|build|height|shape)`, `despite your`, `(hide|hides|hiding|conceal|conceals|disguise|disguises) your`, `slimming`, `makes you look (taller|slimmer|thinner|bigger)`. **Checked in comments too** — *"a doc comment that models the wrong phrasing is a template the next person copies."* Say what the garment does: balances, lengthens, defines, softens. (Ref `docs/14-frame-fit.md` §4.)

Opt-out marker: a trailing `ui-conventions:allow` on the line. Its only legitimate use is a comment that must quote a banned phrase to explain the rule.

Rules 1 and 2 are mirrored as SwiftLint `custom_rules` (severity `error`, `match_kinds: [string]`) so they also fail live in Xcode. **Rule 3 has no SwiftLint mirror** — it only fires in CI.

### 3.4 The other checkers

**`check_contrast.py`** parses hex values straight out of `AstraColor.swift` (never a duplicated table) and checks a curated pair list in both appearances against WCAG. The rule it encodes: **`accentChampagneAccessible` for gold TEXT (4.5:1); plain `accentChampagne` for fills, borders and icons only (3.0:1).** In light mode the plain token is ~2.7:1 — it failed on the welcome screen's legal links once already. Adding a token means adding its rendered pair to `PAIRS`, or an `EXEMPTIONS` entry with a written justification.

**`check_column_drift.py`** compares Swift `CodingKeys` against real Postgres columns **in both directions**, parsing `CREATE TABLE` plus every later `ALTER TABLE ADD/DROP/RENAME`. It exists because `BodyProfile` once had coding keys (`height_value`) that didn't match its columns (`height_value_cm`) — and because every property was Optional, the synthesized decoder silently decoded `nil` for every user, forever, with no error. **A new persisted model must be registered in `MODEL_TABLES`** and must have explicit snake_case `CodingKeys`. Deliberately-unmapped columns/keys go in `ALLOWED_UNMAPPED_COLUMNS` / `ALLOWED_EXTRA_KEYS` **with a written reason**.

**`check_schema_drift.py`** compares Swift `enum X: String` raw values against Postgres `create type ... as enum`. **Every Swift enum must be explicitly classified** in `ENUM_MAPPING` or `NO_DB_COUNTERPART` — *an unclassified enum is a hard error.* Mapping is explicit, not name-derived, because two of the five real historical bugs were cases a naive lowercase auto-matcher would have missed (`ItemCondition → condition`, not `item_condition`; `ItemFit → fit_preference`). If your file isn't `Enums.swift`, add it to `EXTRA_SWIFT_FILES`. Its own workflow calls it *"the single highest-value check in this repo's CI."*

**`check_progress.py`** enforces six invariants on `docs/03-progress.md`: every ticket appears exactly once, no invented IDs, statuses drawn from `{Done, Partial, Not started, Unverifiable}`, summary counts match the rows *and* the phase rows sum to the total, `requiredNow` slugs have real function directories, and an audit stamp exists. **Crucially: only `Done` rows must cite files that exist** — *"a `Partial` or `Not started` row earns its status precisely BY citing things that are absent."*

**`resolve_ios_simulator.py`** prints one UDID: the newest installed iOS runtime's alphabetically-first iPhone. It exists because a hardcoded `name=iPhone 16` broke when the runner moved to macos-26. Use `-destination "id=$(python3 scripts/resolve_ios_simulator.py)"`, never a device name.

### 3.5 CI

Five workflows. **`ios.yml`** is the one that matters most:

- Triggers on `paths: ["ios/**", ".github/workflows/ios.yml"]` — **a PR touching only `supabase/`, `docs/` or `scripts/` does not run it at all.**
- `macos-26`, Xcode pinned **26.6**, 45-minute timeout.
- Order: SwiftLint `--strict` → the four Python checkers → *then* Xcode install → XcodeGen → build → **warning gate** → test. The checkers run before Xcode deliberately: each is seconds, so a violation fails in under a minute rather than after a ten-minute build.
- Writes `Config/Secrets.xcconfig` from **real repository secrets**, not placeholders — an earlier placeholder version made every UI test crash at launch with an opaque `preconditionFailure`.
- **The warning gate** is `grep -E '^/.*ios/AstraStyle/.*warning:' "$RUNNER_TEMP/xcodebuild-build.log"`. It is scoped to first-party code so SwiftPM dependency warnings don't block. `SWIFT_TREAT_WARNINGS_AS_ERRORS` is deliberately *not* set — several dependencies compile with `-suppress-warnings`, and combining the two produces a hard compiler conflict.

Others: `schema-drift.yml` (ubuntu, narrow path filter), `edge-functions.yml` (Deno 2.9.4 pinned), `progress.yml` (**no path filter at all**, deliberately — a `Done` row's cited file can be renamed by any commit), `rls-tests.yml` (real `pgvector/pgvector:pg16` service container).

**Known CI gaps, all real:**
- `edge-functions.yml` runs against `_shared/` and `outfits/` **only**. `profile/` and `style-dna/` are in `deno.json`'s task lists but **not in the workflow** — a regression in either will not be caught.
- `schema-drift.yml`'s path filter doesn't include the `EXTRA_SWIFT_FILES`/`EXTRA_SQL_FILES` the script itself reads.
- No workflow covers `design/`.
- ADR 0012 describes a scheduled UI-test job; no such workflow file exists. In practice `ios.yml` runs the full scheme including UI tests on every triggering PR, which is *stricter* than the ADR describes.

### 3.6 `.swiftlint.yml`

`line_length` 220/320, `file_length` 560/1000, `type_body_length` 280/400 — every threshold set with headroom above a **measured** real max, with the measurement recorded in the file. Opt-in: `force_unwrapping`, `force_try`, `implicitly_unwrapped_optional`, `contains_over_first_not_nil`, `empty_count`, `closure_spacing`, `toggle_bool`, `unneeded_parentheses_in_closure_argument`, `redundant_type_annotation`, `first_where`. `nesting.type_level` is loosened to 2 with a stated reason (the compiler *requires* `CodingKeys` nested inside its type).

`todo` is **disabled on purpose** — this codebase has zero TODO comments by convention and tracks gaps as named disabled tests instead (see §9.4).

The file's own header states the discipline in one sentence: *"if a threshold changes, change it because the rule is wrong for this codebase and say why, not because a violation was inconvenient."*

---

## 4. iOS architecture

### 4.1 Layering

```
Features/*  →  Domain/Repositories + Domain/Models + Domain/Services + Core/DesignSystem + Core/Utilities
App/        →  the ONLY place that imports both Domain protocols and Core/Networking/Live, Core/Persistence, Core/Mocks
Core/Networking/Live/*, Core/Persistence/*  →  import Supabase / SwiftData; conform to Domain protocols
Domain/*    →  pure Swift + Foundation. No SwiftUI, no SwiftData, no Supabase. Value types only.
```

There is one app target and no SPM-local-package boundary, so this is enforced by convention, CLAUDE.md and review — not by the build system. Nothing in `Features/` imports a concrete `Live*`/`Mock*` type.

**The AI seam is server-side, always.** Spec §8's five provider protocols (`StylistReasoningProvider`, `VisionAnalysisProvider`, `ImageGenerationProvider`, `EmbeddingProvider`, `ProductExtractionProvider`) are **deliberately absent from `ios/` entirely.** ADR 0004 decision 3: the client never holds a provider key and never constructs a request to a model vendor. The client's seam onto AI is always a repository method in front of an Edge Function.

### 4.2 The canonical feature module

```
Features/<Name>/
  README.md          Required. What it owns, governing spec sections, what exists to build against.
  Components/        Small, independently-previewable visual pieces
  Models/            Feature-local view-state/DTO types (not Domain models)
  Routing/           <Name>DestinationView.swift — resolves the tab's Route enum to a screen
  Services/          Feature-local orchestration protocols (e.g. HomeBriefProviding)
  ViewModels/        @MainActor @Observable classes, one per screen/flow
  Views/             SwiftUI Views driven entirely by a ViewModel's `state`
```

**`Features/Home/` is the designated reference implementation.** `HomeViewModel.swift`'s header says so verbatim:

> "This is the reference implementation the rest of the feature modules (P3-CLOSET, P4-OUTFIT, P5-KYRA, ...) are expected to pattern their own view models after: an explicit `ViewState` enum covering loading / loaded / empty / error, a separate `isOffline` flag (offline is orthogonal to the four content states — you can be offline *and* showing cached content), and no view-layer type ever touching a repository directly."

**`Features/Slice/` is explicitly NOT a pattern to copy.** Its README: *"This module is throwaway... Do not treat `SliceView`/`SliceViewModel` as a reference implementation to copy wholesale into a real feature module."* It exists to prove four architectural risks end-to-end against a real Supabase project, is gated behind `ASTRA_VERTICAL_SLICE` in `#if DEBUG`, cannot activate in Release, and is expected to be deleted once Phases 1–4 land.

### 4.3 The view-model pattern

```swift
@MainActor
@Observable
public final class XViewModel {
    public enum ViewState: Equatable {
        case loading
        case loaded(T)
        case empty(T)          // carries the same payload — never bare
        case failed(AstraError)
        public static func == (lhs: ViewState, rhs: ViewState) -> Bool { ... }  // hand-written, identity-based
    }

    public private(set) var state: ViewState = .loading
    public private(set) var isOffline = false      // orthogonal to state, always outside the enum

    public private(set) var isMarkingWorn = false  // one in-flight flag per action

    public func markWorn() async {
        guard !isMarkingWorn else { return }
        isMarkingWorn = true
        defer { isMarkingWorn = false }
        ...
    }
}
```

Four conventions worth internalising:

- **`Equatable` is hand-written and identity-based**, not synthesized. The question it answers is "is the screen showing the same thing", not "is the content byte-identical" — `@Observable` field tracking already handles repaints.
- **`.empty` carries the payload**, so an empty state can still greet the user by name and render header context.
- **`isOffline` is a separate flag**, always. Offline-with-cached-content is a valid combined state that an enum can't express without doubling every case.
- **Guard-set-defer, one flag per action.** Prevents a double-tap re-entering *that* action without disabling the whole screen. The Closet runs five across its two screens: `ClosetViewModel`'s `isRefreshing` and `isResolvingImages`, plus `ClosetItemDetailViewModel`'s `isMarkingWorn`, `isUpdatingLaundryState` and `isArchiving`.

Dependencies are injected as **protocols only**, with defaulted `networkMonitor: NetworkReachabilityMonitoring = SystemNetworkReachabilityMonitor()` and `analyticsClient: AnalyticsClient = NoOpAnalyticsClient()`.

### 4.4 Concurrency posture — the most important non-obvious decision

`ios/project.yml` sets `SWIFT_VERSION: 6.0`, `SWIFT_STRICT_CONCURRENCY: complete`, `SWIFT_APPROACHABLE_CONCURRENCY: YES`, `IPHONEOS_DEPLOYMENT_TARGET: 18.0`.

It **deliberately does not set `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`**. From the file, verbatim:

> "This codebase is built the other way around: Domain models are plain Sendable value types, repositories are Sendable and run off the main actor, and only view models are explicitly `@MainActor`. Defaulting every type to MainActor contradicts that and made ~25 call sites fail with 'main actor-isolated initializer cannot be called from outside of the actor'. The default (nonisolated) is correct here."

So: **types are nonisolated by default.** Repositories do I/O off the main actor; view models hop to main only for the final state update.

**Every `@unchecked Sendable` in the codebase follows one of exactly two shapes** — either every stored property is a `let` set once at `init`, or the one mutable field is guarded by an explicit `NSLock`. None are bare suppressions. The full list: `LiveAnalyticsClient`, `AppleSignInCoordinator` (NSLock on `continuation`), `AstraAPIClient` + its private `TokenProviderBox` (NSLock), `AstraImageCache` (wraps `NSCache`), all eight `Live*Repository` types, `LiveWeatherService`, `LiveCalendarService`, and test-only `MockURLProtocol`.

**The `CGImage` trick, worth copying.** `Features/Scanner/Services/CaptureQuality.swift` needs to accept a non-`Sendable` `CGImage` from an `AVCaptureVideoDataOutput` delegate queue. Its answer: **every entry point is synchronous and nonisolated.** A sync nonisolated call runs in the caller's isolation domain, so the image never crosses a boundary and no `@unchecked Sendable` is needed anywhere. Making anything `async` would push it to the generic executor and force the argument to be `Sendable`. If you build the camera layer, preserve this.

### 4.5 Dependency injection

`App/AppContainer.swift` — a `@MainActor @Observable final class`, no DI framework (ADR 0007). It exposes: `sessionStore`, `authRepository`, `profileRepository`, `closetRepository`, `closetImageURLResolver`, `outfitRepository`, `kyraRepository`, `studioRepository`, `shoppingRepository`, `subscriptionRepository`, `weatherService`, `calendarService`, `apiClient`, `analyticsClient`, `offlineMutationQueue`, `settings`.

- **`.live()`** wires every `Live*` type against one shared `AstraAPIClient`. The model container is `(try? AstraModelContainer.live()) ?? AstraModelContainer.preview()` — a corrupt store degrades to "no caching this session" rather than crashing.
- **`.preview()`** wires every `Mock*` type. It passes `SessionStore(apiClient: .previewClient, supabase: ...previewClient)` **explicitly** rather than relying on the default, because the default evaluates `AstraEnvironment.current`, which `preconditionFailure`s in a process with no Info.plist secrets.

**View models are constructed in `MainTabView`** (or by a parent view model's factory, e.g. `ClosetViewModel.makeAddItemViewModel()`). A child `View` must never reach into `AppContainer` to build its own.

**Launch flags** (`Core/Utilities/AstraFeatureFlags.swift`), all `#if DEBUG` except the first:

| Flag | Effect |
|---|---|
| `-astra-reset-state` | Clears the persisted session at launch. Every UI suite sets it. Not DEBUG-gated. |
| `-astra-skip-onboarding` | Routes straight to the tab shell. |
| `-astra-mock-backend` | Runs against `AppContainer.preview()`, already signed in to a throwaway session. **This is the lever for testing anything backend-dependent**, and since ADR 0014 it is also the only account-free way into onboarding for a UI test. |
| `-astra-theme light\|dark\|system` | Overrides the stored theme (needed because the app's `.preferredColorScheme` beats the simulator's `-UIUserInterfaceStyle`). |
| env `ASTRA_VERTICAL_SLICE=1` | Boots `SliceRootView()` instead of the app. |

### 4.6 Navigation

`AppRouteState`: `.launching`, `.signedOut`, `.onboarding`, `.main`. Five tabs: `.home`, `.closet`, `.studio`, `.discover`, `.profile`.

Each tab owns its own `NavigationStack(path: $router.<tab>Path)` with a `<Tab>DestinationView`, which is what makes tab state survive switching. `AppModalRoute` is orthogonal and singular (`presentedModal: AppModalRoute?`), presented in `MainTabView` via `.sheet(item:)`.

`routeState`'s `didSet` auto-calls `resetForSignOut()` on any transition **to** `.signedOut` — deliberately tied to the state transition, not each call site, because there are several ways to become signed out (manual, revoked refresh token, account deletion) and only a `didSet` covers all of them.

**The `@Bindable` gotcha**, repeated verbatim above every tab in `MainTabView`:

> "`@Bindable` must be re-established in each of these: the one in `body` is a local binding and does not carry into other members, so `$router` would otherwise be out of scope."

Every `@ViewBuilder private var xTab` is a separate scope and must re-declare `@Bindable var router = router`.

### 4.7 Design system

`Core/DesignSystem/` — `Components/`, `Tokens/`, `Previews/`.

**Components** (exact initializers):

```swift
AstraButton(title:isLoading:action:)                              // + .astraPrimary/.astraSecondary/.astraTertiary styles
AstraCard(padding: = AstraSpacing.lg, @ViewBuilder content:)
AstraChip(_ title:systemImage:isSelected:action:)
AstraTextField(_ label:text:placeholder:footnote:errorText:isRequired:keyboardType:textContentType:submitLabel:autocapitalization:axis:)
AstraDecimalField(_ label:value:placeholder:footnote:errorText:isRequired:currencyCode:)
AstraSectionHeader(title:eyebrow:actionTitle:action:)
AstraScoreMeter(score:title:style:)                               // Style: .compact | .hero
AstraWrappingHStack(spacing:lineSpacing:)                         // a Layout, for chip clouds
AstraRemoteImage(url:aspectRatio:thumbnail:cornerRadius:accessibilityDescription:)
AstraMarble(intensity:)                                           // + .astraMarbleBackground(scrimmed:) / .astraOnMarble()
AstraMonogram(size:tint:)  /  AstraWordmark(showsTagline:)
GeneratedImageBadge()  /  GeneratedImageContainer(accessibilityDescription:content:)
```

Four of these carry a decision worth knowing:

- **`AstraDecimalField` is a separate type, not a `format:` parameter on `AstraTextField`.** SwiftUI's `TextField(_:value:format:)` cannot express "empty means nil" — clearing the field silently keeps the old `Decimal`. `pricePaid == nil` ("he didn't say") must stay distinguishable from `pricePaid == 0` ("he paid nothing") for cost-per-wear maths.
- **`AstraRemoteImage` is deliberately not `AsyncImage`.** `AsyncImage` never exposes `Data`, so it cannot route through `ImageDownsampling`, and §20 requires the closet grid to hit 60fps without full-resolution decodes. It has **no retry** (a grid that retries per-tile causes N concurrent retry storms) and renders "no image" and "failed to load" **identically** — no broken-image glyph in a premium app. Decoded images are cached in a process-wide `NSCache` keyed on **URL host+path, not `absoluteString`**, because signed URLs re-sign hourly and an `absoluteString` key would throw the whole grid's cache away on every refresh.
- **`AstraWrappingHStack` exists instead of a horizontal `ScrollView` of chips** because a scroller has no indicator and silently hides content past the fold at large Dynamic Type.
- **`GeneratedImageContainer` is "the only sanctioned way" to present Style Studio output** — it pairs the mandatory disclosure badge with a required alt description so neither can be forgotten.

**Tokens:**

| Token type | Members |
|---|---|
| `AstraColor` | `backgroundPrimary`, `backgroundSecondary`, `surfaceElevated`, `surfaceMarble`, `textPrimary`, `textSecondary`, `textMuted`, `textOnAccent`, `accentChampagne`, `accentChampagnePressed`, `accentChampagneAccessible`, `divider`, `successOlive`, `warningAmber`, `destructive` |
| `AstraSpacing` | `unit`/`xxs` 4, `xs` 8, `sm` 12, `md` 16, `lg`/`pagePadding` 20, `xl` 24, `xxl` 32, `xxxl` 40, + `cardRadius`/`buttonRadius`/`minTapTarget` aliases |
| `AstraRadius` | `card` 18, `button` 14, `chip` `.infinity`, `small` 8 |
| `AstraSize` | `minTapTarget` 44, `referencePreviewHeight` 220 |
| `AstraTypography` | `displayXL` 42, `displayL` 34, `title1` 28, `title2` 22, `headline` 17, `body` 16, `callout` 15, `caption` 12, `micro` 10 — serif for display/title, `@ScaledMetric`-driven |
| `AstraIcon` | `disclosure` 13, `inline` 16, `control` 20, `emphasis` 24, `feature` 32, `display` 40 |
| `AstraMotion` | `standard` (220ms), `outfitPaging` (spring), `breathing` (2.4s, Kyra's orb), `aware(_:reduceMotion:)` |
| `AstraHaptics` | `selection()` (outfit swaps), `success()` (completed scan), `warning()` (precedes destructive) |

Applied via `.astraText(_:)`, `.astraIcon(_:weight:)`, `.astraAnimation(_:value:)`. **Never `Font.system(size:)` directly** — it doesn't scale with Dynamic Type; the tokens route through `@ScaledMetric`.

**`AstraGarmentColor` is the one non-semantic token file.** It maps colour *words* (server content: "tobacco brown") to swatches. `swatch(for name: String) -> AstraSwatch` where `hex: UInt32?`. Resolution is exact match, then **last-word fallback** (English colour names are head-final). An unrecognised word returns `hex == nil` — **render the name alone, never a guessed rectangle.** Swatches are deliberately **not** appearance-paired (a swatch is a picture of cloth, not a UI surface) and every one must be stroked with `AstraColor.divider` so a bone or white chip has an edge in light mode.

### 4.8 Errors

```swift
public struct AstraError: Error, Sendable, Equatable, LocalizedError {
    public enum Category { case network, auth, validation, server, provider, rateLimited, cancelled, unimplemented, unknown }
    public let category: Category
    public let message: String            // ALWAYS user-facing copy
    public let underlyingStatusCode: Int?
    public let requestID: String?
    public var isRetryable: Bool          // network, server, provider, rateLimited
}
```

**`message` is user-facing copy, always.** Render it directly; never wrap it. Developer-facing detail belongs in a comment at the throw site.

**`.unimplemented` is deliberately distinct from `.server`:** *"a `.server` failure is a runtime problem that might not happen next time; this one is a fact about the build — retrying will never help, and the UI should degrade (hide the module, disable the control) rather than offer a retry button that cannot succeed."* It is not retryable, which is what stops the Closet growing a dead "Try Again" button.

Two other error types cross boundaries: **`FreeTierClosetError.capReached(limit:)`** (a distinct type, not an `AstraError` category, so call sites can catch the cap without string-matching a message) and **`OfflineMutationNotHandled`** (thrown by a drain handler that doesn't own the mutation type it was handed — means "skip, don't fail, don't consume").

### 4.9 The API client

`Core/Networking/AstraAPIClient.swift`. Nothing else may import `URLSession` for first-party API calls. (`Live*Repository` types *do* talk to Postgrest/Storage directly via the Supabase SDK for simple CRUD — the rule covers the 16 orchestration/AI endpoints in `AstraEndpoint`. `AstraRemoteImage.fetch` is the one other sanctioned direct `URLSession` user, for already-signed image bytes.)

- **Request envelope:** `{request_id, client_version, body}`. `clientVersion` is `"ios/<CFBundleShortVersionString>"`.
- **Headers:** `Content-Type`, `X-Request-Id`, `apikey: <anon>`, `Authorization: Bearer <access token>` (or the anon key for the one unauthenticated endpoint).
- **Response envelope:** `{data, error, request_id}`. **A 2xx carrying `error != null`, or a 2xx with `data == null`, is a failure.**
- **Status mapping:** 401/403 → `.auth` (envelope ignored); **404 → `.unimplemented`** (see below); 400/422 → prefers the envelope; 429 → `.rateLimited`; 5xx → prefers the envelope; anything else → `default:`, which prefers the envelope and falls back to `"Unexpected response (<code>)."`
- **404 is its own branch since 2026-08-06**, because it has exactly two causes and neither is transient: an undeployed slug (Supabase's gateway answers in its *own* shape, `{"code":"NOT_FOUND","message":...}` — note `code` is a **string**, and that body decodes "successfully" as `AstraResponseEnvelope` because every field of the envelope is optional, which is how the real message used to vanish), or a deployed function's router rejecting a sub-path (ADR 0013's envelope). Both are facts about the build, so both map to `.unimplemented`, which is **not retryable** — that is what stops the UI offering a retry that cannot work, and stops the client burning three backoff attempts on a permanently-404ing URL. The endpoint path and the server's own words go to `Logger(subsystem: "app.astrastyle", category: "networking")`, correlated by `X-Request-Id`.
- **Retry:** `AstraRetryPolicy.default = (maxAttempts: 3, baseDelay: 0.5, maxDelay: 8.0)`, exponential with up to 20% jitter, applied only when `isRetryable`.

### 4.10 Persistence and offline

SwiftData schema: `PersistedClosetItem`, `PersistedOutfit`, `PersistedDailyBrief`, `PersistedOfflineMutation`.

**`PersistedClosetItem` now backs the signed-in read cache only** (`SwiftDataClosetItemCache`); it used to back guest storage as well, which is gone. The "no local-cache fallback" this paragraph used to describe is also gone — `LiveClosetRepository.fetchItems` write-throughs on success and serves cached rows when the network fetch fails, which is what moved P3-CLOSET-02 to Done.

**`OfflineMutationQueue`** is FIFO, stops at the first genuine failure (preserving order, incrementing `attemptCount`), and treats `OfflineMutationNotHandled` as "skip, leave queued, don't count an attempt" since one queue serves several repositories. Its limitations, all stated in the codebase:

1. Only `LiveClosetRepository` drains it. **`.outfit`/`.outfitWear` mutations accumulate and are never replayed.**
2. Only `createItem`/`updateItem` queue on failure. `archiveItem`, `markWorn` and `updateLaundryState` surface the error directly, because the queue's payload (an encoded `ClosetItem`) can't represent an id-only or read-modify-write operation.
3. Replay is triggered by the *next successful call*, not by a reachability event — so "reconnecting triggers replay" is met only in effect.

### 4.11 Copy, localisation, accessibility

- **Every user-facing string is `String(localized: "...", comment: "...")`.** `SWIFT_EMIT_LOC_STRINGS: YES`; the literal is both the extraction key and the base value, matching Xcode's `.xcstrings` workflow.
- **Prose is British English** ("colour", "trousers", "autumn", "£"), while Swift API surface is inescapably American (`Color`, `AstraColor`). This is emergent authorial convention, not a documented rule — **follow the surrounding file**.
- State is **never carried by colour alone** — selected chips change fill *and* outline *and* gain a checkmark; score tiers pair a colour with a text descriptor.
- Decorative glyphs get `.accessibilityHidden(true)`; meaning lives in adjacent text.
- **Placeholder text is never a field's accessibility label** — it disappears the moment the user types, leaving an unlabelled field mid-edit.
- Required fields are marked with the word **"Required"**, never an asterisk (VoiceOver reads "star"; a 12pt asterisk is invisible).
- `Link` surfaces as `.button` in the accessibility tree, not `.link` — which drives `Button`-vs-`Link` choices where UI tests need to query it.

---

## 5. Backend

### 5.1 Schema shape

21 migrations under `supabase/migrations/`, applied in timestamp order, **every one written idempotent** (`create ... if not exists`, `do $$ ... exception when duplicate_object`, `pg_policies` existence guards).

Tables: `profiles`, `style_profiles`, `body_profiles`, `lifestyle_profiles`, `closet_items`, `closet_item_images`, `outfits`, `outfit_items`, `outfit_wears`, `kyra_threads`, `kyra_messages`, `style_feedback`, `style_memories`, `product_candidates`, `user_product_evaluations`, `occasions`, `daily_briefs`, `studio_generations`, `subscriptions`, `account_deletions`. 24+ enum types. Extensions: `pgcrypto`, `vector` (pgvector), `pg_trgm`, `unaccent`, all in a dedicated `extensions` schema.

**Conventions that are project-wide, stated in migration 3's header:**
- Any `*_score` column is `smallint` 0–100.
- A probability/confidence is `numeric(3,2)` in [0,1].
- `outfit_wears.rating` (1–5 stars) is the one named exception.
- Canonical body measurements are **centimetres regardless of `profiles.units`**.

**Design decisions in the schema worth not undoing:**
- `profiles.id` **is** `auth.users.id`, not an independent uuid. Created by the `handle_new_user()` trigger on signup.
- `style_memories` has **no soft-delete column, by design** — §6.20/§29 require memory removal to be real deletion.
- `product_candidates` is a **shared catalogue with no `user_id`** and no per-user isolation; it has a read-only `using (true)` policy and no write policy at all (service-role only).
- `user_product_evaluations` deliberately has **no unique constraint** on `(user_id, product_candidate_id)` — an evaluation should be recomputed as the wardrobe changes; the latest is fetched by `order by created_at desc limit 1`.
- `style_feedback.target_id` is **deliberately polymorphic, not an FK** (Postgres has no polymorphic FK) — the app layer must validate it.
- `studio_generations.provider` is `text`, not an enum, because provider selection is server config (ADR 0004).
- `body_profiles.frame_*` columns are **server-derived, never user-entered**, computed by the `derive_frame_axes()` BEFORE trigger so iOS and Edge Functions can never disagree on the derivation.

Indexes worth knowing: partial btrees on `where archived_at is null`; unique partials (`one_primary_per_item`, `unique_closet_item_per_outfit`, `unique_calendar_event_per_user`); GIN `jsonb_path_ops` on the jsonb arrays; GIN **trigram** on `closet_items.name`/`brand` and `product_candidates.name`/`brand` (these back the search bars); **HNSW `vector_cosine_ops`** on the four 1536-dim embedding columns.

### 5.2 RLS

`ENABLE`d (not `FORCE`d — deliberately, so the migration role isn't also constrained) on every user-owned table. Sixteen "ordinary owned tables" get select/insert/update/delete generated by a `do $$` loop, each predicate `user_id = (select auth.uid())`.

**Note the subquery form.** `(select auth.uid())`, never bare `auth.uid()` — Postgres evaluates it once per statement as an InitPlan rather than once per row.

**Child-table ownership is enforced twice.** `closet_item_images`, `outfit_items` and `kyra_messages` carry a **denormalised `user_id`** set by a family of three near-identical BEFORE INSERT triggers (`set_user_id_from_closet_item`, `set_user_id_from_outfit`, `set_user_id_from_kyra_thread`). The critical detail: these are **plain `SECURITY INVOKER`**, so their internal `SELECT` against the parent is itself subject to the parent's RLS as the calling user. If a client inserts a child row against a parent owned by someone else, the lookup **cannot see the parent at all**, `NEW.user_id` stays null, and the trigger raises — *before* the table's own `WITH CHECK` even runs. Two independent layers. Verified in `supabase/tests/20_rls_isolation_tests.sql`.

`closet_item_images.user_id` therefore has no Swift property and is registered in `check_column_drift.py`'s `ALLOWED_UNMAPPED_COLUMNS` with the reason *"a client-writable user_id on a child row is an IDOR surface."*

### 5.3 Storage — and the trap

**One private bucket: `user-content`.** `public: false`, 25 MiB limit, MIME allowlist `image/jpeg|png|heic|heif|webp`. Path convention `users/{user_id}/closet/...`, `.../references/...`, `.../studio/...` — one bucket, feature subfolders.

All four `storage.objects` policies share one predicate:

```sql
bucket_id = 'user-content'
and (storage.foldername(name))[1] = 'users'
and (storage.foldername(name))[2] = (select auth.uid())::text
```

> ### ⚠️ THE UUID-CASING TRAP — read this before writing any storage path
>
> `uuid::text` in Postgres renders **lowercase**. Swift's `UUID.uuidString` renders **UPPERCASE**.
>
> A path built as `"users/\(userID.uuidString)/closet/..."` is well-formed, targets the right bucket, and is **rejected by RLS every single time** — silently, with no error naming the cause, because the object was never reachable by anyone including its own uploader.
>
> **Always `.lowercased()` a Swift UUID before it becomes a storage path segment.**
>
> It is documented in exactly two places, both client-side: `LiveClosetRepository.uploadCaptured()`, which calls it *"the most expensive kind of wrong, because it looks correct in the debugger,"* and `LiveProfileRepository.uploadReferenceImage()`, which notes the same reasoning *"cost a day the first time."* It is **not** documented in any migration, in `supabase/README.md`, or in ADR 0013 — so a third storage-path builder still has to rediscover it or read one of those two.

**A second bucket, `legal`, is public** (2 MiB, `text/html|plain|markdown` only, no image types so it can't drift into an asset host). It is currently **empty** — see §8.3.

**Storage policies are not covered by CI.** The RLS suite runs against a bare `pgvector/pgvector:pg16` container which has no `storage` schema. An upload-path RLS regression will not be caught by anything automated.

### 5.4 Edge Functions — ADR 0013 is the one to read

**The problem it records:** Supabase routes `/functions/v1/{slug}/{rest}` by the **first path segment only**. The vertical slice deployed a function named `outfits-generate` while the client built `/outfits/generate`. Every production call 404'd while every test stayed green:

```
POST /functions/v1/outfits-generate  ->  401   (function exists; correctly demands a JWT)
POST /functions/v1/outfits/generate  ->  404   (the URL the app actually builds)
```

**The decision:** §14's URL shapes are preserved verbatim; the deployment layout bends to the spec. Functions are **named after the first path segment** and group every endpoint sharing it, routing internally on the remainder via `_shared/routing.ts`. **Twelve functions serve sixteen endpoints.**

Named costs, accepted: grouped functions **share fate at runtime** (a crash-loop in one endpoint degrades every endpoint in its slug), share the in-memory rate limiter, and **deploy as a unit**.

**`_shared/routing.ts`** — `createRouter(slug, routes)` behaves, in order: (1) `OPTIONS` answered 204 for **any** path before route matching (a browser preflights the exact URL, and answering only known paths would make CORS failures indistinguishable from routing failures); (2) method+pattern match dispatches; (3) pattern matches but verb doesn't → **405**; (4) nothing matches → **404** in the standard envelope; (5) a handler that throws is caught and re-enveloped without leaking a stack trace. `resolveRoutePath` defensively strips `/functions/v1` and/or the slug so the router works under three different mount shapes.

**Which slugs exist:** `outfits/` (POST /generate built; /rank not), `profile/` (POST /complete-onboarding), `style-dna/` (POST /generate). **Nine do not exist at all:** `closet`, `daily-brief`, `kyra`, `products`, `studio`, `packing`, `subscriptions`, `app-store`, `account`.

**`outfits/` is the template.** Layout: `index.ts`, `handler.ts`, `handler_test.ts`, `schema.ts`, `schema_test.ts`, plus domain files each with their own `_test.ts`.

- `index.ts` reads env once at cold start, constructs the rate limiter, **constructs the provider ("THE PROVIDER SWAP HAPPENS HERE AND NOWHERE ELSE")**, builds a `createUserScopedClient` per request forwarding the caller's own `Authorization` header, and calls `Deno.serve(createRouter(slug, routes))`.
- `handler.ts` ordered responsibilities, deliberately cheapest-and-most-hostile-first: **validate JWT → rate limit (before the body is parsed, so a caller can't burn parse cost past the limiter) → parse envelope + validate schema → do work → log request id and latency on every path.**
- **The user id may originate nowhere but the JWT.** `authenticateRequest` calls `authClient.auth.getUser(token)` — a real round trip to GoTrue. JWT verification is deliberately not hand-rolled. Reads then rely on RLS, not on a `.eq("user_id", …)` filter; `outfits/index.ts` even `void userId`s the parameter with a comment explaining that filtering by it would change nothing.
- **None of the three existing functions ever constructs a service-role client.** `supabaseClient.ts`'s header: *"A function should reach for the service-role key ONLY when RLS cannot express what it needs."*

**Error envelope** (`_shared/errors.ts`):

```json
{ "data": <T>|null, "error": { "category": "...", "message": "..." }|null, "request_id": "..." }
```

`category` must be one of `network | auth | validation | provider | rate_limited`. **Anything else — including the literal `"server"` — silently maps to `.server` on the client**, because `AstraServerErrorPayload.asAstraError` switches on those five and defaults. Inventing a new category server-side without checking the Swift switch collapses quietly rather than failing loudly. `methodNotAllowed` is 405/`validation`; `notFound` is 404/`validation`.

**The rate limiter is not a security boundary.** `_shared/rateLimit.ts` is an in-memory, per-isolate fixed-window counter. Supabase can land one user's requests on different isolates, each with an empty `Map`, and every isolate recycle resets everyone to zero. This is stated three separate times (file header, README, ADR 0013's negatives) precisely so nobody mistakes green rate-limit tests for abuse resistance.

**Deno tests** use `@std/assert` and plain `Deno.test` — no network, no real Supabase, no real JWT signing. Every boundary is a hand-written mock. `outfits/handler_test.ts` is the template; **its most important test is the cross-user isolation one**: it sends User A's JWT with an attacker-supplied `user_id` in the body and asserts the repository was invoked with exactly the JWT-derived id and that no returned item belongs to User B.

### 5.5 The endpoint↔deployment contract

`AstraEndpoint.swift` enumerates all 16 endpoints. `EndpointDeploymentMappingTests.swift` (a **Swift** test in the iOS unit target, not a Deno test) makes three assertions:

1. Every endpoint path's first segment is in `expectedSlugs`. Coverage is compile-enforced by a non-`default` exhaustive switch — adding an `AstraEndpoint` case without updating `allEndpoints` fails to compile.
2. `expectedSlugs` equals the derived set **exactly, in both directions** — no endpoint with an unlisted slug, no listed slug no endpoint uses.
3. It walks `supabase/functions/` on disk: (a) every directory must be a slug some endpoint uses; (b) every slug in **`requiredNow: Set<String> = ["outfits", "profile", "style-dna"]`** must exist as a directory.

**When you add an endpoint:** name the directory after the first path segment; route internally via `_shared/routing.ts`; add the slug to `expectedSlugs` if genuinely new; add the case to `allEndpoints`; **and grow `requiredNow` by hand** — it does not update itself, and a new function is unguarded until you do.

### 5.6 Secrets and providers

**Standing rule: OpenAI only.** xAI, Gemini and Higgsfield are revoked or dropped. This has been verified across `docs/08`, `docs/09`, `docs/15`, `docs/16` and `supabase/README.md` — none names another vendor as active.

| Provider role | Decision | Where |
|---|---|---|
| Stylist reasoning | OpenAI GPT-5.6, two-tier — Luna default, Terra escalation, Sol as a narrow ceiling | `docs/08` §1.5 |
| Vision analysis | Apple Vision on-device **+** OpenAI GPT-5.6 Luna server-side; Terra only on low-confidence retry | `docs/08` §2.5 |
| Image generation | OpenAI direct. **Style Studio → `gpt-image-1.5`. Quiz imagery + reference/figure → `gpt-image-2`.** | `docs/08` §3.5, `docs/15`, `docs/16` |
| Embeddings | `text-embedding-3-small` | `docs/09` |

**Secrets:** only `IMAGE_PROVIDER_API_KEY` is confirmed set (2026-07-31, verified against `gpt-image-1`, `-mini`, `-1.5`, `gpt-image-2`, `chatgpt-image-latest`). `STYLIST_PROVIDER_API_KEY`, `VISION_PROVIDER_API_KEY`, `EMBEDDING_PROVIDER_API_KEY`, weather/affiliate keys and `APP_STORE_SHARED_CONFIGURATION` are named but **not set**, and **no function reads any provider key yet**. `XAI_API_KEY` and `GEMINI_API_KEY` were **revoked at the provider** on 2026-07-31.

**Two traps here:**

- **`docs/10-style-studio-integration.md` documents an abandoned Higgsfield integration.** Its header is an explicit banner: *"Nothing in this document is an instruction. Every vendor-specific line below describes an integration that will not be built."* It contains client setup, prompt construction and credit pricing for a vendor that is gone. **Do not use it as current spec.** The live decision lives in `docs/08` §3.5.
- **The vision-provider decision has a pilot gate attached**, and it is a hard precondition, not a formality. `docs/08` §2.5 calls GPT-5.6's menswear subcategory accuracy *"a pilot-and-verify gate, not a settled fact"* and requires a labelled-real-photo pilot **before the closet-scan flow ships**. If it fails, Terra becomes the default tier and `docs/09`'s cost model must be rerun.

### 5.7 Deployment and operations

- **`scripts/apply-migrations.sh`** wraps `supabase link` + `db push`. Unless `--dry-run` or `--yes`, it forces the operator to **re-type the project ref** at a prompt. *"There is no way for this script to know which ref is 'production'... the guard is therefore unconditional."*
- **`scripts/deploy-functions.sh`** deploys every directory with an `index.ts` (excluding `_shared`). It deliberately does **not** set secrets, run migrations, or verify — *"so a failure in one is unambiguous about what did and didn't happen."*
- **`scripts/verify-deployment.sh`** is "did the deploy actually work", distinct from "did deploy exit 0". Four checks: the client's URL **extracted live from `AstraEndpoint.swift`** (never hand-written — that is exactly the ADR-0013 bug class) is reachable; a JWT-less request gets 401; every local migration timestamp is recorded as applied on the remote DB; RLS is actually `relrowsecurity = true` on every user-owned table, read from `pg_class`.
- **`supabase/config.toml` is not checked in.** A first-time setup needs `supabase init` before `supabase link`.
- **The account-deletion runbook is a migration header.** `20260728101300_account_deletion.sql` specifies the exact six-step Edge Function orchestration (validate JWT → `request_account_deletion()` → respond 202 → service-role Storage sweep of `users/{user_id}/` → `finalize_account_deletion()` → `auth.admin.deleteUser()` → `mark_account_deletion_complete()`). **That function does not exist.** Whoever builds `DELETE /account` should follow that comment verbatim rather than re-deriving the sequence.

### 5.8 One server-side rule that is easy to violate

**`complete_onboarding()` and `style-dna/generate` intentionally never write the same columns.** `style_profiles.formality_preference`, `logo_tolerance`, `trend_tolerance`, `accessory_preference`, `preferred_colors`, `avoided_colors`, `style_summary` and `embedding` are owned **exclusively** by `POST /style-dna/generate`; the onboarding RPC omits them from both its INSERT and its `ON CONFLICT DO UPDATE`. Writing them from anywhere else silently reverts a regenerated Style DNA on the next onboarding resubmission.

---

## 6. ~~Guest mode~~ — removed (ADR 0014)

**There is no guest mode.** An account is required before onboarding. Removed 2026-08-06 by
[ADR 0014](docs/adr/0014-account-required-no-guest-mode.md), which supersedes 0011 and amends
spec §6.2 and §7.

Deleted, not flagged off: `GuestClosetRepository`, `GuestAwareClosetRepository`,
`GuestClosetStore` and both implementations, `GuestMigrationService` /
`LiveGuestMigrationService`, `GuestProfileView(Model)`, `GuestLimits`, `CreateAccountReason` and
the create-account sheet, `AuthSession.isGuest`, `SessionStore.isGuest` /
`currentIsGuest()` / `currentGuestUserID()`, `AppRouter.blocksGuestScan`,
`AppModalRoute.createAccount`, `OnboardingViewModel`'s `.guestPreview` and `.savedLocally`
states, and the three test suites that pinned the behaviour.

**Read this part even though the feature is gone**, because two of its lessons are about the
codebase and not about guests:

1. **A branch added to fix one path can quietly become the only path that is right.** The guest
   branch in `DefaultHomeBriefProvider` was added because a guest hit Home's error state — and
   it then became the *only* path that reached §6.11's empty state. Every real user got an error
   screen where the spec calls for an invitation, for weeks, and the branch structure is what
   hid it.
2. **ADR 0011 predicted its own data-loss bug and it shipped anyway.** Its Consequences section
   said onboarding answers "must also be captured locally during guest onboarding and migrated,
   not just closet scans". `LiveGuestMigrationService` migrated closet items and no profile
   table. A named consequence is not a mitigated one.

What remains and is easy to confuse with it: **the free-tier 30-item cap**
(`FreeTierLimits`, `FreeTierCappedClosetRepository`, `FreeTierClosetError.capReached`) is a cap
on a *signed-in* closet and is untouched. Both used to cap a closet, which is most of why they
were confusable.

If a trial path is ever wanted again, ADR 0014's Alternatives says where to start — and it is
not what was deleted.

## 7. Feature-by-feature state

### 7.1 Onboarding — the most complete flow

`OnboardingStep` is a `Comparable` enum whose `allCases` order **is** the flow:

```
intro → goals → identity → measurements → appearance → lifestyle → quiz → reference → firstItems → result
```

`answerableSteps` excludes `intro` and `result` (so the progress denominator is honest). **Every step is skippable except `.identity`** — §6.5's "choose three, rank one primary" is the only shape that can't be partially satisfied.

**The submission-ordering bug and its fix — do not undo this.** From `OnboardingViewModel.swift`'s header, verbatim:

> "It used to run when the user tapped forward OFF the result step, which was correct while that step was a stub. It cannot stay there now that the step shows Style DNA, because `POST /style-dna/generate` deliberately sends no body — it reads the profile rows the client has already written... Generating before submitting would therefore read an empty or stale `style_profiles` row and hand every brand-new user a null identity: the screen would render the server's honest 'not enough to call a direction' state for a man who had just answered seven screens of questions."

So `loadStyleDNA()` **submits first and generates second**, and §6.10's forward button only leaves the flow. The server generator is stateless with respect to the request body — it re-reads whatever is currently in the three profile tables.

**The reference photo uploads at submission, not at capture.** `uploadReferenceImageIfNeeded()` runs inside `submit()`, so nothing leaves the device until the answers do — which is also what keeps `removeReferenceImage()` a purely local operation with no remote object to chase.

### 7.2 The quiz imagery system — the most unusual thing in the repo

`ios/AstraStyle/Resources/QuizImagery/quiz-pairs.json`, `version: 2`, **15 pairs** across 8 axes:

| Axis | Pairs |
|---|---|
| `formality`, `colour_tolerance`, `texture`, `logo_tolerance`, `trend_tolerance`, `accessory_preference`, `contrast_preference` | 2 each |
| **`silhouette`** | **1 — permanently `.low` confidence until a second lands** |

> **`docs/03-progress.md`'s blocker list is stale here** — it says 14 pairs with `logo_tolerance` also at one. `logo-01` has shipped; only `silhouette` is short. `Resources/QuizImagery/README.md` is stale more subtly: its heading already says "15 pairs" correctly, but the table below still lists 14 rows (no `logo-01`), and one sentence keeps a plural verb left over from an incomplete edit. **Fix the table and that sentence, not the heading.**

**How loadings work.** `StylePreferenceInference` sums signed loadings per axis and separately sums `|loading|`. `score = signed/absolute` (−1…+1); `agreement = |signed|/absolute` (0…1). Bands: `< 2.0` observations → `.low` (*"one comparison is a direction, nothing else — no part of the app should tell the user this is what he likes"*); `≥ 2.0` **and** `agreement ≥ 0.5` → `.moderate` (the bar at which Kyra may say it out loud); `≥ 4.0` **and** `agreement ≥ 0.75` → `.high`. A "no preference" answer counts as *answered* but contributes zero evidence, so a forced binary on an indifferent user isn't recorded as signal.

**Reference-conditioned generation, and why.** The first batch was text-to-image, one prompt per frame, and returned a **visibly different person** in 3 of 10 candidate pairs — *"the user may be answering the model rather than the clothes,"* a worse confound than lighting. The fix: generate **one canonical reference figure** once, then dress that same figure for every frame via `/v1/images/edits`. Measured result: backdrop drift within a pair fell from **20.9 mean / 33.7 worst-case** luma to **1.6 / 3.0**, residual ≤0.8 after normalisation.

**The three scripts, in pipeline order:**

1. `scripts/generate_quiz_imagery.py` — OpenAI `gpt-image-2`, portrait 1024×1536, medium quality, direct (needs `OPENAI_API_KEY`). `--reference` once, then `--all` or `--pair <name>`. Total spend to date ≈ **$1.30**.
2. `scripts/build_quiz_imagery.py` — normalises each pair's backdrop to the pair's **mean** luma via one scalar gain (chosen over pinning a seed because seed stability was untested), **crops the top 7% unconditionally** (removes chin/neck even though the prompt asks for none — treated as load-bearing because the cost of a leaked face is asymmetric), resizes to 720px, JPEG q90. Needs `pillow` + `numpy`.
3. `scripts/composite_quiz_logo.py` — builds the `logo_tolerance` "b" frames by **compositing**, not generating.

**Why the logo pairs are composited.** Generating a second photograph, even from the same reference figure, lets drape, fabric and light shift — signal the man might answer that isn't branding. Compositing removes the confound rather than measuring it, **making backdrop delta 0.0 by construction.** The mark is Astra's own monogram, and the decisive reason is **measurement, not law**: a real logo makes the man answer *"do I like that company"* instead of *"do I mind visible branding."* (The first attempt literally returned a readable "HILFIGER" wordmark; that file was deleted.)

The placement constants took four passes and are all measured:

```python
PLACEMENTS = {
    "logo-1": {"y": 0.118, "width": 0.034, "x": 0.600},   # crew-neck sweatshirt
    "logo-2": {"y": 0.111, "width": 0.033, "x": 0.600},   # quarter-zip, higher neckline
}
OPACITY = 0.90
BLUR = 0.5
```

Torso spans ~0.40 of image width, so a mark of width `w` covers `w/0.40` of the chest:

| width | % of chest | reads as |
|---|---|---|
| 0.155 | 39% | a graphic print across the midriff |
| 0.080 | 20% | roughly twice a real logo |
| 0.048 | 12% | a printed chest logo, on the large side |
| **0.034** | **8.5%** | **an embroidered left-chest mark** |

The 10–12% figure an earlier pass reasoned from was drawn from *printed* chest graphics; embroidered left-chest branding runs 7–9%. `x = 0.600` is the wearer's left chest (viewer's right), the standard placement — centre-chest reads as a print, and this axis is about logos.

**Known, recorded risks:** no blinded human rating has been done on whether these read as photographs vs renders; "one man throughout" is a deliberate confound-removal that is itself a coverage tradeoff.

### 7.3 Closet — the most complete feature

> **`Features/Closet/README.md` is stale and *undersells* the module.** It claims the metrics row, the three view modes and the filter panel don't exist. All three shipped. Trust the code and `docs/03-progress.md`.

**View modes.** `ClosetViewMode` — `editorialGrid` (default), `compactList`, `colorSpectrum`. Declaration order is display order, a deliberate progression: *look at it → find something in it → see it as a whole*. Persisted at `@AppStorage("closet.viewMode")`, owned by the **view** layer so `ClosetView` and `ClosetCategoryView` read the same key and can't disagree. `ClosetViewModel` is unaware of the active mode — it exposes plain arrays; only `ClosetColorSpectrum` reorders what it's given.

**Filters — OR within a facet, AND across facets.** Eight facets. The rationale: *"category is Tops and category is Bottoms describes a garment that cannot exist, so an AND-within-facet rule would make every multi-select in this panel a control whose second tap always empties the screen."* The panel states both operators in copy rather than relying on convention.

Details worth preserving:
- A garment with nothing recorded in a filtered optional field is **excluded**, not passed through — *"a garment with no brand on file is not any brand."*
- Brand and colour are matched on a **folded key** (case + accent + whitespace + punctuation insensitive), so "A.P.C." and "apc" are one chip, displayed with the spelling most of the closet uses.
- Wear frequency carries **two axes ANDed** (count bands + recency windows) and no label claims a rate, because there is no denominator on-device — `purchaseDate` is optional and `createdAt` records app-entry, not wardrobe-entry.
- **`apply(to:)` returns the identical array reference when nothing is active** — no copy, no re-derivation. That is what guarantees clearing filters can't flash a reload, which is P3-CLOSET-05's second acceptance criterion.
- **A value no garment carries is never offered**, and a facet whose every value covers the whole scope is dropped entirely.

**Metrics — five of six, and the sixth is a deliberate absence.** `ClosetMetrics.compute(for:)` is a pure function with a private memberwise init, so the "recomputes after add/archive/mark-worn" criterion is met **by construction** rather than by discipline.

- **Estimated value** is per-currency subtotals, **never a converted sum** (no exchange rate exists anywhere in the client or spec), and carries its own coverage — 3 of 40 priced reads as exactly that, not as a $400 wardrobe.
- **Average cost per wear** is total spend ÷ total wears over the **priced garments only**. `CostPerWearCalculator.averageCostPerWear` does `pricePaid ?? 0` in the numerator but counts *every* item's wears in the denominator, so passing a whole closet silently deflates it. Its doc comment now says so; the behaviour is pinned by P3-CLOSET-10's tests and must not change.
- **Most/least worn** report `.tie(itemCount:wearCount:)` as a tie and `.noWearHistory` for an all-zero closet — never an arbitrary pick, and a tie is not tappable.
- **Versatility is absent.** `docs/05` §5.1 defines it as outfit participation at compatibility ≥ 0.65; every input is Phase 4. From the file header: *"A client-side substitute was considered and deliberately rejected: any of those is a defensible number about something, but none of them is versatility, and it would render in the same type, in the same row, beside four measured figures, indistinguishable from them."*

**Colour-spectrum ordering — a pure, unit-testable function.** `ClosetColorSpectrumOrder.ordered(_:)` is what lets P3-CLOSET-04's second acceptance criterion be an assertion instead of a screenshot.

Sorting on the packed hex is a **red-channel sort** — it files burgundy `0x5E2233` next to forest green `0x3B5A40`. So: six hue bands round the wheel (boundaries hand-placed, not an even 30° grid, so `sky blue` at 209° doesn't split from the other blues), each running **dark → light**, then a neutral block ordered by depth. Chromatics before neutrals, because a menswear closet is mostly neutral and leading with grey is the opposite of "reads as a colour story at a glance."

**Neutrality is decided by HSV saturation < 0.20**, and both obvious alternatives were tested against the real palette and **measurably fail**:

| Test | Failure |
|---|---|
| HSL saturation | blows up near white — `cream` scores 0.49, higher than `sky blue` at 0.46 |
| Absolute chroma | collapses in the dark — `forest green` 0.094 vs `bone` 0.082, indistinguishable |
| **HSV saturation** | cream 0.12, bone 0.09, sky blue 0.33, forest green 0.35 — all correct |

Both counterexamples are pinned as tests. A second clause forces lightness ≤ 0.10 to neutral (a near-black `0x0A0A14` scores 0.50 HSV and would otherwise file as blue). Ordering key chain — band, lightness, hue, saturation, name (locale-independent `<`), UUID — never leaves a tie, because `Array.sorted` is not documented stable.

Colours the wheel can't place go to **two named, explained trailing groups**, kept apart because "no colour on file" is a field the user can fill in and "no swatch for this word" is not. A test asserts every non-wheel group has an explanation string, so a silent tail can't ship.

**Empty-state precedence — `emptyReason(for:)`, checked in this order.** Two of these branches exist because of bugs that put a **false sentence on screen**:

1. `.closetIsEmpty` — zero items anywhere.
2. `.categoryIsEmpty(category)` — **checked before query and filters**, because it's the only one true regardless of them. The bug: reaching Shoes with any filter on reported `.noFilterMatches` — *"you own pieces in each of those, but none in all of them at once"* — on a closet with no shoes, and Clear Filters then put nothing back.
3. `.noSearchMatches(query:)` — wins over filters, **but only when the query alone empties the scope** (`searchNarrowed(scopeSource).isEmpty`, not merely `isSearching`). The bug: filter to one house, type "shirt" over a closet holding two shirts by others, and the screen said *"Nothing in your closet matches 'shirt'"* — false, and Clear Search handed back garments that aren't shirts. **`scopeSource` is category-scoped, not whole-closet** — that's what stops the fix producing the mirror-image lie.
4. `.noFilterMatches` — the residual.

**Metrics-vs-tile-count asymmetry, deliberate:** `metrics` is computed over `allItems`; `count(in:)` on a category tile **is** narrowed by search and filters. *"A tile is a door and its number must match what's behind it; a metric is a statement about the wardrobe. 'Estimated closet value' falling from £14,000 to £180 because a man typed three letters reads as money going missing."*

### 7.4 Scanner — single-item loop ships; modes still Partial

> **UPDATE (2026-08-01, `86edb74`):** The paragraph below described mid-day groundwork and is **historical**. On current `main` the Scanner has real `Views/` + `ViewModels/` + capture session adapters, review/upload/save, pending-analysis offline queue, device hints before review, App Icon assets, and a post-save unlock report (`P3-SCAN-05/06/09/11`, `P3-INFRA-01/02` Done). Still Partial / Not started: live device Vision QA criteria, OpenAI pilot gate (`VISION_ANALYSIS_PROVIDER` still defaults to mock), batch analyze end-to-end, receipt/mirror modes, server cutout. Ticket truth: `docs/03-progress.md` Phase 3 table. Runbook for phone: `docs/12-testflight-cut.md` and **§12.0**.

What landed earlier the same day (pure pipeline — still accurate as building blocks):

**`CaptureQuality.swift`** — §12 step 1. `CaptureQualityVerdict` combines independent `BlurAssessment` and `ExposureAssessment`, each `Comparable` on a three-level severity (`acceptable`/`warning`/`blocking`). **Every threshold was measured against the garment photographs already in `brand/quiz-imagery`, not taken from literature.** Reconcile the corpus before re-deriving any of them: `CaptureQuality.swift`'s blur comment says **34** photographs, its own exposure comment says **36**, and the directory holds 36 PNGs of which only 32 are axis-pair garment photos. The source disagrees with itself.

| Constant | Value | Evidence |
|---|---|---|
| `analysisLongestEdge` | 512 | Laplacian variance is scale-dependent — the same photo measures 378 @256, 203 @512, 154 @1024. A 2.5× swing, larger than the sharp/blocked gap, so the working resolution must be pinned. |
| `blurWarningVariance` | 90 | Sharp 122–309 (median 178); radius-1 blur 44–73. 90 is the gap. |
| `blurBlockingVariance` | 30 | Radius-1 44–73; radius-2 (where label text dies) 16–26. 30 is the gap. |
| `midGreyEncoded` | 0.4587 | `0.18^(1/2.2)` — everything is stated in sRGB-**encoded** space. A naive "mean < 0.18" rejects frames 1.5 stops *brighter* than correct. |
| under warn/block | 0.28 / 0.16 | −1.6 / −3.3 stops. Corpus floor 0.331. |
| over **block** | clip > 0.35 **and** mean > 0.75 | The important one. A dark garment on a white duvet is half near-white; blocking on clipped fraction alone refuses an entirely ordinary photograph. |

The corpus is editorial studio photography, not handheld phone captures — the file states this and calls the thresholds *"if anything a conservative floor"* pending the real 20-photo device test.

**`CapturePreparation.swift`** — §12 steps 6–7. `Data → Data`, resize to `docs/08` §2.3's **1024px** cap, JPEG **q0.72** (from a measured sweep: 48 KB @0.50, 95 KB @0.72, 145 KB @0.90), metadata dropped **by construction**. It is a **sibling** of `ImageDownsampling`, not an extension of it: that utility returns a `UIImage` with no re-encoding step for steps 6–7 to live in, and its `scale` multiplier would make a pixel cap unenforceable. Measured **18.2× mean** reduction on simulated 12 MP captures.

The metadata claim is precisely worded: **"nothing that identifies the person, the place, the time or the device"**, not "no metadata" — ImageIO writes its own `{JFIF}` block and a three-key `{Exif}` block (`ColorSpace`, `PixelXDimension`, `PixelYDimension`), so the test asserts on **keys**, not on a block's absence. Orientation is asserted **baked into the pixels** — a stripped orientation tag on an unrotated image ships every garment sideways.

**`DominantColorExtraction.swift`** — §12 step 5. Samples a **centre-region prior** (`x:0.2, y:0.15, w:0.6, h:0.7`) rather than the whole frame, quantises to 4096 bins, merges within `mergeDistance = 28` — derived exactly from the quantisation cell diagonal (`16×√3 ≈ 27.7`), not picked by eye. A perceptual merge rule was tried and **killed by the palette data**: navy and ink blue are 1.6° of hue apart, camel and tan 1.4°, forest and hunter green 0.7° — 32 pairs would merge at any threshold loose enough to absorb real shading.

**The seam:** `protocol GarmentRegionDetecting: Sendable { func detectGarmentRegion(in: CGImage) throws -> GarmentRegion? }`. Deliberately **unimplemented and unstubbed** — the only honest implementation is a live Vision request against a real garment photo, which can't be asserted in CI. Three things change when it lands: exposure/focus get measured over the garment (retiring the white-duvet leniency), colour extraction stops guessing the centre, and the review screen gets its cutout.

**Label OCR (§12 step 4) is out entirely** — no code, no stub, no seam yet.

**`AstraGarmentColor` runs word → hex, and should not be inverted client-side.** The review screen wants hex → word, but `ClosetItemAnalysisResult.primaryColor` is already a `FieldSuggestion<String>` — **the server supplies the word**; device hints carry RGB only. Inverting the table on-device would create a second colour vocabulary that disagrees with the server's.

### 7.5 The analysis DTO — the contract between four tickets

Redesigned 2026-08-01 *before* anything depended on it, precisely because changing it later means touching the Edge Function, the mock, every test double and the review screen. Three defects were fixed:

1. **Missing fields the spec names.** §5.3 step 5 says analysis suggests "…condition, **and fit**". There was no `fit`. Now added: `fit`, `size`, `seasonality`, `formalityScore`, `warmthScore`, `waterResistanceScore` — the rule being *a field belongs iff analysis can infer it AND `ClosetItem` can store it*, because a suggestion the user edits and confirms that then evaporates on save looks exactly like a save that worked.
2. **`secondaryColors` and `material` carried no confidence at all**, making P3-SCAN-09's "visibly marked" criterion unsatisfiable for them. Now **per element**, not per list: "80% wool, 20% nylon" can be certain about the wool and guessing at the nylon, and the review screen can mark the nylon chip alone.
3. **The batch shape couldn't express its own criterion.** Results now carry a **client-minted correlation UUID** and an outcome **enum**, so "neither result nor error" and "both" are unrepresentable, and identity never depends on array position. (The mock previously fanned out with a task group and returned results **out of order** — position-based identity would have silently mismatched garments.)

`fieldsBelowConfidenceThreshold` is **stored AND computed, unioned**. Stored alone can disagree with the numbers beside it; computed alone can't see the reasons `docs/08` gives the server for flagging a field anyway. The union is **monotone** — it only ever adds a mark — so a server omission, an older deploy, or the mock can never leave a low-confidence field unmarked.

The display threshold moved off `FieldSuggestion` onto `AnalysisConfidence.lowConfidenceThreshold = 0.6`, deliberately distinct from and above `docs/09` §2.1's **0.55 server-side escalation** trigger, which is a different thing for a different field set.

### 7.6 The six empty modules

`Discover/`, `Kyra/`, `Outfits/`, `Shopping/`, `Studio/`, `Subscription/` contain **only a README.md**, and since ADR 0014 so does `Profile/` — its two files were the guest profile. Every one of those READMEs is an accurate forward-looking spec, not an overclaim — but a reader skimming directory names will assume far more exists than does.

---

## 8. Standing decisions — do not relitigate these

These were decided deliberately, often against an obvious-seeming alternative, and several were reversed once already before landing where they are. Changing one needs an ADR that supersedes the existing one, not a quiet edit.

### 8.1 Vendor

**OpenAI only.** xAI and Gemini keys were revoked at the provider on 2026-07-31. Higgsfield is dropped outright as a vendor — *"nothing routes to it."* The user has stated this twice, in the strongest terms: **under no circumstance is Higgsfield to be called.** `docs/10` exists as a record of the abandoned integration, not as a spec.

One nuance you may trip over: the bake-off that *chose* `gpt-image-2` was run through Higgsfield's **reselling** API. `docs/16` §0 addresses it — *"The model that won the race is the model that ships; what changed later the same day is the route to it."* The production path is direct to OpenAI.

### 8.2 Soul ID / trained identity models — rejected

A trained per-user identity model was proposed and **explicitly rejected** in `docs/15` §4: it is a persistent derived biometric model and collides with §29's right to erasure. Do not reintroduce it under any name.

### 8.3 Legal — deferred to the end of the project, by explicit decision

Four documents exist under `legal/` (`privacy`, `terms`, `data-deletion`, `affiliate-disclosure`), drafted **from the actual migrations and ADRs** rather than a template, specifically so a lawyer argues law and not software behaviour. The decision, quoted from `legal/README.md`: *"deliberately left alone until the end of the build. Nothing further happens before then: no publishing, no domain registration, no filling of the `[[NEEDS INPUT]]` placeholders, no legal review, no flipping of `AstraLegal.isPublished`."*

`AstraLegal.isPublished = false`, and **every accessor returns `URL?` = `nil` while unpublished** — the unpublished state is a compile-time fact every call site must handle. The previous shape returned a non-optional `URL`, so every call site looked correct, compiled clean, and silently opened Safari on a DNS error. `LegalDocumentAvailabilityTests` pins the invariant.

Remaining `[[NEEDS INPUT]]`: legal entity name, registered address, governing law, jurisdiction, three contact emails (all blocking, across all four documents); the warranty-disclaimer and limitation-of-liability clauses in `terms.html` are **not drafted at all**; and a **biometric-privacy review** (BIPA / CUBI / GDPR Art. 9 for face images + body measurements) is flagged with a red-bordered notice and unresolved.

There is **no registered domain** — `astrastyle.app` returned RDAP 404 on 2026-07-31, i.e. nobody owns it. The public Supabase Storage URL is the App-Store-submission stand-in, which is why `AstraLegal.host` is one constant.

> **`legal/README.md`'s "where the app does less" table is now inaccurate** — it says Closet and Scanner have no Swift files. They do. Since that table is a factual input to the privacy policy, re-verify it against the tree before the end-of-project legal pass.

### 8.4 Architecture

| Decision | ADR | One line |
|---|---|---|
| Native SwiftUI, iOS-only | 0001 | Vision/StoreKit2/WeatherKit have no first-class RN/Flutter bridges. |
| Supabase as the backend | 0002 | Accepting Deno-runtime and Supabase-Auth-RLS lock-in as the real costs. |
| Relational wardrobe graph, not a graph DB | 0003 | Ordinary Postgres + cached compatibility scores, with four named conditions to revisit. |
| Provider-neutral AI layer | 0004 | The client never holds a vendor key; extra network hop accepted. |
| SwiftData as cache, not source of truth | 0005 | Postgres is authoritative; conflicts are surfaced, never silently auto-resolved. |
| `@Observable` over Combine | 0006 | iOS 18 floor removes the backward-compat reason. |
| Hand-rolled `AppContainer` | 0007 | No reflection/macro DI framework; a growing flat initializer is the accepted cost. |
| XcodeGen | 0008 | Reviewable YAML diffs instead of `.pbxproj` merge conflicts. |
| StoreKit 2 + server reconciliation, not RevenueCat | 0009 | Margin protection at $12.99/month, with named switch conditions. |
| Image storage and retention | 0010 | Private buckets, signed URLs, `users/{user_id}/…`; abandoned references auto-delete (24h default), Studio outputs expire (30d default); **training opt-out defaults to off**. |
| ~~Guest mode fully local~~ | 0011 | **Superseded by 0014**: an account is required, guest mode removed. |
| An account is required | 0014 | The trial path guest mode offered was never reachable; the branches it added cost more than it bought. |
| Testing strategy | 0012 | Swift Testing for unit/integration, XCUITest for UI, unit-heavy pyramid. |
| Edge Function routing | 0013 | §14 URL shapes preserved verbatim; 12 slugs, shared router. |

---

## 9. Landmines

Ordered roughly by how expensive they are to hit.

**1. The UUID-casing storage trap.** See §5.3. Silent 403 on every object, no error naming the cause. Documented in exactly two client-side doc comments and nowhere server-side.

**2. ~~Orphaned uploads and non-idempotent retry on a paid call.~~ Closed 2026-08-06.** Kept here because the *shape* of it recurs: `analyzeItem` uploads to Storage and then calls an Edge Function, so any failure between those two steps strands bytes nobody references.

What closed it, in the order the three parts fell:
- The `closet` function **is deployed** (it existed in the repo from `59e07361` and had never been deployed; `20260801120000_closet_analysis_jobs.sql` had never been applied — both done now), so analyze stopped 404ing on every call.
- **Idempotency is real:** `AstraEndpoint.requiresIdempotencyKey` mints one key per logical call and reuses it across retries; `closet_analysis_idempotency` replays the stored response. One tap can no longer become three paid vision calls.
- **`ClosetRepository.deleteCapturedImage(atPath:)` now exists**, and `ScannerReviewViewModel.discardUnsavedUpload()` runs on every non-save exit (Retake, both Close buttons, swipe-dismiss). `LiveClosetRepository.analyzeItem` / `batchAnalyzeItems` additionally delete what *they* uploaded on failure.

Two rules to preserve if you touch this. **Only compensate for an upload you made** — a caller-supplied `storagePath` belongs to the caller, and the scanner deliberately keeps its path across an analyze retry so the retry does not re-upload; deleting it would pull the object out from under the retry. And **the batch stops compensating once the job is enqueued** — from then on the server owns those objects, and a poll that times out is not a reason to delete images a job is still working through.

ADR 0010's 24h sweep for *reference* photos still does not exist. That is a separate gap.

**3. Grouped-function fate-sharing puts a batch job in the interactive path's isolate.** ADR 0013 requires `analyze-item` and `batch-analyze` to be **one deployed function**, sharing one in-memory rate limiter and one deploy unit. Batch is bursty and long-running; single-item analysis is what a user is staring at. A 20-image batch will saturate the shared limiter and can OOM the isolate. **Design the batch as a job + poll from day one** — P3-SCAN-08's own scope permits "asynchronously or via polling". Note a polling endpoint is a *new* §14 endpoint, touching `AstraEndpoint`, `EndpointDeploymentMappingTests` and arguably the spec.

**4. ~~Guest mode dead-ends the scanner.~~ Gone with guest mode (ADR 0014).** The scan button now opens the scanner for everyone who can reach it.

**5. Nothing about the camera is testable, and the acceptance criteria are written as if it were.** No camera in the simulator, no fixture-image mechanism, no test-asset wiring in either target, storage RLS uncovered. P3-SCAN-01 criterion 2, P3-SCAN-02 (both), P3-SCAN-03 (both), P3-SCAN-10 criterion 1 and P3-SCAN-12 criterion 1 are **all manual-on-device**. If the capture layer is not isolated behind a protocol with the logic pulled into pure functions, the largest ticket in Phase 3 ships with **zero automated coverage**.

**6. `xcodebuild` reports warnings and still says BUILD SUCCEEDED.** This has bitten the project before. The only thing that enforces the zero-warning bar is the grep. Local equivalent:

```bash
xcodebuild -project ios/AstraStyle.xcodeproj -scheme AstraStyle \
  -destination "id=$(python3 scripts/resolve_ios_simulator.py)" build 2>&1 \
  | grep "warning:" | grep "ios/AstraStyle/"
```

It must print nothing.

**7. ~~`AstraAPIClient` discards the server envelope on 404.~~ Fixed 2026-08-06** — see §4.9. A 404 now maps to `.unimplemented` and the server's message is logged. The replacement landmine is smaller but real: **a new endpoint whose function is not yet deployed now fails quietly and unretryably.** That is the honest behaviour, but it means the screen says "Not ready yet" rather than anything you can debug from. When you see that, read the log line — it names the method and path.

**7a. `xcodegen generate` rewrites `ios/AstraStyle/Resources/Info.plist` wholesale**, because `project.yml`'s `info:` block owns that path. Anything hand-added to the plist disappears at the next regen with no warning. This already happened once: commit `913e43a1` added `UISupportedInterfaceOrientations` (App Store Connect rejects an upload without it) and a later regen silently deleted it — it was missing from the working tree again on 2026-08-06. The keys now live in `project.yml`'s `info.properties`, which is the only place they survive. **The `INFOPLIST_KEY_*` build settings did NOT cover this**: Xcode merges those only when `GENERATE_INFOPLIST_FILE` is `YES`, and this target sets it `NO` because it supplies its own plist. Three of them (`UILaunchScreen_Generation` and both orientation keys) sat in `settings.base` doing nothing while reading as the source of truth — they have been deleted, and removing them changed the generated plist not at all, which is the proof they were dead. Do not add an `INFOPLIST_KEY_*` to this target; add the key to `info.properties` instead.

**8. ~~`.github/workflows/edge-functions.yml` does not cover `profile/` or `style-dna/`.~~ Closed 2026-08-06.** The workflow now calls `deno task check|test|fmt-check|lint` instead of repeating the directory list, so `supabase/functions/deno.json` is the single list and a new function directory added there is covered by CI by construction. (The gap was real when written and had since half-closed on its own; the duplication that caused it is what got removed.)

What still needs a second edit when you add a function: **`requiredNow` in `EndpointDeploymentMappingTests`.** Add the slug there the moment a production call path builds a URL for it, not once it is deployed — `daily-brief` sat in `expectedSlugs` and not in `requiredNow` while `HomeBriefProviding` called it on every load, so the test written to catch exactly that had a hole exactly where the bug was.

**9. `ClosetRoute.filters` and `ClosetRoute.editItem` are provably dead enum cases.** Both resolve to honest placeholders; nothing pushes either (the filter panel is a sheet, the editor is presented from the detail screen which already holds the loaded item). Don't wire them to something wrong on the assumption they're wanted.

**10. Stale documents.** In addition to the module READMEs already flagged: `ios/README.md` still says *"Nothing in this repository has been compiled"* — that dates from the original scaffold and is long false. `docs/11-risk-register.md` carries Higgsfield-credit arithmetic under a heading that says it has not been recomputed. `Astra_Style_iOS_Master_Build_Spec.md` at the **project root, outside the repo**, is a frozen 2026-07-28 snapshot — **`docs/00-master-spec.md` is 11 lines newer and is the only authoritative copy** (spec §3's WCAG-corrected hex values were amended into it on 2026-07-30 specifically so nobody "restores" the failing values later).

---

## 10. How work is recorded

### 10.1 `docs/03-progress.md`

Structure: audit stamp → "How this file is kept honest" → status vocabulary → summary table → **"What is actually blocking, right now"** (severity-ordered) → **"Acceptance criteria that are wrong, rather than unmet"** (an amendment log) → one section per phase.

Row format: `| Ticket | Status | Evidence |`. Evidence cells cite specific files (and sometimes line ranges) in backticks, **bold the negative findings inline**, and state in the same cell exactly what is still missing and why the status isn't higher.

Statuses, exactly four: **Done** (every criterion met, with evidence) · **Partial** (some met, others provably not, and the row says which) · **Not started** (no implementing code exists anywhere) · **Unverifiable** (a real criterion not settleable by reading code — needs a device, a sandbox purchase, App Store review, or subjective judgement; *"used honestly; it is not a synonym for Done"*).

Ticket IDs: `P{1-7}-{AREA}-{nn}`. Areas seen: `INFRA`, `CORE`, `DS`, `AUTH`, `ONBOARD`, `CLOSET`, `SCAN`, `OUTFIT`, `KYRA`, `STUDIO`, `SHOP`, `SUB`, `PRIVACY`, `TEST`.

Current counts:

| Phase | Tickets | Done | Partial | Not started |
|---|---|---|---|---|
| 1 — Foundation | 25 | 13 | 12 | 0 |
| 2 — Identity | 17 | 12 | 5 | 0 |
| 3 — Closet | 27 | 5 | 9 | 13 |
| 4 — Outfit intelligence | 26 | 2 | 11 | 13 |
| 5 — Kyra | 22 | 1 | 3 | 18 |
| 6 — Studio and commerce | 25 | 2 | 4 | 19 |
| 7 — Monetization and hardening | 36 | 0 | 8 | 28 |
| **Total** | **178** | **35** | **52** | **91** |

The discipline, quoted:

> *"A hand-maintained status file is accurate the day it is written and quietly wrong a week later, which is worse than having none because people trust it."*
> *"When you finish a ticket, update its row in the same commit. A status change with no corresponding code change is a lie in the making."*
> *"'Partial' is the most common status and that is expected, not a failure."*

**To update it correctly:** flip the status, rewrite the Evidence cell to cite what now does (or still doesn't) substantiate the claim, and if counts moved, update **both** the phase's own count line **and** the global summary table — that mismatch is the single most common failure `check_progress.py` catches.

**A row that overclaims is worse than a Partial.** This is the file's whole purpose.

One thing `check_progress.py` does **not** check: each phase section opens with a free-text `**X Done · Y Partial · Z Not started.**` sentence, and the checker only validates the machine-readable summary table against the rows. Phase 3's prose sentence had drifted (it read 5/7/15 against a real 5/9/13) and was corrected alongside this handoff — but nothing stops it drifting again, so update the sentence, the phase table row and the global total together.

### 10.2 The amendment log

`docs/03-progress.md` has a section for **criteria that are wrong rather than unmet**, with the rationale: *"A criterion that can never pass quietly trains its reader to stop trusting criteria at all, so each has been corrected at its source rather than left open."* Six are logged. If you meet a criterion that cannot pass, correct it at source and record it there — don't leave it hanging.

### 10.3 Commit style

Long, structured, narrative bodies. A representative subject: `"Scanner groundwork: fix the analysis contract, build the testable half"`. Bodies consistently: (1) name the tickets and their status delta, (2) use all-caps section headers inside the body for distinct concerns, (3) explain **why**, citing measured numbers, (4) close with a verification line stating lint/build/test results verbatim, (5) end with a `Phase N: X done / Y partial / Z not started -> ...` delta.

Trailers on AI-assisted commits: `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` and `Claude-Session: <url>`.

### 10.4 Skipped tests are the backlog

There are **14** deliberately skipped tests, and they are the project's backlog in disguise. Each names the missing infrastructure and the ticket prefix expected to close it.

`Tests/UITests/AstraStyleUITests.swift` — 7 `XCTSkip`s, one per §22 flow: `testCompleteOnboarding`, `testAddGarment`, `testGenerateOutfit`, `testMarkOutfitWorn`, `testAskKyra`, `testOpenPaywallAndRestorePurchases`, `testDeleteAccount`.

`Tests/UnitTests/PendingIntegrationRequirementsTests.swift` — 7 `.disabled(reason:)`: `authLifecycle`, `closetUploadAndSync`, `dailyBriefGeneration`, `productEvaluation`, `studioJobPolling`, `storeKitSandboxPurchase`, `snapshotTestsNotYetConfigured`.

Both files carry an explicit instruction, and it matters:

> *"They were previously written as `Issue.record`/`XCTFail` bodies; that made the iOS job permanently red, which hid real regressions instead of highlighting these. **Do not delete them to make CI green**; replace them with real tests — dropping the skip at that point, not before — as their dependencies land."*

The choice of `.disabled(reason:)` over `withKnownIssue` is also deliberate: *"`withKnownIssue` is for a test that genuinely RUNS and genuinely fails. None of these bodies contain a single assertion — there is nothing to run, so there is no known issue to observe, only work that has not started."*

This is also why SwiftLint's `todo` rule is off — **there are zero TODO comments in this codebase by convention.**

### 10.5 Testing conventions

- **Swift Testing** for unit/integration (`import Testing`, `@Suite`, `@Test`, `#expect`, `try #require`). **XCTest** for UI only (Swift Testing has no UI driver). 39 of the 40 files in `Tests/UnitTests/` import `Testing`, and **zero** import XCTest — the one exception, `ScannerImageFixtures.swift`, is a fixture-data helper with no tests of its own.
- Tests live centrally in `Tests/UnitTests/` and `Tests/UITests/`, **not** per-feature.
- Style: a header citing the spec section or criterion it satisfies; `@Suite` named for the type plus the spec reference; **`@Test` descriptions written as full prose sentences stating the behaviour AND the reason** (e.g. *"Returns nil when never worn, rather than treating it as free or infinite"*); private `makeItem(...)` fixture helpers inside the suite; `try #require(...)` instead of unwrapping.
- XCUITest classes need `@MainActor` (every `XCUIApplication` member is main-actor-isolated in the iOS 26 SDK; 85 warnings without it, and warnings fail the build).
- CI-aware timeout convention: `ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60`.
- **There is no fixture-image mechanism and no test-asset bundle.** Neither test target declares `resources:`. The Scanner tests synthesise their fixtures in code (`ScannerImageFixtures.swift`) — follow that pattern rather than committing binary assets.
- **No snapshot-testing harness exists**, despite ADR 0012 calling for one. `snapshotTestsNotYetConfigured` is the placeholder.

---

## 11. Local dev setup

**Install:**

```bash
# Xcode 26.6 exactly — CI pins it and it matches the owner's machine.
# (ios/README.md says "Xcode 16 or later"; that line is stale.)
brew install xcodegen
brew install swiftlint
brew install supabase/tap/supabase      # only if touching the backend
# Deno 2.9.4 (CI pins it via denoland/setup-deno@v2) — only for Edge Functions
# psql — only for scripts/run-rls-tests.sh or seed-slice.sh
```

**Create what isn't checked in:**

```bash
cd ios
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # then fill in real values
```

`Config/Secrets.xcconfig` holds `SUPABASE_URL` and `SUPABASE_ANON_KEY` — **and nothing else ever**. Watch the xcconfig footgun: `//` starts a comment, so a URL must be written `https:/$()/...`. `Config/Base.xcconfig` documents it.

Also not checked in: the `.xcodeproj` (generated), `supabase/config.toml` (run `supabase init`), and a StoreKit Configuration file for sandbox subscription testing (two products matching `AstraProductID`: `com.astrastyle.app.premium.monthly` $12.99, `...annual` $79.99).

**From clone to green:**

```bash
cd ios && xcodegen generate && cd ..

swiftlint --strict --config .swiftlint.yml
python3 scripts/check_ui_conventions.py
python3 scripts/check_contrast.py
python3 scripts/check_column_drift.py
python3 scripts/check_schema_drift.py
python3 scripts/check_progress.py

UDID=$(python3 scripts/resolve_ios_simulator.py)
xcodebuild -project ios/AstraStyle.xcodeproj -scheme AstraStyle -destination "id=$UDID" build 2>&1 \
  | tee /tmp/build.log | tail -3
grep "warning:" /tmp/build.log | grep "ios/AstraStyle/"      # must print nothing

xcodebuild -project ios/AstraStyle.xcodeproj -scheme AstraStyle -destination "id=$UDID" \
  -only-testing:AstraStyleTests test                          # unit only, ~20s
xcodebuild -project ios/AstraStyle.xcodeproj -scheme AstraStyle -destination "id=$UDID" test
                                                              # full suite, UI tests add ~20 min
```

Backend, if needed:

```bash
supabase login
supabase link --project-ref <ref>
scripts/apply-migrations.sh --project-ref <ref>    # guarded; forces you to re-type the ref
scripts/deploy-functions.sh --project-ref <ref>
scripts/verify-deployment.sh --project-ref <ref>   # four real post-deploy checks
cd supabase/functions && deno task test            # covers _shared + outfits + profile + style-dna
```

**Expected baseline as of this handoff:** trust the latest green `iOS` workflow on `main` (PR #12 was green before merge). Local file counts and suite totals drift; do not treat older “525 tests / 262 files” numbers in this file as current.

---

## 12. Where to pick up

**Immediate owner request:** get a build on the owner's iPhone via **internal TestFlight**. Feature work after that should follow Phase 3 leftovers → Phase 4, not invent a new path.

### 12.0 ▶ TestFlight cut — instructions for Claude on the owner's Mac

> **Canonical copy lives in [`START_HERE.md`](START_HERE.md).** Prefer that file —
> agents keep missing this section inside a 1000+ line handoff. What follows is
> the same checklist kept here so deep links to §12.0 still work.

You are running on a **Mac with Xcode 26.6**. Linux/cloud agents already merged the Phase 3 exit to `main` (`86edb74` / PR #12) and **cannot** codesign or talk to App Store Connect. Your job is the Apple-side cut only. Twin doc: `docs/12-testflight-cut.md`.

#### Preconditions (stop and ask the owner if any fail)

- Active **Apple Developer Program** membership; owner signed into Xcode with the right Apple ID.
- App Store Connect app **Astra Style** exists (or create it) with bundle id **`com.astrastyle.app`** (see `ios/project.yml`).
- App ID has **Sign in with Apple** capability.
- An **internal TestFlight** group exists and includes the owner's Apple ID.
- Repo clone is current: `git checkout main && git pull`.
- `brew install xcodegen` if needed.

#### A. Secrets + generate the project

```bash
cd <repo>/ios
test -f Config/Secrets.xcconfig || cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# Ensure SUPABASE_URL + SUPABASE_ANON_KEY are filled.
# xcconfig footgun: write URLs as https:/$()/anutsdzbxycaavmmkewo.supabase.co
# (project ref from earlier handoffs — confirm with owner if unsure).
xcodegen generate
open AstraStyle.xcodeproj
```

#### B. Signing (Xcode UI — once per machine/team)

AstraStyle target → **Signing & Capabilities**:

- Team = owner's Personal Team / org
- Automatically manage signing = ON
- Bundle identifier = `com.astrastyle.app`
- Confirm **AppIcon** resolves (`Resources/Assets.xcassets` — marble 1024)

Do **not** commit `Secrets.xcconfig`, provisioning profiles, or `.p12` keys.

#### C. Build number

ASC rejects duplicate `CFBundleVersion`. Before each upload, bump `CURRENT_PROJECT_VERSION` in `ios/project.yml` (currently `"1"`; `MARKETING_VERSION` is `"1.0.0"`). Re-run `xcodegen generate` after editing. Commit the bump on a tiny branch/PR or direct-to-main per §0 convention — do not leave the archive on a dirty tree with an uncommitted version you already uploaded.

#### D. Archive and upload (preferred: Xcode Organizer)

1. Scheme **AstraStyle**, destination **Any iOS Device (arm64)** (not a simulator).
2. **Product → Archive**. Wait for Organizer.
3. **Distribute App → App Store Connect → Upload**.
4. Defaults are fine for first internal cut (bitcode N/A; strip Swift symbols as Xcode suggests).
5. When ASC finishes processing, App Store Connect → TestFlight → add the build to the **internal** group → enable for the owner.
6. On the iPhone: TestFlight app → install **Astra Style**.

CLI alternative if you prefer scriptable archive (still needs a signed team on the Mac):

```bash
cd <repo>/ios
xcodegen generate
xcodebuild archive \
  -project AstraStyle.xcodeproj \
  -scheme AstraStyle \
  -configuration Release \
  -archivePath build/AstraStyle.xcarchive \
  -destination 'generic/platform=iOS'
# Then distribute via Organizer / Transporter / `xcodebuild -exportArchive`
# with an ExportOptions.plist pointed at app-store distribution.
```

If Apple ID 2FA or "agree to new license" interrupts, **hand that click to the owner** — do not invent credentials or store app-specific passwords in the repo.

#### E. Optional — live vision for the phone build

Default Edge Function vision provider is **mock**. For real garment suggestions on device:

```bash
supabase login   # if needed
supabase link --project-ref anutsdzbxycaavmmkewo   # confirm ref with owner
supabase secrets set VISION_ANALYSIS_PROVIDER=openai OPENAI_API_KEY=sk-...
supabase functions deploy closet
```

Read `supabase/functions/closet/README.md` and `docs/08-provider-abstraction.md` §2.5 / §2.5.1 before inviting anyone else. Do not put `OPENAI_API_KEY` in iOS secrets.

#### F. Smoke checklist on the iPhone (report results to the owner)

1. Sign in with Apple or email → Home / Closet reachable. (No guest entry — ADR 0014.)
2. Manual add a garment → appears under category; detail wear count 0.
3. Scan or **Import** a shirt → editable review → Save → unlock copy → **Done**.
4. Airplane mode: Closet still shows cached items; start a scan → queued analysis copy; reconnect → analyze completes without re-capture.
5. Closet filters / metrics / mark worn — no crash.

#### G. Done criteria for this review

- Build visible in TestFlight internal group.
- Owner can launch the app on a physical iPhone.
- Smoke checklist results written back (pass/fail per step + any crash logs).
- If upload failed: paste the exact Organizer / `xcodebuild` error; common fixes are missing Sign in with Apple capability, wrong team, or stale build number.

**Out of scope for the TestFlight cut:** Fastlane/Match automation, ASC privacy nutrition labels, subscription products, public TestFlight, Phase 4 outfit generation.

---

### 12.1 What just landed (2026-08-01, `86edb74` / PR #12)

Phase 3 exit for an internal phone cut:

- Closet CRUD + free-tier 30-cap + offline read cache + `testAddGarment`
- Scanner single-item loop: capture/import → device hints → upload → analyze → review → save → unlock report
- Offline: LWW closet conflict on drain; pending scan queue that analyzes on reconnect
- App Icon + AccentColor asset catalog; `docs/12-testflight-cut.md`

Honest Phase 3 leftovers (do **not** block the TF cut): device Vision QA (`P3-SCAN-01`–`04` Partial), live OpenAI pilot gate (`P3-SCAN-07` Partial), batch/receipt/mirror (`P3-SCAN-08`/`12`), server cutout (`P3-SCAN-10`).

### 12.2 After TestFlight is on the phone — recommended next engineering

Only start this after §12.0 is done (or the owner explicitly prioritizes code over the phone build).

1. **Stale Scanner/Closet READMEs** — they still under/over-claim; align with `docs/03-progress.md`.
2. **Live vision pilot** — run docs/08 §2.5 gate against real menswear photos; flip `VISION_ANALYSIS_PROVIDER=openai` only after the gate.
3. **P3-SCAN-10** server background-removal fallback (load-bearing for messy real rooms — see Phase 3 risks in `docs/01-build-roadmap.md`).
4. **Phase 4** outfit intelligence per `docs/01-build-roadmap.md` / `docs/02-task-breakdown.md` — do not jump to Kyra/Studio screens while Daily Brief still lacks real outfit generation.
5. **`silhouette-2` quiz imagery** — still blocked on the owner’s OpenAI billing hard limit if not yet raised.

### 12.3 Phase 3 debts that are already Done (do not rebuild)

These used to be the “pick up next” list; they shipped before/with PR #12 — verify in `docs/03-progress.md` before rewriting:

- `P3-SCAN-05` / `P3-SCAN-06` / `P3-SCAN-09` / `P3-SCAN-11`
- `P3-CLOSET-02` offline read cache, `P3-CLOSET-11` free-tier cap, `P3-TEST-02` UI test
- `P3-INFRA-01` LWW conflict, `P3-INFRA-02` pending scan queue
- `closet` Edge Function + OpenAI adapter **code** (pilot gate still unrun)

### 12.4 Housekeeping worth doing early (non-blocking)

- Reconcile capture corpus count comments in `CaptureQuality.swift` (34 vs 36).
- Fold `MeasurementFormatting.formattedPrice` into `CurrencyFormatting` carefully (locale fallback behaviour differs — not a pure move).
- Consider CI→TestFlight later **only with an ADR** (Fastlane/Match is a new dependency) and ASC API key secrets — not required for the first internal cut.

---

## 13. Quick reference

### 13.1 Files to read first, in order

1. **`START_HERE.md`** (TestFlight cut — open this first on the owner's Mac)
2. `CLAUDE.md`
3. `docs/00-master-spec.md`
4. `docs/03-progress.md`
5. `docs/02-task-breakdown.md` (for the ticket you're picking up)
6. The relevant `docs/adr/000X-*.md`
7. `.github/workflows/ios.yml` and the six `scripts/check_*.py` — so you know what will reject you before you write code that trips it
8. `Features/Home/ViewModels/HomeViewModel.swift` — the pattern everything else copies

### 13.2 Endpoints and their deployment state

Five slugs are deployed to `anutsdzbxycaavmmkewo`, verified 2026-08-06 via
`list_edge_functions`: `profile`, `style-dna`, `outfits`, `closet`,
`daily-brief` — all `verify_jwt: true`. **"Built" and "deployed" are different facts and this table
tracks the second**, because `closet` sat fully written and fully tested in the
repo for five days while every client call to it 404'd.

| Endpoint | Method | Slug | State |
|---|---|---|---|
| `profile/complete-onboarding` | POST | `profile` | ✅ deployed |
| `style-dna/generate` | POST | `style-dna` | ✅ deployed |
| `outfits/generate` | POST | `outfits` | ✅ deployed |
| `outfits/rank` | POST | `outfits` | ⚠️ slug deployed, route not built |
| `closet/analyze-item` | POST | `closet` | ✅ deployed 2026-08-06 (mock vision provider) |
| `closet/batch-analyze` | POST | `closet` | ✅ deployed 2026-08-06 (job + poll) |
| `closet/batch-status/{uuid}` | GET | `closet` | ✅ deployed 2026-08-06 |
| `daily-brief/generate` | POST | `daily-brief` | ✅ deployed 2026-08-06 (idempotent per `brief_date`) |
| `kyra/respond` | POST | `kyra` | ❌ |
| `products/extract` | POST | `products` | ❌ |
| `products/evaluate` | POST | `products` | ❌ |
| `studio/generate` | POST | `studio` | ❌ |
| `studio/status/{uuid}` | GET | `studio` | ❌ |
| `packing/generate` | POST | `packing` | ❌ |
| `subscriptions/sync` | POST | `subscriptions` | ❌ |
| `app-store/webhook` | POST | `app-store` | ❌ (auths by shared secret, not JWT) |
| `account` | DELETE | `account` | ❌ (runbook is the migration header) |

### 13.3 Repository protocols

| Protocol | Conformances |
|---|---|
| `AuthRepository` | Live, Mock |
| `ClosetRepository` | Live, **FreeTierCapped** (the one injected), Mock |
| `ClosetImageURLResolving` | Live, Mock |
| `OutfitRepository` | Live, Mock |
| `KyraRepository` | Live, Mock |
| `ProfileRepository` | Live, Mock |
| `ShoppingRepository` | Live, Mock |
| `StudioRepository` | Live, Mock (simulates queued→generating→complete across polls) |
| `SubscriptionRepository` | Live, Mock |
| `CalendarService` | Live (EventKit), Mock |
| `WeatherService` | Live (WeatherKit + CoreLocation), Mock |

`fetchWardrobeScore()` throws `AstraError.unimplemented` unconditionally — there is no `wardrobe_scores` table and no conforming `WardrobeScoring` implementation. **`ClosetViewModel` deliberately never calls it**, because *"calling it to render a score would put a permanent, unwinnable error on the closet's first screen."*

### 13.4 Things that will silently do the wrong thing

| If you… | …this happens |
|---|---|
| Build a storage path from `UUID.uuidString` | Every object 403s under RLS, silently |
| Add a `CodingKey` with no matching column | `check_column_drift.py` fails — or, if it slips through, an Optional property decodes `nil` forever with no error |
| Add a Swift `enum: String` without classifying it | `check_schema_drift.py` hard-fails |
| Pass a whole closet to `averageCostPerWear` | Silently deflated average (numerator over priced items, denominator over all) |
| Assign `onSaved` on a form view model built by a factory | You drop the factory's own handler; the save succeeds and the screen doesn't update |
| Invent a new server error `category` | It collapses to `.server` on the client rather than failing loudly |
| Read `BUILD SUCCEEDED` and stop | Warnings shipped; CI's grep will catch it, you won't |
| Trust a module `README.md` for status | Several are stale in both directions |

---

## 14. The house style, in one paragraph

Every non-obvious decision carries a comment saying **why**, not what — and those comments are the project's real design record, quoted throughout this document because they are better than any summary of them. Thresholds are measured against real data and the measurement is written down. A gap is named rather than filled with a plausible substitute. A control that cannot do anything is removed rather than disabled. A test that cannot run is skipped **with a reason naming the ticket that will close it**, never deleted to make CI green. A status row that overclaims is worse than one that says Partial. And when something turns out to be wrong — the vendor choice, the DTO shape, an acceptance criterion, a threshold that took four passes — it gets corrected at the source, with the reversal recorded, rather than quietly patched over.

Match that and you'll fit in fine.

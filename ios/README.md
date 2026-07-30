# Astra Style — iOS

Native iPhone app for Astra Style, a premium personal-stylist and wardrobe operating system for men, with an AI companion named Kyra. iOS 18+, Swift 6, SwiftUI, SwiftData, Supabase. See `/docs/00-master-spec.md` for the full product/technical specification this codebase implements.

## Prerequisites

- macOS with Xcode 16 or later (iOS 18 SDK, Swift 6 toolchain).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- A Supabase project (or access to the shared dev project) for `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
- CocoaPods is **not** used — dependencies are Swift Package Manager only (see `project.yml`'s `packages:` section, currently `supabase-swift`).

This repository does not include a Swift toolchain or Xcode, and the project has never been opened in Xcode or compiled — see "Verification status" below for exactly what was and wasn't checked.

## 1. Generate the Xcode project

The `.xcodeproj` is intentionally **not** committed (see `.gitignore`) — it's generated from `project.yml` so merge conflicts in a binary/plist-like project file never happen.

```bash
cd ios
xcodegen generate
open AstraStyle.xcodeproj
```

Re-run `xcodegen generate` any time `project.yml` changes, or any time you add/remove/rename a file or folder under `AstraStyle/` — XcodeGen's `sources:` entry in `project.yml` walks the directory tree automatically, so this is the only file-management step required (no manual "Add Files to project" in Xcode).

## 2. Configure secrets

Per spec §25, the client ships with exactly two values — `SUPABASE_URL` and `SUPABASE_ANON_KEY` — and nothing else. Everything else (service role keys, AI provider keys, webhook secrets) lives only in Supabase Edge Function environment variables and must never appear in this repository.

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Then edit `Config/Secrets.xcconfig` and fill in your project's real values. **Read the comment block at the top of `Config/Base.xcconfig` first** — `.xcconfig` files treat an unescaped `//` as the start of a line comment, which silently truncates a plain `https://...` URL. Every URL-valued entry must break up its `//` with an empty macro reference, e.g.:

```
SUPABASE_URL = https:/$()/xyzcompany.supabase.co
```

`Config/Secrets.xcconfig` is gitignored; `Config/Secrets.example.xcconfig` (the template, with placeholder values) is committed. If `AstraEnvironment.current` sees a missing or still-placeholder value at launch, it fails fast with a `preconditionFailure` naming exactly this fix, rather than the app silently failing every network call.

## 3. Run

Select the `AstraStyle` scheme and a simulator or device running iOS 18+, then Cmd-R. The app boots into `AppContainer.live()` (real Supabase networking) by default; SwiftUI previews use `AppContainer.preview()` (in-memory mocks, `Core/Mocks/`) and never touch the network.

## 4. Test

```bash
xcodebuild test -project AstraStyle.xcodeproj -scheme AstraStyle -destination 'platform=iOS Simulator,name=iPhone 16'
```

or Cmd-U in Xcode. Unit tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) per iOS 18's minimum deployment target; UI tests use **XCUITest**, which Swift Testing doesn't cover.

Every test in `Tests/UnitTests/PendingIntegrationRequirementsTests.swift` and in `Tests/UITests/AstraStyleUITests.swift` is an **explicitly skipped placeholder** for a spec §22 requirement that needs real backend/StoreKit/UI infrastructure this scaffold doesn't have yet (a live Supabase project, deployed Edge Functions, a StoreKit sandbox tester, and the still-scaffolded feature screens themselves). The unit ones carry Swift Testing's `.disabled(reason:)`; the UI ones `throw XCTSkip(...)`. Each skip reason names the spec requirement and the ticket prefix expected to close it, so the gap is reported rather than silently missing — and the suite can still be green, which is what makes a genuine failure worth reading. They were previously written as `Issue.record`/`XCTFail` bodies; that made the iOS job permanently red, which hid real regressions instead of highlighting these. Do not delete them to make CI green; replace them with real tests — dropping the skip at that point, not before — as their dependencies land.

## 5. Supabase setup (backend)

This directory is the iOS client only. The Postgres schema, RLS policies, and Edge Functions live under `/supabase/` at the repo root (migrations, `supabase/functions/`). Broadly:

```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase db push                 # applies migrations
supabase functions deploy        # deploys the 16 Edge Functions in spec §14
```

Every Edge Function needs its own environment variables set via `supabase secrets set` — see spec §25 for the full list (`SUPABASE_SERVICE_ROLE_KEY`, `STYLIST_PROVIDER_API_KEY`, `VISION_PROVIDER_API_KEY`, `IMAGE_PROVIDER_API_KEY`, `EMBEDDING_PROVIDER_API_KEY`, `WEATHER_PROVIDER_KEY_IF_USED`, `AFFILIATE_PROVIDER_KEYS`, `APP_STORE_SHARED_CONFIGURATION`). None of these are ever referenced from this iOS project.

## 6. StoreKit configuration

For local sandbox testing without hitting App Store Connect:

1. In Xcode, File > New > File > StoreKit Configuration File.
2. Add two auto-renewable subscription products matching `Domain/Models/Subscription.swift`'s `AstraProductID`: `com.astrastyle.app.premium.monthly` ($12.99) and `com.astrastyle.app.premium.annual` ($79.99), per spec §16.
3. Edit the scheme's Run action > Options > StoreKit Configuration to select the file.
4. `SubscriptionRepository.syncTransaction(_:)` forwards verified transactions to `POST /subscriptions/sync`; the real product catalog and pricing are still owned by App Store Connect for TestFlight/production builds.

## Project layout

```text
ios/
  project.yml              XcodeGen project definition
  Config/                  .xcconfig files (Base/Debug/Release/Secrets)
  AstraStyle/
    App/                   @main entry, root routing, tab shell, DI container
    Core/
      DesignSystem/        owned by a separate workstream — tokens/components
      Networking/          AstraAPIClient, typed endpoints, Live/ repository adapters
      Persistence/         SwiftData cache models + offline mutation queue
      Auth/                SessionStore, Keychain-backed session persistence
      Analytics/           typed AnalyticsEvent enum + AnalyticsClient protocol
      Utilities/           formatting, cost-per-wear, image downsampling, reachability
      Mocks/                in-memory repository conformances + sample wardrobe data
    Domain/
      Models/               Codable value types mirroring spec §9's tables
      Repositories/          protocol-only — Auth/Profile/Closet/Outfit/Kyra/Studio/Shopping/Subscription + Weather/Calendar services
      Services/               CompatibilityScoring, WardrobeScoring, OfflineMutationQueue protocols
    Features/                 one folder per spec §4 tab + supporting flows; each has its own README
      Home/                    fully implemented — the reference module every other feature is patterned after
      Onboarding/ Closet/ Scanner/ Outfits/ Studio/ Kyra/ Shopping/ Discover/ Profile/ Subscription/
                               scaffolded (folder structure + README only) — see docs/02-task-breakdown.md
    Resources/                 Info.plist, asset catalog, entitlements
    Tests/
      UnitTests/               Swift Testing
      UITests/                 XCUITest
```

## Code quality bar

- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete` in `project.yml`); every view model is `@MainActor` + `@Observable`.
- No force unwraps, no `try!`, anywhere in the codebase.
- No network calls in `View` bodies — every repository call happens inside a view model or a `Services/` façade, never a `Views/` file.
- Every public protocol has a doc comment explaining what it's for and which spec section governs it.
- No hardcoded user-facing strings — every string goes through `String(localized:)` in a String-Catalog-ready form (literal text doubles as the extraction key, matching Xcode's `.xcstrings` workflow).

## Verification status (read this before trusting anything above)

**No Swift toolchain is available in the environment that produced this scaffold** (`which swift swiftc xcodebuild xcodegen` all returned nothing). Nothing in this repository has been compiled, and no claim of "it builds" should be inferred from its presence. What *was* verified:

- `project.yml` parses as valid YAML (`python3 -c "import yaml; yaml.safe_load(open('project.yml'))"`).
- A manual, file-by-file review pass for: obviously missing `import` statements, force unwraps / `try!`, Swift 6 actor-isolation mistakes (e.g. a `@MainActor`-isolated type conforming to a `Sendable` protocol, `@ModelActor` usage for SwiftData off-main-thread access), naming consistency against the `AstraColor` / `AstraTypography` / `AstraSpacing` / `AstraMotion` / `AstraCard` / `AstraButton` / `AstraTheme` API this codebase assumes (see below), and `CodingKeys` completeness against spec §9's column lists.

Before the first real build, expect to fix:

1. **DesignSystem API mismatches.** This codebase was built against an *assumed* API for `AstraColor` (color tokens as static `Color` properties matching spec §3's names exactly), `AstraTypography` (static `Font` properties: `displayXL/L`, `title1/2`, `headline`, `body`, `callout`, `caption`, `micro`), `AstraSpacing` (a 4pt scale: `xxs/xs/sm/md/lg/xl` plus named constants `pagePadding`, `cardRadius`, `buttonRadius`), `AstraMotion` (e.g. `AstraMotion.standard` as an `Animation`), and `AstraCard`/`AstraButton` as simple wrapping components (`AstraButton(title:isLoading:action:)`). DesignSystem is owned by a separate workstream building concurrently — reconcile the real API against every call site once it lands.
2. **`supabase-swift` API surface.** `Core/Networking/Live/*.swift` and `Core/Auth/SessionStore.swift` were written against the general shape of `supabase-swift`'s `SupabaseClient` (`.auth.signInWithIdToken`, `.auth.verifyOTP`, `.auth.refreshSession`, `.from(...).select()/.insert()/.update()/.execute().value`, `.storage.from(...).upload/.createSignedURL`) from memory, not against the installed package — check these compile once SPM resolves the real dependency, especially method signatures that vary between major versions.
3. **WeatherKit/EventKit/CoreLocation entitlements.** `LiveWeatherService` uses WeatherKit and the iOS 17+ `CLLocationUpdate.liveUpdates()` async API; WeatherKit requires the WeatherKit capability enabled in the Apple Developer portal and added to the app's entitlements (not currently in `AstraStyle.entitlements` — add it there).

## Spec ambiguities encountered

- **§6.7 Appearance profile** (skin undertone, hair color, facial hair, glasses, tattoo visibility, reference selfies) has no corresponding table in §9's authoritative data model. `Domain/Models` does not invent one; `Features/Onboarding/README.md` flags this.
- **Wishlist** (spec §5.5, §6.18 "Add to wishlist") has no table in §9 either. `LiveShoppingRepository` assumes a `wishlist_items` join table (`user_id`, `product_candidate_id`, `purchased_at`) — reasonable, but not spec-authoritative; confirm against the real schema/migrations under `/supabase/`.
- **Personal data export** (§29) has no corresponding endpoint in §14's 16-endpoint list. `LiveProfileRepository.exportPersonalData()` assumes a signed Storage URL convention (`exports/users/{id}/export-latest.json`) rather than inventing a 17th endpoint.
- **Discover and Profile's owning tickets** are ambiguous against the nine ID prefixes given (P1-CORE, P2-ONBOARD, P3-CLOSET, P3-SCAN, P4-OUTFIT, P5-KYRA, P6-STUDIO, P6-SHOP, P7-SUB) — neither module maps cleanly onto one. Each module's README records a best guess and flags it for confirmation once `docs/02-task-breakdown.md` is finalized.

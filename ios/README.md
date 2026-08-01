# Astra Style — iOS

Native iPhone app for Astra Style, a premium personal-stylist and wardrobe operating system for men, with an AI companion named Kyra. iOS 18+, Swift 6, SwiftUI, SwiftData, Supabase. See `/docs/00-master-spec.md` for the full product/technical specification this codebase implements. Per-ticket status lives in `/docs/03-progress.md`; a cold-start narrative is in `/HANDOFF.md`.

## Prerequisites

- macOS with **Xcode 26.6** exactly (CI pins it; matches the owner's machine). The line "Xcode 16 or later" that once lived here is stale.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- A Supabase project (or access to the shared dev project) for `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
- CocoaPods is **not** used — dependencies are Swift Package Manager only (see `project.yml`'s `packages:` section, currently `supabase-swift`).

The project builds and tests. Trust `docs/03-progress.md` for what is Done vs Partial, not directory names under `Features/`.

## 1. Generate the Xcode project

The `.xcodeproj` is intentionally **not** committed (see `.gitignore`) — it's generated from `project.yml` so merge conflicts in a binary/plist-like project file never happen.

```bash
cd ios
xcodegen generate
open AstraStyle.xcodeproj
```

Re-run `xcodegen generate` any time `project.yml` changes, or any time you add/remove/rename a *directory* under `AstraStyle/`. New files under an existing directory are picked up by the recursive glob without a project edit.

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

Prefer a UDID from the resolver (hardcoded device names break when the runner's runtimes change):

```bash
xcodebuild test -project AstraStyle.xcodeproj -scheme AstraStyle \
  -destination "id=$(python3 ../scripts/resolve_ios_simulator.py)"
```

or Cmd-U in Xcode. Unit tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`); UI tests use **XCUITest**.

`BUILD SUCCEEDED` from `xcodebuild` does **not** mean the warning gate passed — CI greps the build log for first-party warnings. Local equivalent:

```bash
xcodebuild -project AstraStyle.xcodeproj -scheme AstraStyle \
  -destination "id=$(python3 ../scripts/resolve_ios_simulator.py)" build 2>&1 \
  | grep "warning:" | grep "ios/AstraStyle/"
```

It must print nothing. Also run `swiftlint --strict` and the Python checkers under `scripts/` before pushing.

Several UI / integration tests remain deliberately skipped (`XCTSkip` / `.disabled`) with reasons naming the ticket that will close them. Do not delete skips to make CI green; replace them with real tests when their dependencies land.

## 5. Supabase setup (backend)

This directory is the iOS client only. The Postgres schema, RLS policies, and Edge Functions live under `/supabase/` at the repo root. Broadly:

```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase db push                 # applies migrations
supabase functions deploy        # deploys existing function slugs (see supabase/README.md)
```

Every Edge Function needs its own environment variables set via `supabase secrets set` — see spec §25. None of these are ever referenced from this iOS project.

## 6. TestFlight (iPhone)

Internal device builds: see **`docs/12-testflight-cut.md`**. Short version — generate the project, set your Development Team in Xcode, Archive → Upload to App Store Connect, add the build to an internal TestFlight group. App Icon lives in `AstraStyle/Resources/Assets.xcassets`.

## 7. StoreKit configuration

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
      DesignSystem/        tokens and components (AstraColor, AstraTypography, …)
      Networking/          AstraAPIClient, typed endpoints, Live/ repository adapters
      Persistence/         SwiftData cache models + offline mutation queue
      Auth/                SessionStore, Keychain-backed session persistence
      Analytics/           typed AnalyticsEvent enum + AnalyticsClient protocol
      Utilities/           formatting, cost-per-wear, image downsampling, reachability
      Mocks/               in-memory repository conformances + sample wardrobe data
    Domain/
      Models/              Codable value types mirroring spec §9's tables
      Repositories/        protocol-only seams
      Services/            CompatibilityScoring, WardrobeScoring, OfflineMutationQueue
    Features/
      Home/                fully implemented — the reference module
      Onboarding/          Style DNA flow (most complete product flow)
      Closet/              overview, metrics, filters, detail, manual form — usable end to end
      Scanner/             capture → hints → review → save; offline queue; unlock report
      Profile/             guest profile + create-account; signed-in Profile still thin
      Outfits/ Studio/ Kyra/ Shopping/ Discover/ Subscription/
                           README-only — zero Swift files yet
      Slice/               DEBUG vertical slice; throwaway — do not copy as a pattern
    Resources/             Info.plist, entitlements, QuizImagery
    Tests/
      UnitTests/           Swift Testing
      UITests/             XCUITest
```

## Code quality bar

- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete` in `project.yml`); every view model is `@MainActor` + `@Observable`.
- No force unwraps, no `try!`, anywhere in the codebase.
- No network calls in `View` bodies — every repository call happens inside a view model or a `Services/` façade, never a `Views/` file.
- Every public protocol has a doc comment explaining what it's for and which spec section governs it.
- No hardcoded colours/fonts/spacing — use `Astra*` tokens. User-facing strings go through `String(localized:)`.

## Spec ambiguities encountered

- **§6.7 Appearance profile** (skin undertone, hair color, facial hair, glasses, tattoo visibility, reference selfies) has no corresponding table in §9's authoritative data model. `Domain/Models` does not invent one; `Features/Onboarding/README.md` flags this.
- **Wishlist** (spec §5.5, §6.18 "Add to wishlist") has no table in §9 either. `LiveShoppingRepository` assumes a `wishlist_items` join table — confirm against migrations under `/supabase/`.
- **Personal data export** (§29) has no corresponding endpoint in §14's endpoint list. `LiveProfileRepository.exportPersonalData()` assumes a signed Storage URL convention rather than inventing a new endpoint.

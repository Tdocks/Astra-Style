# 13 — Screen QA Sweep

A visual pass over every screen the app can currently reach, run on the simulator rather than
reviewed by reading code. Repeatable: `Tests/UITests/ScreenQAUITests.swift` walks the surface and
attaches a screenshot per screen.

```bash
cd ios
xcodebuild test -project AstraStyle.xcodeproj -scheme AstraStyle \
  -destination 'platform=iOS Simulator,id=<sim-udid>' \
  -only-testing:AstraStyleUITests/ScreenQAUITests \
  -resultBundlePath /tmp/qa.xcresult
xcrun xcresulttool export attachments --path /tmp/qa.xcresult --output-path ./shots
```

The sweep asserts reachability and anchor content, not pixels. Snapshot-diffing this early would
fail on every intentional design change and train everyone to ignore it.

## Toolchain (verified 2026-07-29)

| | |
|---|---|
| Xcode | 26.6 (17F113) |
| macOS | 26.6 |
| Simulator runtime | **iOS 26.5** — confirmed newest; `xcodebuild -downloadPlatform iOS` resolves to 26.5 |
| Deployment target | iOS 18.0 (minimum supported — distinct from the OS it runs on) |
| supabase-swift | 2.54.0 — matches the latest GitHub release |
| Deno (Edge Functions) | 2.9.4 |

## Findings

Seven defects, all fixed and re-verified.

### 1. A guest landed on a broken Home — severe

Enter guest mode, skip onboarding, and Home rendered **"Something went wrong / Couldn't load your
profile."** `DefaultHomeBriefProvider.loadTodayBrief` called `fetchCurrentProfile()` unguarded, and
guests have no server profile at all (ADR 0011). The first thing a guest saw was an error.

Fixed by branching on session type before any network call. A guest now gets the real empty state
driven by their local closet count.

### 2. A rejected session was a dead end

Launch routing sent a user to `.main` whenever the profile fetch failed. For a genuinely invalid
session that meant landing on a broken Home with **no route back to sign-in**. `withDeadline` now
distinguishes *timed out* from *failed*: a slow network still lets the user in, while an `auth`
failure clears the session and returns to Welcome.

### 3. Light mode was unreachable, so the whole light palette was dead code

`UIUserInterfaceStyle: Dark` in Info.plist is a UIKit-level override that beats SwiftUI's
`.preferredColorScheme`. Spec §3 defines a full light palette, doc 07 records a WCAG audit of it,
and `accentChampagneAccessible` was added specifically to fix a light-mode contrast failure — none
of it had ever rendered. Removed; dark remains the default via `AppSettings`.

### 4. Two contrast failures light mode immediately exposed

Making light mode reachable proved its own worth within one screenshot:

- Legal links used `accentChampagne`, which is `#B8914E` in light mode — **2.68:1, failing WCAG AA**
  and barely legible. Now `accentChampagneAccessible` (4.62:1).
- The marble scrim used `backgroundPrimary`, so in light mode a *light* scrim washed the black
  stone out to pale grey and dragged every label with it. Marble is a brand texture that does not
  flip with the theme; the scrim is now a fixed near-black, and `.astraOnMarble()` forces content
  over it to resolve dark-scheme tokens.

### 5. Text truncated at the largest Dynamic Type size

At AX5 the Welcome screen showed "Meet Kyra, your per…", "Explore in guest m…", "Terms of S… ·
Privacy…". Spec §19 requires *full* Dynamic Type support. Now scrolls and wraps, with the
Terms/Privacy row reflowing vertically via `ViewThatFits`. Base font sizes untouched — shrinking
them would penalise every user to satisfy one size class.

### 6. CI would have failed on every single run

`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` as an xcodebuild command-line setting applies to **every**
target including SwiftPM dependencies, and four of ours compile with `-suppress-warnings`:

```
error: Conflicting options '-warnings-as-errors' and '-suppress-warnings'
  (in target 'Crypto' from project 'swift-crypto')
```

It failed before compiling a line of our code. Replaced with a log-scan step scoped to
`ios/AstraStyle/`, which is strictly more accurate: zero warnings in our sources without making us
responsible for third-party ones.

### 7. Eighty-five concurrency warnings in the UI tests

XCUITest's element APIs are `@MainActor` in the iOS 26 SDK. Both test classes needed `@MainActor`,
and `setUpWithError()` had to become `setUp() async throws` — the throwing synchronous override
stays nonisolated even on a `@MainActor` class.

Also: SwiftUI `Link` surfaces as a **button**, not a link, so `app.links["Terms of Service"]` never
matched. The links carry accessibility identifiers now.

## Cosmetic

The guest greeting read "Good evening, there." — a mail-merge fallback, and the opposite of a
personal stylist. The name clause is now dropped when there is no name.

## Known placeholders (not defects)

Closet, Studio, Discover, Profile and the onboarding step are intentional `FeaturePlaceholderView`
stand-ins for Phases 2–7. Onboarding's "Skip for now" is a temporary bypass and must not ship.

## Still open

Spec §6.22 requires a theme control in Profile and `profiles.theme` exists in the schema, but there
is no UI to change it — so light mode is reachable in code and in tests, and still not by a user.
That belongs with the real Profile screen.

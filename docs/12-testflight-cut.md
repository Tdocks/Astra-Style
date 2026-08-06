# 12 — TestFlight cut (internal iPhone)

How to put current `main` (`86edb74`+, Phase 3 exit) on the owner's iPhone via
TestFlight. Cloud / Linux agents cannot complete the Apple-side steps —
signing, App Store Connect, and `xcodebuild archive` need the owner's Mac +
Apple ID.

**If you are Claude Code on that Mac:** open **`START_HERE.md` at the repo root**
first — that is the canonical checklist. Situation brief:
[`CLAUDE_HANDOFF.md`](../CLAUDE_HANDOFF.md). `HANDOFF.md` §12.0 is older cold-start
context. This file is the short twin. **CLI-only agents:** 
[`ios/CLI_BUILD_AND_TESTFLIGHT.md`](../ios/CLI_BUILD_AND_TESTFLIGHT.md).

**Status 2026-08-06:** `1.0.0 (1)` installed on owner's iPhone. Next: smoke
checklist in `START_HERE.md` §6 — report pass/fail.

## What you get on device

After Phase 3 exit work lands, a TestFlight build is useful for:

- Sign-in / guest, onboarding, Home shell
- Closet browse, filters, metrics, manual add/edit, mark worn / archive
- Single-item scan: capture or Photos import → device hints → upload → analyze →
  correct → save → unlock-count report
- Offline: closet read cache; queued scan while offline that analyzes on reconnect
- Free-tier 30-item and guest 10-item caps

Still Partial / deferred (honest gaps):

- Live vision defaults to **mock** until you set `VISION_ANALYSIS_PROVIDER=openai`
  + `OPENAI_API_KEY` on the Supabase project (see `supabase/functions/closet/README.md`)
- Batch / receipt / mirror capture modes
- Server background-removal fallback
- Versatility metric, item insights, care instructions (Phase 4 data)

## Prerequisites (once)

1. **Apple Developer Program** membership active.
2. App Store Connect → **My Apps** → create **Astra Style** if missing  
   Bundle ID: `com.astrastyle.app` (matches `ios/project.yml`).
3. Enable **Sign in with Apple** for that App ID (Capabilities).
4. Create an **internal TestFlight** group and add your Apple ID.
5. On your Mac: Xcode **26.6**, XcodeGen (`brew install xcodegen`), repo secrets.

## One-time Xcode signing

```bash
cd ios
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# Fill SUPABASE_URL / SUPABASE_ANON_KEY (escape // per Base.xcconfig comments)
xcodegen generate
open AstraStyle.xcodeproj
```

In the AstraStyle target → Signing & Capabilities:

- Team: your Personal Team / org
- Automatically manage signing: ON
- Confirm bundle id `com.astrastyle.app`

App Icon now ships in `AstraStyle/Resources/Assets.xcassets/AppIcon.appiconset`
(from `brand/assets/app-icon-marble.jpg`). Confirm it shows in the target’s
App Icons source.

For distribution builds, flip `aps-environment` in
`AstraStyle/Resources/AstraStyle.entitlements` from `development` to
`production` if you enable push later — not required for first internal TF.

## Cut a build

Prefer Archive from Xcode (Product → Archive → Distribute App → App Store Connect
→ Upload). Or CLI:

```bash
cd ios
xcodegen generate
xcodebuild archive \
  -project AstraStyle.xcodeproj \
  -scheme AstraStyle \
  -configuration Release \
  -archivePath build/AstraStyle.xcarchive \
  -destination 'generic/platform=iOS'
```

Then distribute the archive via Organizer / Transporter to App Store Connect.
When processing finishes, add the build to your internal TestFlight group and
install from the TestFlight app on your iPhone.

Bump `CURRENT_PROJECT_VERSION` (and optionally `MARKETING_VERSION`) in
`ios/Config/Base.xcconfig` or `project.yml` before each new upload — ASC rejects
duplicate build numbers.

## Point the build at real vision (optional but recommended)

On the Supabase project that `Secrets.xcconfig` targets:

```bash
supabase secrets set VISION_ANALYSIS_PROVIDER=openai OPENAI_API_KEY=sk-...
supabase functions deploy closet
```

Follow the pilot checklist in `docs/08-provider-abstraction.md` §2.5 / §2.5.1
before inviting anyone outside yourself.

## Smoke checklist on phone

1. Guest or Sign in with Apple → reach Home / Closet.
2. Manual add a garment → appears under its category; detail wear count 0.
3. Scan (or Import) a shirt → review fields editable → Save → unlock copy → Done.
4. Airplane mode: open Closet (cached items); start a scan, confirm queued
   analysis copy; reconnect and confirm analyze completes without re-capture.
5. Confirm no crash on Closet filters / metrics / mark worn.

## App Store Connect Privacy Policy URL

If ASC requires a URL on the app record: `https://astra-style.com/privacy/`
(Draft banner on purpose). Do **not** flip `AstraLegal.isPublished`
(`P7-PRIVACY-05`).

## What this doc is not

- Not ASC screenshots, privacy nutrition labels, or subscription products
  (`P7-INFRA-05` / `P7-SUB-*`).
- Not publishing counsel-cleared legal docs (`P7-PRIVACY-05`).
- Not CI→TestFlight automation (no Fastlane/Match in-repo yet).
- Not a substitute for measured 60 fps / device Vision acceptance criteria —
  those stay Partial until you run them on hardware.

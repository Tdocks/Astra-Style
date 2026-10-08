# START HERE — Claude on the owner's Mac

> If you are fixing **astra-style.com / privacy / the marketing site**: wrong file.
> Open **[`web/CLAUDE.md`](web/CLAUDE.md)** (sources in `web/` + `legal/`, not `ios/`).
> Deploy brief: [`web/GATE.md`](web/GATE.md).

**Your only job right now:** keep the **public TestFlight** current. A stranger
installs [the External join link](https://testflight.apple.com/join/mU5pC1RW)
and must complete guest → Closet/scan → Wear This → Shop → Discover Unlocks →
Studio without hitting a dead chrome tab.

Do **not** dig through `HANDOFF.md` landmines, rewrite READMEs, or start Phase 5
Kyra. Do **not** treat older “internal TestFlight / no guest” commits as the
current brief.

| Fact | Value |
|---|---|
| Branch | `main` (pull latest) |
| Bundle ID | `com.astrastyle.app` |
| Xcode | **27.0** on the owner's Mac for builds 12–19 (previous release used 26.6) |
| Marketing version | `1.0.0` (`ios/project.yml`) |
| Build number | bump `CURRENT_PROJECT_VERSION` before each upload (now `20`) |
| Public join | https://testflight.apple.com/join/mU5pC1RW |
| External group | `cdf6feb8-9fcd-451e-87cb-c1f6983600bf` |
| Supabase project ref | `anutsdzbxycaavmmkewo` (confirm with owner if unsure) |
| Twin docs | `docs/12-testflight-cut.md`, `ios/CLI_BUILD_AND_TESTFLIGHT.md` |

## Current internal release — 2026-10-08

Version **1.0.0 (20)** is **VALID** and **IN_BETA_TESTING** in the Internal group
(build ID `5cba6279-9473-450e-bdff-6783bc30b096`). Build 20 adds runtime
session renewal, concurrent request coordination, sign-out safety and offline
credential recovery. Nineteen session/network tests and the mock Kyra UI flow
passed. en-US testing notes are saved. Device lifecycle and hosted token-rotation
acceptance remain open. External review is not submitted; the public group still
uses build 11. See `docs/session-refresh-acceptance.md`.

## Previous internal release — build 19

Version **1.0.0 (19)** is processed **VALID** and **IN_BETA_TESTING**, with
membership confirmed in the Internal group (build ID `2eced5aa-8742-4521-b790-cfab94d067b6`).
Build 19 adds editable Studio image descriptions with garment-based defaults,
VoiceOver labels, generated-image disclosure on Home inspiration, and Reduce
Motion fixes. It includes the earlier Home contextual generation, private
collections, comparison, labeled image sharing and server-owned image erasure.
Studio backend is ACTIVE v15 and Profile v16, with server-owned jobs, durable trial accounting,
private collections and owned export support. Studio-retention v2 is active with a verified five-minute Cron schedule. Saved and dependent outputs are protected; server-owned individual deletion is deployed (ADR 0025). Builds through 16 can no longer use their old direct Studio deletion path; build 17 uses the new endpoint. Build 18 adds atomic reference-photo cascading and tracked cleanup (ADR 0026). The configurable 24-hour abandoned-reference sweep is deployed and enabled. Guest Storage uploads and replacements are blocked using the signed anonymous JWT claim (ADR 0027).
External beta review for builds 12–19 has not been submitted;
the public link still serves build 11. Use Internal TestFlight for the owner's checks.
See `docs/home-inspiration-device-checks.md` and `docs/studio-comparison-live-acceptance.md`.

Build 19 passed the simulator build and first-party warning gate, nine Swift
description/export tests and eleven mock UI flows: eight core flows, Home
inspiration and both description-editor layouts (standard dark and light
Accessibility XXXL). Studio/Profile backend tests: 111 passed. SQL restrictions
and live owner save/reset, peer denial, status/export persistence and QA erasure
passed. TestFlight notes are saved in en-US. This is selected acceptance coverage,
not a complete physical-device or live-provider UI pass.

Build 18 passed the simulator build and warning gate, 18 reference/Studio/endpoint Swift tests, 89 backend tests, the SQL isolation suite including guest Storage restrictions, four reference concurrency orderings and both generated-source deletion orderings. All eight core simulator flows and both reference-removal flows passed (10 UI tests, zero failures), including light theme at Accessibility XXXL. Live checks passed atomic recursive reference deletion, preserved unrelated photos, safe export, consumed-credit preservation, abandoned cleanup and guest upload denial even after editable metadata spoofing. Earlier Home, comparison, sharing and collection checks are documented in their acceptance reports; this is not a full-app end-to-end pass.
Disposable-account live checks passed image generation, Kyra, scoped export and account deletion after schema repairs.
The simulator uses mock images; personal-reference quality, edit consistency and closet fidelity still need device checks.
Image-file sharing unit tests and a serial simulator sharing flow passed; sharing is included in build 14.

## Previous public release — 2026-09-30

Version **1.0.0 (11)** is processed as **VALID** and available to the owner's
Internal group and the public External group. Beta App Review is **APPROVED**.
The owner can install build 11 through Internal TestFlight, and the public join
link above offers it to external testers. Kyra now uses the existing OpenAI
`IMAGE_PROVIDER_API_KEY` while `IMAGE_GENERATION_PROVIDER=openai`; those calls
share OpenAI billing and limits. A dedicated `STYLIST_PROVIDER_API_KEY` still
takes precedence when configured.
A signed-in production conversation smoke test remains open. Production and
Sandbox App Store Server Notifications URLs are configured at
`https://anutsdzbxycaavmmkewo.supabase.co/functions/v1/app-store/webhook`.
Signed Apple test-notification acceptance and sandbox purchase checks remain.

---

## 1. Pull and open the project

```bash
cd /path/to/Astra-Style   # the connected folder
git checkout main
git pull origin main
cd ios
test -f Config/Secrets.xcconfig || cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# Fill SUPABASE_URL + SUPABASE_ANON_KEY if empty.
# xcconfig footgun: URLs must be written https:/$()/anutsdzbxycaavmmkewo.supabase.co
xcodegen generate          # brew install xcodegen if missing
open AstraStyle.xcodeproj
```

## 2. Signing (once)

In Xcode → AstraStyle target → **Signing & Capabilities**:

- Team = owner's Apple Developer team
- Automatically manage signing = ON
- Bundle ID = `com.astrastyle.app`
- App Icon should resolve from `Resources/Assets.xcassets`

Do not commit `Secrets.xcconfig` or any `.p12` / provisioning profile.

## 3. Bump build number if needed

ASC rejects duplicate `CFBundleVersion`. Edit `CURRENT_PROJECT_VERSION` in
`ios/project.yml`, then `xcodegen generate` again. Commit the bump before upload.

## 4. Archive → TestFlight

1. Scheme **AstraStyle**, destination **Any iOS Device (arm64)** (not Simulator).
2. **Product → Archive** → Organizer opens.
3. **Distribute App → App Store Connect → Upload**.
4. Wait for ASC processing (**VALID**).
5. Add the build to the **External** group, then submit **Beta App Review**
   (a prior build’s review does not cover a new binary).
6. Public link can stay `mU5pC1RW`; testers only get the new build after Apple
   approves it.

CLI archive: `ios/CLI_BUILD_AND_TESTFLIGHT.md` or `cd ios && bundle exec fastlane beta`.

**2FA / license agreements:** stop and ask the owner. Never invent Apple credentials
or put app-specific passwords in the repo.

## 5. Hosted loops (not mock lies)

```bash
# Closet scan — live OpenAI (do not commit the key)
supabase secrets set VISION_ANALYSIS_PROVIDER=openai VISION_PROVIDER_API_KEY=sk-...
supabase functions deploy closet --import-map supabase/functions/deno.json

# Account deletion (Guideline 5.1.1(v))
supabase functions deploy account --import-map supabase/functions/deno.json
```

Auth → Providers: turn **Anonymous** on, and **manual identity linking** if
Apple/email link 422s. Probe: empty-body `/auth/v1/signup` returns
`is_anonymous: true`. See `supabase/functions/closet/README.md`.
Never put provider keys in the iOS target.

## 6. Smoke on the phone (report pass/fail)

1. Welcome → **Try without an account** (or Apple/email if Anonymous is still off).
2. Add ≤10 items → link Apple/email (photos migrate).
3. Scan one piece (live vision) → Wear This → paste or Shop row.
4. Discover Unlocks shows gap items only → one Studio Visualize.
5. Terms/Privacy open HTTPS → delete-account row does not 404.
6. Wear This stays free. Paywalls after the actual quotas (paste 1, Studio 1,
   closet 10/30, Kyra 3/day) must **Close**, not brick.

## 7. Done when

- [x] Build is VALID, on the External group, and approved by Beta App Review
- [ ] Owner (or a stranger) launched it from the public join link
- [ ] Smoke results reported (and any Organizer errors pasted verbatim)

**Out of scope for this cut:** App Store listing screenshots / sale, filling
`[[NEEDS INPUT]]` legal entity names, Fastlane Match certs repo, full curated
women’s Shop SKU catalog.

---

If something blocks you, tell the owner the exact Xcode/ASC error. Do not pivot
into unrelated refactors while this cut is unfinished.

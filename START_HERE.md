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
| Build number | bump `CURRENT_PROJECT_VERSION` before each upload (now `33`) |
| Public join | https://testflight.apple.com/join/mU5pC1RW |
| External group | `cdf6feb8-9fcd-451e-87cb-c1f6983600bf` |
| Supabase project ref | `anutsdzbxycaavmmkewo` (confirm with owner if unsure) |
| Twin docs | `docs/12-testflight-cut.md`, `ios/CLI_BUILD_AND_TESTFLIGHT.md` |

## Current internal release — build 33 (2026-10-10)

Version **1.0.0 (33)** is VALID and IN_BETA_TESTING in Internal
(build ID `5e68e692-61c7-4843-ac06-967eb64143b7`). Internal group membership
and en-US testing notes were read back. Includes all current app source changes:
foundation/design-system refinements, motion and haptics, large-text Kyra and
accessibility improvements, Studio polling recovery, privacy-safe analytics, and
bundled dependency notices. Local acceptance passed 1,193 unit tests, 64 visual
comparisons and both critical-screen large-text audits. The latest general iOS CI
run failed; local real-backend Kyra CI and physical-device acceptance remain open.
This build is for internal device testing. External review remains unsubmitted;
the public group still uses build 11.

## Previous internal release — build 32 (2026-10-09)

Version **1.0.0 (32)** is VALID and IN_BETA_TESTING in Internal
(build ID `e95031d0-f90b-4247-8ea7-a47f90df240f`). Internal group membership
and en-US testing notes were independently read back. Includes the completed
outfit builder: long-press locks without opening the picker, real Kyra completion
preserves locks, edits keep the original outfit identity and wear history, and
mutating actions cannot overlap. Twenty-five focused builder unit tests and both
simulator flows passed; bounded live provider and owner/peer edit checks passed.
Also ships previously verified full style-quiz refinement, care instructions,
Studio preset browsing, authored Monthly Review, closet thumbnails/versatility,
semantic Studio cache requests and critical-screen accessibility fixes. Those
other tickets retain their separately recorded acceptance status. Full physical-
device, purchase, legal and outside-user acceptance remain open. External review
remains unsubmitted; the public group still uses build 11.

## Previous internal release — build 30 (2026-10-09)

Version **1.0.0 (30)** is VALID and IN_BETA_TESTING in Internal
(build ID `1ac7da90-68d5-434f-ac16-64d2f3dc7071`). Internal group membership
and en-US testing notes were verified by readback. Adds explicit versioned local
schemas and lightweight upgrades, verified with historical unversioned four-,
five-, and six-entity on-disk fixtures and a second reopen. An on-disk offline
queue fixture verifies payload/date preservation, FIFO replay, durable retry counts,
and clearing after success. The full native unit suite passed; disabled live
integration checks remain separate. Backend account deletion's Auth cascade fix
is deployed and separately verified. New recommendation and scanner unlock-count
work is not included. Real-device, provider, purchase, and legal gates remain open.
External review remains unsubmitted; public group still uses build 11.

## Previous internal release — build 29 (2026-10-09)

Version **1.0.0 (29)** is VALID and IN_BETA_TESTING in Internal
(build ID `d4950b5a-1a54-4a51-9512-d67ab7321a06`). Internal group membership
and en-US testing notes were verified by readback. Adds explicit durable-storage
startup recovery and serialized, account-scoped offline replay when connectivity
returns. Eight mock core UI flows passed; startup retry was checked in dark and
light at accessibility text sizes. Historical store upgrades are being verified
separately and are not included in this build. Real-device, live-provider, purchase,
and legal acceptance remain open. External review remains unsubmitted; public
group still uses build 11.

## Previous internal release — build 28 (2026-10-09)

Version **1.0.0 (28)** is VALID and IN_BETA_TESTING in Internal
(build ID `6650cb3c-b144-4e3b-92a8-2bfd3c46df08`). Internal group membership
and en-US testing notes were verified by readback. Adds scanner interrupted-save
recovery, owner-scoped offline closet photo caching, Premium Studio high resolution
export confirmation/recovery, structured WeatherKit context for closet generation,
and purchase-month Monthly Review attribution with complete history pagination.
Selected native integration and Studio dark/light accessibility flows passed.
Studio light accessibility screenshots were visually reviewed after fixing badge
wrapping. This does not establish full-app accessibility or real-device acceptance.
External review remains unsubmitted; public group still uses build 11.

## Previous internal release — build 27 (2026-10-08)

Version **1.0.0 (27)** is VALID and IN_BETA_TESTING in Internal
(build ID `b460317e-1ace-4b5b-95f1-397c45cb97cf`), with group membership
and en-US testing notes verified. Includes offline closet archive/laundry
queueing, surfaced durable enqueue failures, scanner save retry IDs, Home
manual-selection fallback and Fahrenheit context, owned inspiration-image
Kyra conversation context, and photo-reference export round trips.
Seventy focused native tests passed. Hosted export pagination/owner isolation
and invalid-image authorization checks passed. Scanner restart recovery,
offline remote photo bytes and reopened-chat visual context are newer work.
Server background-removal fallback remains disabled. Real-device/provider,
full accessibility and legal acceptance remain open. External review is
unsubmitted; the public group still uses build 11.

## Previous internal release — build 24 (2026-10-08)

Version **1.0.0 (24)** is VALID and IN_BETA_TESTING in Internal
(build ID `56569c96-4950-4556-b670-8b6f014955b3`), with group membership
and en-US testing notes verified. Includes item insights, saved-look gallery,
and the accessibility laundry layout. Closet v19 is deployed; hosted ownership
and insight fixtures passed. Device, live photo signing and VoiceOver acceptance
remain open. These follow-ups shipped in build 25.
External review is not submitted; the public group still uses build 11.

## Previous internal release — build 22 (2026-10-08)

Version **1.0.0 (22)** is VALID and IN_BETA_TESTING in Internal
(build ID `71f4c60b-dfd4-435a-a6e8-0b5445c5d567`), with group membership and
en-US testing notes verified. Adds remaining preview allowance/reset display,
refresh/error handling and monthly-limit behavior without an upgrade paywall.
Fifteen selected native tests and the Home inspiration UI flow passed.
Studio v19 and Kyra v19 are deployed with final saved-confirmation checks.
Hosted Premium purchase and consented-photo chat acceptance remain open.
External review is not submitted; the public group still uses build 11.

## Previous internal release — build 21

Version **1.0.0 (21)** is VALID and IN_BETA_TESTING in Internal
(build ID `aa507aee-4135-411d-b51e-d2550e9eb683`), with group membership and
en-US testing notes verified. Adds Open preview in Kyra chat, routing to existing
Studio progress/results. Twelve native chat tests passed, including focused
action routing checks. Backend Kyra v14 uses Responses; one hosted styling reply
passed without fallback. Full hosted preview and device acceptance remain open.
External review is not submitted; the public group still uses build 11.

## Previous internal release — build 20

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

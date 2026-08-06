# START HERE — Claude on the owner's Mac

> **Full situation brief:** [`CLAUDE_HANDOFF.md`](CLAUDE_HANDOFF.md) — where we
> are, what works, what is stub. Read that if you are cold-starting.
>
> If you are fixing **astra-style.com / privacy / the marketing site**: wrong file.
> Open **[`web/CLAUDE.md`](web/CLAUDE.md)** (sources in `web/` + `legal/`, not `ios/`).
> Deploy brief: [`web/GATE.md`](web/GATE.md).

**Current status (2026-08-06):** Build **1.0.0 (1)** is **installed on the
owner's iPhone** via TestFlight (Internal group). **Your job now:** run the
smoke checklist (§6) and report pass/fail. Do not cut another build unless
smoke fails hard or the owner asks. Do not start Phase 4.

### Owner decisions (2026-08-02) — stop waiting on these

1. **Privacy / legal stay drafts.** Keep the live “Draft — not yet in force”
   banner on https://astra-style.com/privacy/. Do **not** remove it. Do **not**
   flip `AstraLegal.isPublished`. Do **not** fill `[[NEEDS INPUT]]` or chase
   counsel for this cut (`legal/README.md`, ticket `P7-PRIVACY-05`).
2. **Priority = TestFlight smoke.** ASC Privacy Policy URL may be
   `https://astra-style.com/privacy/` — that does **not** authorize flipping
   in-app legal links.

| Fact | Value |
|---|---|
| Branch | `main` (pull latest) |
| Bundle ID | `com.astrastyle.app` |
| Team ID | `Q9ZH8AA9NY` |
| ASC App ID | `6797115649` |
| Owner ASC login | `tdoxwell@icloud.com` |
| Xcode | **26.6** exactly |
| Marketing version | `1.0.0` (`ios/project.yml`) |
| Build number | **1 already on ASC** — bump before any re-upload |
| Supabase project ref | `anutsdzbxycaavmmkewo` |
| Situation brief | **`CLAUDE_HANDOFF.md`** |
| GUI path | this file + `docs/12-testflight-cut.md` |
| CLI path (no Xcode GUI) | **`ios/CLI_BUILD_AND_TESTFLIGHT.md`** |

---

## 1. Pull (only if you need to rebuild)

```bash
cd /path/to/Astra-Style
git checkout main
git pull origin main
cd ios
test -f Config/Secrets.xcconfig || cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# xcconfig footgun: URLs must be written https:/$()/anutsdzbxycaavmmkewo.supabase.co
xcodegen generate          # brew install xcodegen if missing
open AstraStyle.xcodeproj
```

## 2. Signing (already pinned for build 1)

In `ios/project.yml` target settings: `CODE_SIGN_STYLE: Automatic`,
`DEVELOPMENT_TEAM: Q9ZH8AA9NY`. Do not rely on GUI-only signing —
`xcodegen generate` regenerates the project.

Do not commit `Secrets.xcconfig` or any `.p12` / provisioning profile.

## 3. Bump build number only for a re-upload

ASC rejects duplicate `CFBundleVersion`. Edit `CURRENT_PROJECT_VERSION` in
`ios/project.yml`, then `xcodegen generate`. Commit the bump before upload.

## 4. Archive → TestFlight (re-cuts only)

GUI: Scheme **AstraStyle** → Any iOS Device → Product → Archive → Distribute →
App Store Connect.

CLI: follow **`ios/CLI_BUILD_AND_TESTFLIGHT.md`** (`xcodebuild archive` +
`-exportArchive` with `ExportOptions.plist`).

**2FA / license agreements:** stop and ask the owner.

## 5. Optional — real vision (mock is the default)

```bash
supabase secrets set VISION_ANALYSIS_PROVIDER=openai OPENAI_API_KEY=sk-...
supabase functions deploy closet
```

See `supabase/functions/closet/README.md` and `docs/08-provider-abstraction.md` §2.5.
Never put provider keys in the iOS target.

## 6. Smoke on the phone (report pass/fail) — **do this now**

1. Guest or Sign in with Apple → Home / Closet.
2. Manual add a garment → shows under category; wear count 0.
3. Scan or **Import** a shirt → edit fields → Save → unlock copy → **Done**.
4. Airplane mode: Closet cached; scan queues; reconnect analyzes without re-capture.
5. Filters / metrics / mark worn — no crash.

Note: analyze defaults to **mock** vision unless §5 was enabled — mock success
still counts as a pass for the client loop.

## 7. Done when

- [x] Build is in the internal TestFlight group
- [x] Owner launched it on a physical iPhone
- [ ] Smoke results reported (and any Organizer errors pasted verbatim)

**Out of scope:** Fastlane, public TestFlight, subscriptions, Phase 4 features,
legal publish.

---

If something blocks you, tell the owner the exact Xcode/ASC error. Do not pivot
into unrelated refactors while smoke is unfinished.

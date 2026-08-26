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
| Xcode | **26.6** exactly |
| Marketing version | `1.0.0` (`ios/project.yml`) |
| Build number | bump `CURRENT_PROJECT_VERSION` before each upload (now `9`) |
| Public join | https://testflight.apple.com/join/mU5pC1RW |
| External group | `cdf6feb8-9fcd-451e-87cb-c1f6983600bf` |
| Supabase project ref | `anutsdzbxycaavmmkewo` (confirm with owner if unsure) |
| Twin docs | `docs/12-testflight-cut.md`, `ios/CLI_BUILD_AND_TESTFLIGHT.md` |

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

- [ ] Build is VALID, on the External group, and submitted for Beta App Review
- [ ] Owner (or a stranger) launched it from the public join link
- [ ] Smoke results reported (and any Organizer errors pasted verbatim)

**Out of scope for this cut:** App Store listing screenshots / sale, filling
`[[NEEDS INPUT]]` legal entity names, Fastlane Match certs repo, full curated
women’s Shop SKU catalog.

---

If something blocks you, tell the owner the exact Xcode/ASC error. Do not pivot
into unrelated refactors while this cut is unfinished.

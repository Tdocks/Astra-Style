# START HERE — Claude on the owner's Mac

> If you are fixing **astra-style.com / privacy / the marketing site**: wrong file.
> Open **[`web/CLAUDE.md`](web/CLAUDE.md)** (sources in `web/` + `legal/`, not `ios/`).
> Deploy brief: [`web/GATE.md`](web/GATE.md).

**Your only job right now:** cut an **internal TestFlight** build of Astra Style
and get it onto the owner's iPhone.

Do **not** dig through `HANDOFF.md` landmines, rewrite READMEs, or start Phase 4.
Do **not** treat commit `cc7923cf` ("Pre-build groundwork…") as new work — that is
an **older** ancestor on `main` (guest scan gate / CI / truth docs). Current tip
already includes Phase 3 exit + this handoff (`git log -5 --oneline`).

| Fact | Value |
|---|---|
| Branch | `main` (pull latest) |
| Bundle ID | `com.astrastyle.app` |
| Xcode | **26.6** exactly |
| Marketing version | `1.0.0` (`ios/project.yml`) |
| Build number | bump `CURRENT_PROJECT_VERSION` before each upload (starts at `1`) |
| Supabase project ref | `anutsdzbxycaavmmkewo` (confirm with owner if unsure) |
| Twin docs | `docs/12-testflight-cut.md`, `HANDOFF.md` §12.0 (same content, longer context) |

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
4. Wait for ASC processing.
5. App Store Connect → TestFlight → add build to the **internal** group (owner's Apple ID).
6. iPhone → TestFlight app → install **Astra Style**.

CLI archive (optional):

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

Then export/upload via Organizer or Transporter.

**2FA / license agreements:** stop and ask the owner. Never invent Apple credentials
or put app-specific passwords in the repo.

## 5. Optional — real vision (mock is the default)

```bash
supabase secrets set VISION_ANALYSIS_PROVIDER=openai OPENAI_API_KEY=sk-...
supabase functions deploy closet
```

See `supabase/functions/closet/README.md` and `docs/08-provider-abstraction.md` §2.5.
Never put provider keys in the iOS target.

## 6. Smoke on the phone (report pass/fail)

1. Guest or Sign in with Apple → Home / Closet.
2. Manual add a garment → shows under category; wear count 0.
3. Scan or **Import** a shirt → edit fields → Save → unlock copy → **Done**.
4. Airplane mode: Closet cached; scan queues; reconnect analyzes without re-capture.
5. Filters / metrics / mark worn — no crash.

## 7. Done when

- [ ] Build is in the internal TestFlight group
- [ ] Owner launched it on a physical iPhone
- [ ] Smoke results reported (and any Organizer errors pasted verbatim)

**Out of scope:** Fastlane, public TestFlight, subscriptions, Phase 4 features.

---

If something blocks you, tell the owner the exact Xcode/ASC error. Do not pivot
into unrelated refactors while this cut is unfinished.

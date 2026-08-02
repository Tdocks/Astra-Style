# iOS CLI Build & TestFlight Upload (no Xcode GUI required)

**Use this when:** cutting a TestFlight build from the command line — no
access to Xcode's Organizer/GUI (e.g. a background/remote coding agent like
Cursor or Claude working over SSH/terminal on the owner's Mac).

**Companion doc:** `START_HERE.md` is the current task scope and the GUI
path (Product → Archive → Organizer). This doc is the CLI-only mechanics —
read both.

## Facts (re-verify against `project.yml` before trusting these — they drift)

| Fact | Value |
|---|---|
| Bundle ID | `com.astrastyle.app` |
| Apple Developer Team ID | `Q9ZH8AA9NY` (Tyler Dockswell's membership) |
| App Store Connect App ID | `6797115649` |
| Owner's Apple ID / ASC login | `tdoxwell@icloud.com` |
| Xcode version | 26.6 exactly (per `START_HERE.md`) |
| Marketing version / build number | `ios/project.yml` → `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` |

## 0. Two footguns baked into this repo — read before touching anything

1. **Signing settings must live in `project.yml`, not just Xcode's GUI.**
   `xcodegen generate` fully regenerates `project.pbxproj` from `project.yml`
   every time it runs. Any signing config set by hand in Xcode's Signing &
   Capabilities pane is silently discarded on the next regen. Confirm the
   `AstraStyle` target's `settings.base` in `ios/project.yml` includes:
   ```yaml
   CODE_SIGN_STYLE: Automatic
   DEVELOPMENT_TEAM: Q9ZH8AA9NY
   ```
   If missing, add them before archiving — don't assume a prior GUI setup
   survived.

2. **`GENERATE_INFOPLIST_FILE: NO` — `INFOPLIST_KEY_*` build settings in
   `project.yml` are dead code.** This project ships a checked-in
   `Info.plist` at `ios/AstraStyle/Resources/Info.plist`
   (`GENERATE_INFOPLIST_FILE: NO`, set once near the top of `project.yml`).
   Any `INFOPLIST_KEY_*` lines under `settings.base` are **never merged
   in** — that mechanism only applies when Xcode generates the Info.plist
   itself, which this project does not do. If a build needs a new Info.plist
   key (orientations, usage descriptions, URL schemes, etc.), **edit the
   real Info.plist file directly.** Adding more `INFOPLIST_KEY_*` lines to
   `project.yml` will look correct and silently do nothing.

## 1. Pull, regenerate the project

```bash
cd /path/to/astra   # repo root
git checkout main && git pull origin main
cd ios
test -f Config/Secrets.xcconfig || cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# xcconfig footgun: URLs must be written https:/$()/anutsdzbxycaavmmkewo.supabase.co
xcodegen generate   # brew install xcodegen if missing. Required after any project.yml edit.
```

## 2. Bump the build number (every upload needs a unique one)

App Store Connect rejects a re-upload of a `CFBundleVersion` (build number)
it has already seen for this marketing version. Before archiving:

```bash
# edit ios/project.yml: CURRENT_PROJECT_VERSION: "N" -> "N+1"
xcodegen generate
git add ios/project.yml
git commit -m "chore(ios): bump build number to N+1"
```

## 3. Archive (CLI)

```bash
cd ios
xcodebuild archive \
  -scheme AstraStyle \
  -configuration Release \
  -archivePath build/AstraStyle.xcarchive \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates
```

- `-allowProvisioningUpdates` lets `xcodebuild` fetch/create missing
  provisioning profiles via the developer portal API. Without it you will
  hit `No profiles for 'com.astrastyle.app' were found` — but at the
  **export** step, not here, which makes it confusing to diagnose.
- This can take 1-3 minutes. If your shell/tool has a synchronous timeout
  shorter than that (common in agent harnesses — often ~60s), background it
  rather than treating a timeout as failure:
  ```bash
  xcodebuild archive ... > /tmp/archive_log.txt 2>&1 &
  echo "PID $!"; disown
  # then poll:
  ps -p <PID> -o pid,stat,etime,command
  tail -40 /tmp/archive_log.txt
  ```
- Confirm success: log ends with `** ARCHIVE SUCCEEDED **`. Verify contents
  before moving on:
  ```bash
  plutil -p build/AstraStyle.xcarchive/Info.plist
  # check ApplicationProperties.CFBundleShortVersionString / CFBundleVersion / Team
  ```

## 4. Export options file (create once, reuse)

`ios/build/ExportOptions.plist` — build artifact, gitignored, not committed:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>Q9ZH8AA9NY</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>upload</string>
</dict>
</plist>
```

## 5. Export + upload straight to App Store Connect (CLI, no Transporter)

```bash
xcodebuild -exportArchive \
  -archivePath build/AstraStyle.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates
```

`destination: upload` in `ExportOptions.plist` means this both exports the
`.ipa` **and** uploads it directly to App Store Connect — no separate
Transporter step needed. This is a network operation and can take several
minutes; background it the same way as step 3 if your tooling times out.
Success ends with `** EXPORT SUCCEEDED **` and `Upload succeeded` in the log.

## 6. Common export errors seen on this project

| Error | Cause | Fix |
|---|---|---|
| `No profiles for 'com.astrastyle.app' were found` | Missing distribution provisioning profile; xcodebuild can't auto-create one without permission | Add `-allowProvisioningUpdates` to **both** the archive and export commands |
| `Invalid bundle. No orientations were specified... (code 90474)` | `UISupportedInterfaceOrientations` missing from the real Info.plist | Add the key directly to `ios/AstraStyle/Resources/Info.plist` — see footgun #2 above. Project convention: portrait-only on iPhone, all 4 orientations on iPad (`~ipad` suffix) |
| Signing identity mismatch / "no signing certificate" found | `DEVELOPMENT_TEAM` / `CODE_SIGN_STYLE` missing from `project.yml`, dropped by a `xcodegen generate` | Add `CODE_SIGN_STYLE: Automatic` + `DEVELOPMENT_TEAM: Q9ZH8AA9NY` to the target's `settings.base` in `project.yml`, then regenerate |
| Any 2FA prompt, Apple ID sign-in, or license-agreement acceptance | — | **Stop. Ask the owner.** Never invent or enter Apple credentials on their behalf |

Useful diagnostics:
```bash
security find-identity -v -p codesigning   # confirms cert + private key are actually in the local keychain
```

## 7. After a successful upload

1. App Store Connect → app `6797115649` → TestFlight → iOS Builds. New build
   shows **Processing** (usually 15-60 min) then **Ready to Test**.
2. If no Internal Testing group exists yet: TestFlight sidebar → Internal
   Testing → **+** → name it, leave "Enable automatic distribution" checked
   (future builds then auto-flow to the group with no manual re-adding).
3. Add the owner as a tester: group → Testers → **+**. Internal testers must
   already be an App Store Connect user (Users and Access) — this is not an
   arbitrary email invite like external testing. Owner's ASC login:
   `tdoxwell@icloud.com`.
4. Owner gets a TestFlight notification/email once the build finishes
   processing and installs via the TestFlight app on their iPhone.

## Guardrails — do not do these while cutting a build

- Do not flip `AstraLegal.isPublished` in the iOS app, or fill any
  `[[NEEDS INPUT]]` legal placeholders. That's a separate, deliberately
  deferred decision (`legal/README.md`, ticket `P7-PRIVACY-05`) — unrelated
  to shipping a TestFlight build. If ASC asks for a Privacy Policy URL on
  the app record, `https://astra-style.com/privacy/` is already set there;
  pasting it is not the same as publishing in-app legal links.
- Do not commit `Config/Secrets.xcconfig`, `.p12` files, or provisioning
  profiles.
- Do not reach for Fastlane, submit to public TestFlight, or touch
  subscriptions — out of scope unless the owner explicitly asks.
- Never call any Higgsfield tool/MCP, under any circumstance (standing rule
  for this account, unrelated to iOS builds but applies to any agent working
  in this repo).
- If ASC prompts "Missing Compliance" / export-compliance questions on a new
  build: `ITSAppUsesNonExemptEncryption` is already `false` in Info.plist, so
  the standard answer is "No, this app does not use non-exempt encryption" —
  but confirm that key hasn't changed before answering on autopilot.
- If anything is ambiguous or an error doesn't match the table above, stop
  and report the exact Xcode/ASC error to the owner rather than guessing.

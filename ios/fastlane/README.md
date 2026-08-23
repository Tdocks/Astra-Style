# Fastlane

CLI automation for the same archive/upload path as
[CLI_BUILD_AND_TESTFLIGHT.md](../CLI_BUILD_AND_TESTFLIGHT.md). Signing stays
**Automatic** (`CODE_SIGN_STYLE` in `project.yml`). Match is optional.

From `ios/`:

```sh
bundle install
bundle exec fastlane tests
bundle exec fastlane beta
```

`beta` uses the App Store Connect API key at
`~/.appstoreconnect/private_keys/AuthKey_AV4QQKM7Q5.p8`. It does not bump
`CURRENT_PROJECT_VERSION` — do that in `project.yml` first.

## Match

Only when you have a **private** git repo for certificates:

```sh
export MATCH_GIT_URL="https://github.com/Tdocks/Astra-Style-certs.git"
export MATCH_PASSWORD="…"
bundle exec fastlane certs
```

Do not commit `MATCH_PASSWORD`, `.p12`, or provisioning profiles.
Without `MATCH_GIT_URL`, skip Match. Automatic signing on this Mac is enough
for TestFlight.

# Major screen snapshot baselines

Committed PNG references for `MajorScreenSnapshotTests`, covering Home, Closet,
outfit detail, Kyra conversation, Studio gallery and detail, Paywall, and
Profile. Each screen has light/dark populated references at default, AX3, and
AX5 text sizes, plus default-size empty references. Tests fail when a reference
is missing. Recording requires creating the local, gitignored
`.record-snapshots` marker in this folder; CI does not set this marker.

Run XcodeGen first. Snapshot references are recorded on **iPhone 17 Pro,
iOS 26.5** so the device frame and safe areas stay fixed. Use the same Xcode
version, runtime, device, locale, and display scale when recording and
verifying:

```sh
cd ios
xcodegen generate
touch AstraStyle/Tests/SnapshotBaselines/.record-snapshots
xcodebuild test \
  -project AstraStyle.xcodeproj -scheme AstraStyle \
  -destination "id=$(python3 ../scripts/resolve_ios_simulator.py --runtime 26.5 --device 'iPhone 17 Pro')" \
  -only-testing:AstraStyleTests/MajorScreenSnapshotTests
rm AstraStyle/Tests/SnapshotBaselines/.record-snapshots
```

Review the generated PNGs before committing. Then rerun the same test command
after removing the marker; verification mode fails when a baseline is missing
or differs. The resolver fails with the installed simulator inventory
if that exact runtime and device are unavailable; it does not silently choose
another destination. Keep the simulator device, iOS runtime, Xcode version,
locale, and display scale unchanged between recording and verification.

The fixtures use in-memory repositories and fixed sample identities. They do not
call Supabase, StoreKit, or an image provider.

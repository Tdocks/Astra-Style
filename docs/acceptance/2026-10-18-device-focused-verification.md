# Focused physical-device verification — 2026-10-18

Device: connected iPhone 17 Pro Max, iOS 27.2 (24B5110a).
Source: main at d1ce87268253a9b76de5e3d0c0286297e4156b5a; existing unrelated local documentation changes retained.

The current development test build succeeded using the single project DerivedData
directory, `ios/build/DerivedData`. No archive or TestFlight upload was made.

## Results

- SessionRestoreTests and ScannerCaptureViewModelTests: **22 passed, 0 failed, 0 skipped**.
  Evidence: `/tmp/astra-device-focused-20261018.xcresult`.
- PaywallRecoveryTests and CapturePreparationMetadataTests,
  CapturePreparationOrientationTests, CapturePreparationResizeTests:
  **18 passed, 0 failed, 0 skipped**.
  Evidence: `/tmp/astra-device-purchase-recovery-20261018.xcresult`.

These are tests executed on physical hardware. Session tests use isolated real
Keychain services with controlled refresh responses. Scanner state and purchase
recovery tests use mock capture/purchasing/server dependencies. Image preparation
tests exercise metadata removal, orientation and upload sizing with fixtures.
They do not establish live camera capture, provider analysis/save, notification
delivery, or Apple sandbox purchase acceptance. No failures required code changes.

The installed app was opened without reset or mock launch arguments for the owner
to complete a real garment capture → analysis → save. The owner confirmed that
capture, analysis and save succeeded, the garment and photo persisted after a full
relaunch, and an edited detail persisted after reopening the item.
These are owner-observed live-path passes, separate from the controlled tests above.
Device testing is paused at the owner's request; notification delivery and actual
Apple purchases remain unverified.

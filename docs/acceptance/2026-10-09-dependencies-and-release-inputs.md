# iOS dependency inventory and release inputs — 2026-10-09

This inventory records the package versions and revisions resolved on the audit machine, with purposes checked against package manifests and license identifiers checked against the corresponding upstream license files. It is not legal advice or a completed App Store review. The generated Xcode project and its Package.resolved are ignored; the reviewed lock is tracked separately at ios/Dependencies/AstraStyle.Package.resolved and CI installs and enforces that graph.

## Resolved iOS package graph

The app declares one direct package dependency in ios/project.yml: Supabase Swift, product Supabase, pinned with exactVersion 2.54.0. The tracked canonical lock records the transitive graph that resolved on the audit machine:

| Package | Local resolved version | Local revision | Role in the app/package graph | License evidence |
|---|---:|---|---|---|
| supabase-swift | 2.54.0 | 003e58d745f0151c6590bfcb756af8234fdc9ec8 | Direct client SDK. Provides the app's Supabase Auth, PostgREST, Storage, and Edge Function client APIs. | MIT; LICENSE in the pinned checkout. |
| swift-asn1 | 1.7.1 | a9a5efd40eaf558a2bcd48d64b1d1646be686008 | Transitive dependency of swift-crypto; ASN.1 structures used by cryptographic formats. | Apache-2.0; LICENSE.txt and NOTICE.txt in the pinned checkout. |
| swift-clocks | 1.1.0 | 72d749bf341b78851203066ab421869b783ec42a | Supabase package helper dependency for clock abstractions and deterministic time support. | MIT; LICENSE in the pinned checkout. |
| swift-concurrency-extras | 1.4.1 | 5fa253428866f2360c3754e88537f700ed2656b5 | Supabase package dependency for concurrency utilities used by its targets. | MIT; LICENSE in the pinned checkout. |
| swift-crypto | 4.5.1 | 47d3869a7291f085c1fb9fb1e6d3b97a793f45c6 | Supabase Auth cryptographic support, including JWT/JWK operations; depends on swift-asn1. | Apache-2.0; LICENSE.txt and NOTICE.txt in the pinned checkout. |
| swift-http-types | 1.6.0 | db774a277f60063a32d854f2980299caf06da041 | HTTP request/response types used by Supabase networking targets. | Apache-2.0; LICENSE.txt and NOTICE.txt in the pinned checkout. |
| xctest-dynamic-overlay | 1.11.0 | 8f6abcf4c8950e2679d5b2fee4ca284fd7c34886 | Supabase package's issue-reporting and XCTest overlay dependency. | MIT; LICENSE in the pinned checkout. |

The revision values above were read from the generated lock and matching checkouts under Xcode DerivedData on the audit machine, then recorded in the tracked canonical lock. CI copies that canonical file into the generated project after XcodeGen and runs package resolution with onlyUsePackageVersionsFromResolvedFile; build and test commands use the same restriction. The project does not directly declare SnapshotTesting; its presence in Supabase's own package manifest as a test dependency does not make it a resolved app dependency. Apple SDK frameworks are not third-party package pins in this inventory.

For local work, run `python3 scripts/manage_ios_package_resolution.py --install` after XcodeGen and pass `-onlyUsePackageVersionsFromResolvedFile` to Xcode builds and tests. To change a transitive dependency, resolve it deliberately, review the full lock diff and package licenses, then record it with scripts/manage_ios_package_resolution.py --record-reviewed-resolution --reviewed. The helper rejects an unlocked/floating Supabase declaration, malformed lock, duplicate package identities, and a Supabase version that differs from project.yml. Verify that the final archived app and its included package notices satisfy each license's attribution and notice conditions. The exact direct Supabase version alone does not pin its transitive graph; the tracked lock and CI enforcement do.

`ios/AstraStyle/Resources/ThirdPartyNotices.txt` now carries the complete license texts and required upstream NOTICE files for the seven packages above. XcodeGen's `AstraStyle` source tree includes non-Swift resources recursively, so this file is part of the app resource inputs. The generated archive still needs a release check confirming `ThirdPartyNotices.txt` is present in the built `.app`; the current About screen does not yet link to or display it.

Release tooling evidence: `ios/Gemfile` and `ios/Gemfile.lock` pin Fastlane and its Ruby dependency graph; the app release workflow installs XcodeGen with Homebrew's unpinned `brew install xcodegen` command. The XcodeGen binary version is therefore not locked in CI. The dependency graph is reproducible; the full toolchain is not until the XcodeGen version policy is pinned or recorded and enforced.

## Physical-device acceptance

- [ ] Install the current release candidate from TestFlight on a physical supported iPhone and record model, iOS version, build, date, and tester.
- [ ] Use a dedicated disposable QA account, not a personal or customer account. Verify sign-in and session restoration.
- [ ] Capture/import, analyze, and save five distinct garments; correct at least one scanner-generated field and confirm the saved correction.
- [ ] Review camera framing, blur/exposure guidance, photo import, and image quality on real device inputs.
- [ ] Complete the connected outfit, Kyra, wear/review, pasted-link, Studio, memory, and deletion path. Record each step before deleting the QA account.
- [ ] Repeat the connected flow with VoiceOver enabled and separately under a documented degraded-network profile. Preserve per-step results and screenshots where appropriate.
- [ ] Verify that account deletion completes and that the synthetic identity, owned rows, Storage objects, and generated data are absent. Confirm the same credential cannot restore the deleted account.
- [ ] Keep simulator/mock results, hosted fixture results, provider results, and device results labeled as separate evidence classes.

## Owner, counsel, and App Store Connect inputs

These are release decisions or approvals; the repository does not supply values that should be invented.

- [ ] Confirm the legal seller/entity name, copyright holder, public support contact, and support URL.
- [ ] Obtain counsel approval for the published privacy policy, terms, retention/deletion language, provider/processor disclosures, and applicable regional disclosures.
- [ ] Reconcile App Privacy answers against the exact release build and deployed provider configuration, including WeatherKit, image/model processing, product evaluation, analytics, and retention. Confirm all partner classifications and data-linkage answers in App Store Connect.
- [ ] Confirm age rating, primary/secondary categories, territories, availability, and any required privacy-choice URL.
- [ ] Confirm subscription product identifiers, localized names/prices, renewal terms, and sandbox availability. Supply a dedicated App Store Connect sandbox tester for purchase, restore, renewal, cancellation, and expiry acceptance.
- [ ] Supply any required provider-budget approval before running live Kyra, product extraction, image analysis, or Studio image-generation requests. Use synthetic fixture data and bounded requests.
- [ ] Capture and approve actual screenshots from the release candidate. Do not use mock output to imply live provider quality or represent an unshipped UI.
- [ ] Verify final Fastlane/XcodeGen/toolchain version policy and release signing configuration before archive/upload.

Do not publish provisional values from docs/acceptance/2026-10-09-app-store-submission-draft.md until the relevant owner or counsel decisions above are recorded.

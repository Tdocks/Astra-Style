# Shopping and closet thumbnail native acceptance

## Verified

The combined native unit suite completed successfully on October 9, 2026 using
the iOS simulator. The terminal build result was `TEST SUCCEEDED`, exit status 0.
All 1,092 Swift Testing tests across 166 suites passed; all 33 XCTest cases passed.
The local verification log is `/tmp/astra-shop-thumbnails-native-verification-6.log`.

The batch adds Shop the Look routes and explicit candidate-backed missing-item
cards, server-provided shopping alternatives, paired private closet thumbnails,
guest-local thumbnail migration, and thumbnail-first grid resolution. Unit
coverage includes candidate ownership, legacy decoding, upload compensation,
image variants, thumbnail creation, and grid fallback/prefetch behavior.

Verification caught and fixed two image-resolution defects: selecting cutouts
without a cutout thumbnail omitted the source fallback, and the prefetch plan
excluded thumbnail paths that also had a fallback. Originals are signed for
fallback but are not prefetched alongside every thumbnail.

## Backend deployment

The full scratch SQL runner passed all 160 baseline assertions and every
additional contract suite through `51_closet_image_thumbnail_variants.sql`.
The scratch database was dropped and its temporary PostgreSQL server stopped.
The six export-attachment tests passed with the repository's Deno configuration.

Migration `20261009075545_closet_image_thumbnail_variants.sql` was applied to
production. An independent schema query confirmed both thumbnail columns are
nullable. The `profile` function was deployed with thumbnail-aware export
references. Existing rows with null thumbnails remain valid. No Storage bucket,
row-access policy, or client grant was changed.

## Remaining acceptance

- Shop the Look simulator screen navigation and disclosure checks.
- Live private-thumbnail/export/deletion acceptance.
- Physical-device closet performance measurements required by P7-INFRA-03.
- Higher-quality alternative ranking required by P6-SHOP-05; the current server
  supplies compatibility scores, not a product quality measurement.

This result is unit acceptance, not a full application end-to-end pass. Build 31
does not include this batch. No master-plan ticket was closed by this document.

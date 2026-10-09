# Public peer-look hosted acceptance — 2026-10-09

Two disposable confirmed accounts exercised the deployed peer-look detail path. The publisher owned one synthetic jacket and a non-person PNG already in the repository. No provider calls, shared-catalog changes, real-user writes, or messages were made.

## Passed

- `fetch_public_worn_looks` returned the requested public, worn peer look with exactly its approved summary fields.
- `fetch_public_look_garments` returned the synthetic garment with exactly its approved display fields. Private size and image-analysis metadata were absent.
- The viewer received no raw peer rows from `outfits`, `outfit_items`, `outfit_wears`, `closet_items`, or `closet_item_images`.
- Unauthenticated `POST /lookbook/sign-images` returned 401. The exact public/worn outfit-item-image tuple returned a short-lived signed capability, and the corresponding private PNG downloaded successfully. The URL and image bytes were not logged or retained.
- Private-worn, unworn, and forged item/image tuples returned no signed URLs. Attempting to publish the unworn outfit was rejected.
- The only live `outfits` triggers were the public-requires-wear guard and timestamp updater; no notification trigger was present.

## Fixtures and cleanup

Publisher `fc555b15-b198-4727-8a41-b49a44fe3294`; viewer `8d042ab8-bb7e-4e26-bacf-f6a952697b94`. Public outfit `d1c9ebf2-e034-4ca9-92aa-745ce2aa5c34`; private-worn outfit `cafac211-0bdc-471c-a7ae-e5a318b4d3a2`; unworn outfit `428c452d-9009-43bf-8a24-4c2d25440b8f`; closet item `aa4a9b57-2651-4968-ae41-dfa684d05de8`; image metadata row `1e357cf9-273e-422e-a387-493573cdf1b2`.

Both accounts were deleted through the normal account endpoint. Deletion receipts: publisher `ddfd97fa-7b08-443e-9f22-8940d10bdced`; viewer `84fcab14-d973-4581-bbdd-1d5b589939e3`. Targeted SQL readback found zero remaining Auth, profile, closet, image-metadata, outfit, outfit-item, wear-history, or `user-content` object rows for either account. Two earlier setup attempts were also deleted normally and independently verified with zero rows: owner `ef4d13ed-9b2b-4df1-af0a-7a2125a4a451`, receipt `1f523971-26b5-4a82-ab15-05b5d020286c`; viewer `abd097d3-1279-49c3-990e-e3a88c43af21`, receipt `2a62f86d-3670-4591-884d-256ebade8657`; owner `d3e1b5b1-18a0-4c52-9d2b-87d3b9b5978b`, receipt `15c64800-87f1-4ef0-93af-013e4befb45f`; viewer `7934a0ec-e071-4ee3-bff5-397adda8fc79`, receipt `e55bb0d9-7bb5-4c33-b4c5-714b8ff1e5e4`.

## Scope limits

This verifies hosted RPC, signing, private-object download, denial, and cleanup behavior. It does not exercise the iOS peer-detail screen against production or prove device/TestFlight behavior. It also does not satisfy the remaining Discover editorial sections in master spec §6.21: style education, seasonal guides, fit guides, and brand spotlights still have no content model and are placeholders. P6-CORE-01 remains Partial.

Reusable opt-in runner: [`hosted_public_look_acceptance.ts`](../../supabase/functions/lookbook/hosted_public_look_acceptance.ts). Its Deno format, lint, and type checks passed.

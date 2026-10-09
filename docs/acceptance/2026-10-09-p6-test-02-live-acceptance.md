# P6-TEST-02 live acceptance — 2026-10-09

The deployed `products` function was exercised with a disposable anonymous account and the tracked shearling-jacket catalog fixture from `supabase/seed/product_candidates.json`.

The caller-owned closet contained a brown shearling/leather jacket, olive chinos, and brown leather boots. `POST /products/evaluate` returned HTTP 200, `redundancy_score: 100`, verdict `skip`, and duplicate-specific reasoning. This verifies the ticket's near-duplicate/high-risk/non-buy acceptance criterion against the deployed function, including the owned-garment color mapping fixed in this batch.

The acceptance runner is [live_evaluation_acceptance.ts](../../supabase/functions/products/live_evaluation_acceptance.ts). Run it explicitly after deploying `products` and ensuring the duplicate candidate from `supabase/seed/product_candidates.json` is present:

```sh
cd supabase/functions
RUN_PRODUCTS_LIVE_ACCEPTANCE=1 \
SUPABASE_URL="$SUPABASE_URL" \
SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
PRODUCT_DUPLICATE_CANDIDATE_ID="$PRODUCT_DUPLICATE_CANDIDATE_ID" \
deno run --allow-env=RUN_PRODUCTS_LIVE_ACCEPTANCE,SUPABASE_URL,SUPABASE_ANON_KEY,PRODUCT_DUPLICATE_CANDIDATE_ID \
  --allow-net="$SUPABASE_HOST" products/live_evaluation_acceptance.ts
```

The runner creates a synthetic owner, inserts only synthetic closet rows, evaluates once (so it works on the free tier), then requests account deletion through the normal endpoint. It does not call extraction, a retailer, or an image/provider service. It never deletes or mutates the shared candidate.

Deletion IDs were `27613f90-541b-4466-a938-35bb5d026346` (fresh owner) and `286b764d-8545-4e72-982a-d6218f840a03` (the earlier quota-exhausted owner). Both reached `completed`, with owner IDs cleared. Independent SQL readback found zero `auth.users`, `profiles`, `closet_items`, or `user_product_evaluations` rows for either owner. The shared candidate was briefly deleted after the first cleanup check, then restored from the exact seed fields with its original ID and timestamps; it is present again.

Local verification: `deno test --import-map=deno.json products/` passed 64 tests; `deno lint`, `deno fmt --check`, and `deno check` passed for the live acceptance runner. Hosted deployment evidence: `/tmp/astra-products-duplicate-color-deploy.log`.

# Kyra product tools implementation

8 October 2026. Work in progress; not deployed.

## Implemented locally

- `analyze_product` validates one URL or candidate UUID and rejects unsafe URLs.
- Production wiring forwards the caller JWT to the existing product extraction
  and evaluation routes. Those routes retain SSRF guards, quota checks, catalog
  normalization and wardrobe evaluation. Kyra uses no service-role key.
- Catalog candidate lookup uses a caller-scoped client; only mapped public product
  attributes reach the model.
- Tool output preserves measured compatibility, converts redundancy from 0–100
  to 0–1, retains unknown price/cost fields, and labels affiliate links.
- Allowance/authentication/invalid-product failures are domain results rather than
  infrastructure retries. Server failures retain the existing Kyra retry policy.

## Evidence

109 Kyra tests passed (`/tmp/astra-kyra-product-tests2.log`), including the new
service adapter, tool and conversation registration checks. Deno entrypoint type
checking and new module linting passed. These are offline fixture tests.

## Still required before deployment/completion

- Compute `fills_gap` from actual wardrobe coverage; currently returned null.
- Confirm safe behavior for extraction uncertainty and available card fields.
- Hosted ownership, allowance and real provider acceptance, with disposable QA
  identities and catalog cleanup.
- `search_products` and confirmed `generate_studio_preview` remain stubs.
- Audit mutation retries/duplicate evaluations and quota concurrency alongside
  the shared product service.

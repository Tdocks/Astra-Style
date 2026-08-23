# `subscriptions` — P7-SUB-03 stub

`POST /subscriptions/sync` persists a StoreKit-observed transaction so the closet cap can uncap
against a server row.

## Status

**Stub, not Apple-verified.** The client verifies the StoreKit 2 transaction locally, then this
function writes `app_store_original_transaction_id`. `POST /app-store/webhook` (ASSN V2) is not this
slug and is not deployed.

**Deployed** 2026-08-22 to `anutsdzbxycaavmmkewo`.

Wear This, Daily Brief, and paste-evaluate are not gated here.

## Env

| Variable                    | Meaning                                                        |
| --------------------------- | -------------------------------------------------------------- |
| `SUPABASE_SERVICE_ROLE_KEY` | Required. RLS forbids authenticated writes on `subscriptions`. |

## Deliberately not built

- App Store Server API receipt verification
- App Store Server Notifications V2 (`app-store/`)
- Family Sharing / credits / extra IAP

# `subscriptions` — P7-SUB-03

`POST /subscriptions/sync` persists a StoreKit-observed transaction so the closet cap can uncap
against a server row.

## Status

`POST /sync` verifies the StoreKit 2 signed transaction JWS with Apple's official App Store Server
library before associating it to the authenticated Astra account. New purchases include the
authenticated user UUID as Apple's `appAccountToken`; legacy transactions without that token are
accepted only when their lineage is already linked to the same user.

`POST /app-store/webhook` verifies App Store Server Notifications V2, signed renewal information,
bundle ID, app ID, certificate chain, and online revocation status. It updates a linked lineage only
with a newer Apple `signedDate`. Notifications that arrive before the first client sync are kept as
short-lived pending state and reconciled at first sync.

**Local implementation only.** Apply the new migration and deploy both functions after setting the
Apple verification configuration. The previously deployed `subscriptions/sync` remains the older
client-trusted version until that deployment happens.

Wear This, Daily Brief, and paste-evaluate are not gated here.

## Env

| Variable                         | Meaning                                                                          |
| -------------------------------- | -------------------------------------------------------------------------------- |
| `SUPABASE_SERVICE_ROLE_KEY`      | Required. RLS forbids authenticated writes on `subscriptions`.                   |
| `APP_STORE_ROOT_CA_CERTS_BASE64` | Comma-separated Base64 DER Apple Root CA certificates downloaded from Apple PKI. |
| `APP_STORE_APPLE_ID`             | Numeric App Store Connect app ID; required for Production verification.          |
| `APP_STORE_BUNDLE_ID`            | Defaults to `com.astrastyle.app`.                                                |

Configure the App Store Server Notifications V2 production and sandbox URL as:
`https://anutsdzbxycaavmmkewo.supabase.co/functions/v1/app-store/webhook`. The new
`[functions.app-store] verify_jwt = false` setting is required because Apple does not send a
Supabase JWT; the handler verifies Apple's signed JWS before any write.

## Still open

- Deploying the migration and functions, setting Apple secrets, and sending a test notification.
- Sandbox purchase, restore, refund, grace-period, and renewal acceptance on a signed build.
- Family Sharing / credits / extra IAP.

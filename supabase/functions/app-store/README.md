# `app-store` — App Store Server Notifications V2

This public webhook verifies Apple's `signedPayload`, then verifies the nested signed transaction
and renewal information before updating `subscriptions`. It is public to Apple
(`verify_jwt = false`) but rejects malformed or unverified JWS data. Apple `signedDate` ordering
prevents a delayed notification or old device transaction from replacing newer state.

Set these Supabase Edge Function secrets before deployment:

- `APP_STORE_ROOT_CA_CERTS_BASE64`: comma-separated Base64 DER Apple root certificates from
  [Apple PKI](https://www.apple.com/certificateauthority/).
- `APP_STORE_APPLE_ID`: numeric App Store Connect app ID.
- `APP_STORE_BUNDLE_ID`: `com.astrastyle.app` unless the bundle ID changes.
- `SUPABASE_SERVICE_ROLE_KEY`: supplied by Supabase for deployed functions.

The V2 endpoint is `https://anutsdzbxycaavmmkewo.supabase.co/functions/v1/app-store/webhook` for
both production and sandbox configuration in App Store Connect. The handler accepts test events and
notifications unrelated to Astra Premium without changing entitlement state.

This is not deployed or accepted against App Store Connect yet. Deploy the append-only migration,
deploy the `app-store` and updated `subscriptions` functions, then send Apple's test notification
and exercise sandbox purchase, renewal, expiration, refund, and restore flows.

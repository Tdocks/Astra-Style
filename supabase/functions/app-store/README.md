# `app-store` — App Store Server Notifications V2

This public webhook verifies Apple's `signedPayload`, then verifies the nested signed transaction
and renewal information before updating `subscriptions`. It is public to Apple
(`verify_jwt = false`) but rejects malformed or unverified JWS data. Apple `signedDate` ordering
prevents a delayed notification or old device transaction from replacing newer state.

The append-only reconciliation migration and the `app-store` and `subscriptions` functions are
deployed to the Astra Style Supabase project. The production and sandbox App Store Server
Notifications URLs point to the endpoint below. The following Supabase Edge Function secrets are
configured there; values are not stored in this repository:

- `APP_STORE_ROOT_CA_CERTS_BASE64`: comma-separated Base64 DER Apple root certificates from
  [Apple PKI](https://www.apple.com/certificateauthority/).
- `APP_STORE_APPLE_ID`: numeric App Store Connect app ID.
- `APP_STORE_BUNDLE_ID`: `com.astrastyle.app` unless the bundle ID changes.
- `SUPABASE_SERVICE_ROLE_KEY`: supplied by Supabase for deployed functions.

The V2 endpoint is `https://anutsdzbxycaavmmkewo.supabase.co/functions/v1/app-store/webhook` for
both production and sandbox configuration in App Store Connect. The handler accepts test events and
notifications unrelated to Astra Premium without changing entitlement state.

Deployment and URL configuration are verified. Apple signed test-notification acceptance and
end-to-end sandbox purchase, renewal, expiration, refund, and restore checks remain open. Do not
treat the deployed endpoint as proof that Apple-to-server delivery or the complete purchase
lifecycle has been accepted.

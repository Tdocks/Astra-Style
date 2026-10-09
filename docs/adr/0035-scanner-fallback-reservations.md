# ADR 0035: Reserve scanner fallback processing durably

Status: implementation groundwork; not activated.

## Decision

Use a service-only, RLS-protected ledger for server segmentation fallback. Native adequate cutouts bypass it. A claim is unique per owner/source and owner/request key. Serialize new claims by owner before evaluating daily/monthly limits. Persist dispatch before invoking the vendor. Replayed or uncertain requests never dispatch a second time; completing requires the expected owned output object and an existing source.

The first implementation deliberately retains uncertain/failed reservations and quota consumption. There is no automatic expiry/re-dispatch: a vendor without idempotency cannot prove that a lost response was uncharged. A reserved worker crash remains pending. A future reconciliation operation must establish vendor status before allowing another attempt.

Config defaults disabled. Initial configurable caps of five/day and twenty/month are provisional safety limits, not a published entitlement. Review caps, provider credentials and privacy disclosure before activation.

Functions use SECURITY INVOKER and empty search_path with execute granted only to service_role. Account eligibility reads only auth.users id/is_anonymous; client metadata is not eligibility authority.

## Remaining acceptance

Concurrent duplicate/quota races, persistent adapter integration, hosted ownership and actual vendor cutout quality, native invocation, account deletion races, orphan output retention, and export handling are required. No live photos have been sent by this implementation.

## Endpoint configuration

`POST /closet/remove-background` accepts Astra's envelope with `storage_path`
and boolean `device_adequate`, plus `Idempotency-Key`. Returns
`background_removed_path` (nullable). Permanent account verification, caller
storage RLS and exact owner paths precede processing. Requests are limited to
16 KiB. Endpoint processing requires `BACKGROUND_REMOVAL_PROVIDER=removebg`,
`BACKGROUND_REMOVAL_PROVIDER_API_KEY`, and the database enabled switch. None
is activated by this implementation. Provider selection is still pending.

Local concurrent SQL acceptance passed (eight claims and dispatches). Caller
storage and reservation adapters plus endpoint tests exist; full hosted and
native acceptance remain open.

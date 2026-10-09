# 0033 — Premium Studio monthly reservations

Date: 2026-10-08

## Decision

Implement the master specification's higher Premium Studio quota as a configurable default of 20 previews per UTC calendar month. This is an implementation default pending owner pricing decisions, not a user-approved plan quantity. The server-only singleton configuration permits 1–1000 previews.

A BEFORE INSERT trigger on studio_allowances enforces the premium budget under the same per-user transaction advisory lock as job submission. Pending reservations and completed renders count; released failures do not. Existing free-trial enforcement remains in enqueue_studio_generation. Upgrading counts existing unreleased allowances in the current month. Existing over-limit users retain their jobs but cannot reserve another until capacity is available.

Retries reuse an allowance and idempotent replays return the existing job before reserving anything. Deleting an image does not refund a completed allowance. The configuration has RLS with no client policies and explicit service-only grants. The trigger uses SECURITY INVOKER and an empty search path.

## Verification and remaining work

Local full SQL isolation suite passed, including previous-month exclusion, limit rejection, same-key replay, retry without another allowance, release restoring capacity and denied authenticated config modification. Studio job-store type checking passed.

Eight simultaneous local submissions with a one-preview limit accepted exactly one job and rejected seven without extra allowances. Migration 20261009004701 is deployed; Studio v17 is ACTIVE with JWT verification and maps quota exhaustion to HTTP 429 with the UTC reset explanation. Hosted configuration is 20, RLS is enabled and authenticated UPDATE privilege is false. All 61 Studio backend tests passed. The advisor reports the intentional no-client-policy configuration table as INFO; existing unrelated warnings remain.

Hosted premium request acceptance, quota-summary API and native remaining/reset display are still required. TestFlight remains build 21.

## Allowance display implementation

Added authenticated GET studio/quota with explicit verified-owner filters, exact counts and no-store response caching. Premium returns the configured monthly limit and UTC reset instant; free accounts return the lifetime trial count without a reset. The API is informational; the database transaction remains authoritative. Studio and Home inspiration display the returned allowance and provide refresh/error handling, refreshing after accepted submissions. Personal Studio no longer opens a paywall for every HTTP 429: only the existing free-trial exhaustion response triggers it.

Simulator build passed; all 64 Studio backend tests passed, including UTC/year rollover, verified identity overriding caller-supplied owner and unauthenticated denial. This endpoint/display batch is not deployed or in TestFlight yet. Hosted API acceptance, native unit/UI verification and release remain open.

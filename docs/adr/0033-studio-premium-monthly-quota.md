# 0033 — Premium Studio monthly reservations

Date: 2026-10-08

## Decision

Implement the master specification's higher Premium Studio quota as a configurable default of 20 previews per UTC calendar month. This is an implementation default pending owner pricing decisions, not a user-approved plan quantity. The server-only singleton configuration permits 1–1000 previews.

A BEFORE INSERT trigger on studio_allowances enforces the premium budget under the same per-user transaction advisory lock as job submission. Pending reservations and completed renders count; released failures do not. Existing free-trial enforcement remains in enqueue_studio_generation. Upgrading counts existing unreleased allowances in the current month. Existing over-limit users retain their jobs but cannot reserve another until capacity is available.

Retries reuse an allowance and idempotent replays return the existing job before reserving anything. Deleting an image does not refund a completed allowance. The configuration has RLS with no client policies and explicit service-only grants. The trigger uses SECURITY INVOKER and an empty search path.

## Verification and remaining work

Local full SQL isolation suite passed, including previous-month exclusion, limit rejection, same-key replay, retry without another allowance, release restoring capacity and denied authenticated config modification. Studio job-store type checking passed.

Deployment, concurrent premium submission acceptance, quota-summary API and native remaining/reset display are still required. No hosted quota enforcement or new TestFlight build is claimed by this change.

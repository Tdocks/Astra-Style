# ADR 0029: Renew API credentials through SessionStore

Date: 2026-10-08
Status: Accepted

## Context

API requests used SessionStore's cached access token without checking expiry.
Supabase's SDK can rotate its credentials independently, leaving that cached
access token and persisted refresh token stale. Expired-session launch recovery
also erased credentials on network failures.

## Decision

SessionStore owns request-time renewal through the injected SessionRefreshing
protocol. Requests within thirty seconds of expiry share one renewal task.
Live renewal uses the SDK's validated session when its identity matches the
expected user, falling back to the persisted refresh token only when the SDK has
no session. Renewed credentials are stored in Keychain.

A session revision invalidates outstanding work when an account is adopted,
cleared or signed out. Late results cannot recreate or replace an account.
Identity mismatches and definitive refresh credential rejection clear the stale
session; transient failures retain credentials for recovery. Launch restoration
also checks identity and preserves persisted credentials on transient failures.

## Consequences

Requests may wait for renewal; an unavailable refresh returns no bearer token
rather than sending expired credentials. Existing repository interfaces remain
unchanged. No provider credentials are exposed and no database migration is
needed. Unit tests exercise renewal, persistence, identity checks, concurrent
callers, late completion and offline recovery. A request-level test checks the
actual Authorization header. Hosted rotation and device lifecycle acceptance
remain separate release checks.

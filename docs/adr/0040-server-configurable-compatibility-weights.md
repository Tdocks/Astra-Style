# ADR 0040: Server-configurable compatibility weights

Status: Accepted
Date: 2026-10-09

## Context

Master specification section 10 requires compatibility weights to be configurable without a client release. The pure scorer already accepts weights, but production callers previously used only compiled defaults.

## Decision

Store one validated vector in `compatibility_weights_config`, seeded with the exact documented defaults. Only the service role can read or update this global product configuration; wardrobe reads remain caller scoped. Validate eight known finite components in the range zero through one with a positive total. A database trigger increments the version on a vector change and preserves it on no-op updates.

Read current configuration after authenticating each request. Missing or invalid configuration falls back to shipped defaults. Apply it to outfit generation/ranking, product evaluations/alternatives, and Unlocks scoring. Never accept configuration from a user request.

## Verification and limits

Parser and scoring regressions, full backend tests, and real scratch PostgreSQL tests verify constraints, access controls and version changes. Existing score-cache code is a pure key helper accepting the weights version; no persisted compatibility or Unlocks cache currently exists to invalidate. Any future persisted score cache must include the active configuration version in its key. This change does not establish recommendation quality on a real wardrobe or supply an administrative editing interface.

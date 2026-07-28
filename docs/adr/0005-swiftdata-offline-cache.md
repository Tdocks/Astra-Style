# 0005. SwiftData as an offline cache, not the source of truth

## Status

Accepted

## Context

§7 requires meaningful offline behavior: cached closet and outfits remain viewable
offline, local edits queue for sync, new scans can be captured and queued while
offline, and only generative features (Kyra, Studio) require network. §8 names
SwiftData explicitly as "local cache and offline-first entities." §9 defines the
actual system-of-record schema (`closet_items`, `outfits`, `style_profiles`, etc.) as
Supabase Postgres tables with RLS (§15).

There are two fundamentally different ways to use SwiftData here: as the app's
*primary* persistent model (the pattern SwiftData's own documentation and most
tutorials optimize for, where `@Model` types are the app's domain model and
`ModelContext` is the only place data lives before eventual sync), or as a
*derived cache* that mirrors a subset of the Supabase-owned system of record for
offline viewing and optimistic local edits.

## Decision

Supabase Postgres is the single source of truth for all durable user data.
SwiftData is a local cache: it stores a subset of the current server state needed for
offline viewing (closet items, outfits, daily briefs, style profile) plus a
**pending-operations queue** for edits made while offline or mid-sync. SwiftData
models are not identical in shape to the Supabase schema — they are a
view-optimized projection with an explicit sync-state field per record (`synced`,
`pendingCreate`, `pendingUpdate`, `pendingDelete`, `conflict`).

Sync model:

1. On authenticated launch and periodically, the app pulls changed rows from
   Supabase (scoped by `updated_at` watermark) and upserts them into SwiftData,
   never overwriting a record that has local pending changes.
2. Local edits write to SwiftData immediately (optimistic UI) and enqueue a pending
   operation; a background sync task drains the queue against Supabase when
   connectivity is available.
3. Conflict policy: last-write-wins by `updated_at` for simple field edits
   (e.g. `wear_count`, `laundry_state`); destructive operations (archive, delete) are
   never silently overwritten — a conflict surfaces to the user rather than being
   auto-resolved, because silently discarding a user's "I archived this item" is
   worse than asking.
4. Generative outputs (Kyra responses, Studio generations) are never queued for
   offline creation — §7 already scopes these as network-required, so there is no
   offline-write case to reconcile for them, only offline-*read* of previously
   fetched results.

## Consequences

### Positive

- A clean single source of truth means there is never ambiguity about which system
  "wins" in steady state — Supabase does, always, except for the narrow, explicit
  window between a local optimistic write and its successful sync.
- Treating SwiftData as a projection rather than the domain model means the
  Supabase schema (§9) can evolve (new columns, new tables) without forcing a
  SwiftData migration for every server-side change — only fields the offline UI
  actually needs get mirrored.
- The pending-operation queue makes "local edits queue for sync" (§7) an explicit,
  testable data structure (§22 lists "offline queue" as a required unit-test target)
  rather than an implicit property of however SwiftData happens to behave.
- Explicit conflict surfacing on destructive operations avoids the worst offline-sync
  failure mode: a user's archive/delete silently reverting because a stale pull
  overwrote it.

### Negative (real costs, named)

- **Two schemas to maintain in parallel.** Every Supabase column that the offline UI
  needs must be mirrored, mapped, and kept in sync in the SwiftData model, plus a
  translation layer (repositories, per §8) that converts between the two shapes.
  This is genuinely more code than "SwiftData model == server model," and it is an
  ongoing tax on every schema change, not a one-time cost.
- **SwiftData is still a relatively young framework with known rough edges** at the
  time of this decision: CloudKit-backed sync features are irrelevant here (not
  used — Supabase is the sync target, not CloudKit) but SwiftData's migration
  story for `@Model` schema changes is less battle-tested than Core Data's, and
  predicate/query capabilities (complex compound predicates, certain relationship
  queries) have documented limitations and occasional runtime crashes on some SDK
  versions. The team should expect to hit framework bugs, not just app bugs, and
  budget time for workarounds.
- **Conflict resolution is genuine distributed-systems complexity**, not incidental
  complexity — last-write-wins is a real data-loss risk for concurrent edits (e.g.
  editing the same closet item on two devices while offline on both), and the
  "surface conflicts to the user for destructive ops" policy requires UI that does
  not exist by default and must be designed, not just implemented.
- The pending-operations queue itself is another piece of state that can get stuck
  (a malformed pending operation that always fails to sync blocks or silently drops
  behind newer operations) and needs its own observability (a way to see and clear
  stuck queue entries) that is easy to underspec at MVP.
- SwiftData's `@Model` macro and `ModelContainer` setup interacts with Swift 6 strict
  concurrency (ADR 0006) in ways that are still settling across SDK point releases;
  isolating `ModelContext` correctly (it is not `Sendable` in the general case) adds
  real friction to a codebase that otherwise wants everything `@MainActor` or
  actor-isolated cleanly.

## Alternatives Considered

- **SwiftData as the domain model / source of truth, with Supabase as a sync
  backend bolted on (CloudKit-style mental model).** Rejected: this pattern
  optimizes for CloudKit-native apps and fights the reality that Supabase, not the
  device, must remain authoritative for RLS-protected, cross-device, server-scored
  data (compatibility scores, wardrobe scores) that cannot be computed purely
  on-device. It would also make the escape hatch in ADR 0002 (Supabase is
  replaceable) harder, since domain logic would be entangled with SwiftData specifics.
- **Core Data instead of SwiftData.** Rejected: §8 specifies SwiftData explicitly,
  and Core Data offers no material offline-cache advantage here that would justify
  diverging from the spec's stated stack; Core Data's maturity edge over SwiftData
  is real but the app's cache use case (simple upsert + queue, not deep relationship
  graphs replicated on-device) doesn't stress the areas where SwiftData is weakest.
- **No local persistence; require network for every read.** Rejected outright by
  §7's explicit offline requirements.
- **A generic embedded SQL database (SQLite/GRDB) instead of SwiftData.** A credible
  alternative that would sidestep SwiftData's immaturity risk, at the cost of more
  boilerplate (manual row mapping, no `@Query` property wrapper ergonomics) and
  losing SwiftUI-native integration. Not chosen because §8 specifies SwiftData and
  the maturity risk is judged acceptable at MVP scale; this is the fallback if
  SwiftData's rough edges (above) prove unworkable in practice.

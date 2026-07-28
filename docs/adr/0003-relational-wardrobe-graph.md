# 0003. Relational tables + computed compatibility, not a graph database

## Status

Accepted

## Context

§1 names the Wardrobe Graph — closet items, outfits, occasions, style identities,
product candidates, colors, seasons, brands, fit characteristics, connected by edges
like `pairs_with`, `conflicts_with`, `unlocks`, `duplicates` — as the product's core
moat. "Graph" is in the name, and the concept naturally suggests a graph database
(Neo4j, Amazon Neptune, or a graph layer on top of Postgres via AGE/pgRouting).

§10 is explicit, however: "Use relational tables plus computed compatibility, not a
separate graph database" for the MVP implementation, with compatibility scored via a
weighted formula (color 0.25, formality 0.20, silhouette 0.15, season/weather 0.10,
preference 0.10, co-wear history 0.10, occasion 0.05, availability 0.05) that must be
configurable server-side, not hardcoded in the client.

## Decision

Model the wardrobe graph as ordinary Postgres tables (`closet_items`, `outfits`,
`outfit_items`, `style_feedback`, `product_candidates`, etc., per §9) plus computed,
cacheable compatibility scores, rather than adopting a dedicated graph database or a
Postgres graph extension. "Edges" like `pairs_with` and `unlocks` are not stored as a
generic edge table with a `relationship_type` column; they are either:

- derived at query/scoring time from the weighted compatibility formula in §10, or
- materialized as ordinary foreign-keyed rows (`outfit_items` linking an outfit to
  its closet items *is* the `pairs_with` relationship, expressed relationally) when
  the relationship is a concrete, queried-often fact rather than a derived score.

Purchase-unlock counts and wardrobe scores are computed batch/cached values (§10),
not live graph traversals.

## Consequences

### Positive

- One database to operate, back up, and reason about transactionally — a closet item
  edit and its downstream outfit/compatibility cache invalidation can happen in a
  single Postgres transaction; a split relational+graph store cannot offer that.
- RLS (ADR 0002) applies uniformly. A dedicated graph database would need its own,
  separately implemented authorization model, doubling the security surface.
- The compatibility weights are literal server-side config (a row in a weights table
  or a versioned config document read by the Edge Function), which satisfies §10's
  "weights should be configurable server-side" requirement directly — no graph query
  language changes needed to retune scoring.
- Standard Postgres tooling (indexes, `EXPLAIN`, pgvector for the embedding-based
  parts of similarity) is well understood by any backend engineer; a graph database
  adds a second query paradigm (Cypher/Gremlin) that the team must additionally
  learn and hire for.
- At MVP wardrobe sizes (a power user might own 200–400 garments, per §16 "unlimited
  closet" for Premium, but realistically low hundreds), the "graph" is small enough
  that a Postgres join across `closet_items` and `outfit_items` with a handful of
  indexed columns outperforms the operational cost of standing up a graph engine for
  the same query.

### Negative (real costs, named)

- **Multi-hop traversal is genuinely awkward in SQL.** Questions like "find items
  that, transitively through shared outfits, tend to co-occur with this item's
  co-occurring items" require recursive CTEs or repeated self-joins that get harder
  to write and slower to execute as hop count grows. A graph database expresses this
  natively in one query.
- **"Unlocks 18 outfits" is computed by generating and filtering candidate
  combinations (§10), not by a graph reachability query.** That's an explicit
  combinatorial-generation-plus-filter algorithm the team has to write, test, and
  keep performant, rather than something a graph engine gives for free via pattern
  matching.
- Compatibility scores are cached (§10: "cache the result"), which introduces a
  staleness/invalidation problem: adding or archiving a closet item must invalidate
  every cached score that depended on it, and getting that invalidation wrong
  produces stale, wrong-looking recommendations — silently, since a stale score still
  looks like a valid number.
- As the item count grows toward the higher end (multi-hundred-item closets across
  a large user base, cross-user similarity for future social/discovery features), the
  N×N candidate-combination generation described in §10 has real risk of becoming a
  computational bottleneck that a purpose-built graph engine's indexing would have
  handled more gracefully.
- The relational model requires more up-front schema discipline (explicit join
  tables, explicit indexes on every foreign key used in scoring) than a graph
  database's flexible edge model, which makes ad hoc "what new relationship type do
  we want to explore" experiments slower — a new edge concept in a graph DB is a new
  edge label; here it can mean a migration.

## Conditions Under Which This Should Be Revisited

This decision should be reopened, not defended reflexively, if any of the following
becomes true:

1. **Combination-generation latency for purchase-unlock scoring or outfit generation
   regularly exceeds the §20 performance targets** (item analysis under 8s, Kyra
   first token under 2.5s) for typical power-user closet sizes (300+ items), after
   query and index optimization has already been attempted and cannot close the gap.
2. **Multi-hop, exploratory queries become a first-class product feature** — for
   example, a "style neighborhood" discovery feature that needs "users whose
   wardrobe graphs are structurally similar to mine" or deep transitive reasoning
   ("what single purchase best bridges these two style clusters") that recursive SQL
   cannot express or execute at acceptable latency.
3. **The edge/relationship vocabulary grows materially beyond what's listed in §10**
   (i.e., dozens of distinct relationship types with different traversal semantics)
   such that the relational schema needs a new join table or new columns for nearly
   every product iteration.
4. **Cross-user graph features ship** (social recommendations, "wardrobes like
   yours") at a scale where the relational self-join cost across millions of rows
   materially exceeds a graph engine's indexed traversal cost, measured, not assumed.

If none of these conditions hold, the relational-plus-computed-compatibility model
remains the right choice: it is simpler, cheaper to operate, and sufficient for the
MVP and near-term roadmap described in §23.

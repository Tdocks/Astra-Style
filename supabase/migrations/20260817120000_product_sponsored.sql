-- ============================================================================
-- Astra Style — Sponsored-vs-organic labeling for product_candidates
-- ============================================================================
-- P6-SHOP-09 / spec §17 ("Sponsored products must be labeled") and §11
-- ("Separate sponsored placement from organic ranking"). `20260728100600_commerce.sql`
-- shipped `product_candidates` with no way to mark a row as a paid/affiliate
-- placement at all, which made the §17 guardrail unenforceable at the schema
-- level: nothing distinguished a curated-catalog row a retailer paid to
-- feature from one a user pasted in off a receipt, so any ranking code that
-- wanted to boost a sponsored row upward had nothing to even check to avoid
-- doing so honestly — the flag simply did not exist to audit against.
--
-- WHY THIS IS ITS OWN MIGRATION, NOT FOLDED INTO 20260728100600_commerce.sql.
-- That file has already shipped (dated 2026-07-28, well before this
-- ticket); editing a landed migration in place would silently change the
-- schema anyone who already ran `supabase start` against it is holding,
-- rather than describing the change as what it is — an additive column on
-- an existing table, applied forward.
--
-- WHY `not null default false`, NOT NULLABLE. A nullable `sponsored` would
-- let a ranking/labeling code path ask "is this row sponsored?" and get back
-- `null` — a third state ("unknown") that is not what §17 means, and one a
-- careless `if (row.sponsored)` check in JS/TS would silently treat as falsy
-- anyway, masking the ambiguity rather than surfacing it. Every existing row
-- (all of them either curated-admin or user-pasted-URL rows written before
-- this column existed) is honestly "not a paid placement" — nothing in this
-- codebase before P6-SHOP-08's admin ingestion path (out of this migration's
-- scope) has ever written an affiliate-feed row, so `false` is not a guess
-- being backfilled over unknown history, it is the true value for every row
-- that exists today.
--
-- WHO SETS IT TRUE. Not `authenticated` — see the RLS comment below: writes
-- to `product_candidates` are service-role only, unchanged by this
-- migration. `POST /products/extract` (`supabase/functions/products/`,
-- P6-SHOP-03) upserts rows from user-pasted URLs and never sets this column
-- true — see that function's `index.ts` for why the upsert's `on conflict`
-- clause deliberately omits `sponsored` from its `set`, so a user pasting a
-- link to a product an admin has already flagged sponsored cannot
-- accidentally clear that flag, and a plain user paste can never set it.
-- Only a curated-catalog admin insert or an affiliate-feed sync (P6-SHOP-08,
-- not built by this migration) is expected to ever write `true`.
-- ============================================================================

set search_path = public, extensions;

alter table public.product_candidates
  add column if not exists sponsored boolean not null default false;

comment on column public.product_candidates.sponsored is
  'True only for a paid/affiliate placement the catalog is promoting (curated-admin or affiliate-feed ingestion, P6-SHOP-08) — never set by POST /products/extract (P6-SHOP-03), which only ever upserts user-pasted-URL rows. Spec §17: sponsored placements must be labeled and must never influence Kyra''s ranking/verdict logic (§11) — see supabase/functions/products/ranking.ts for the code path that keeps this column read-only input to a LABEL, never to a SCORE.';

-- ============================================================================
-- Astra Style — 07. Commerce
-- ============================================================================
-- Tables: product_candidates, user_product_evaluations
-- Also: attaches outfit_items.product_candidate_id's foreign key now that
-- product_candidates exists (see ordering note in 20260728100400_outfits.sql).
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- product_candidates
-- ----------------------------------------------------------------------------
-- Deliberate exception to "every table has user_id references auth.users":
-- product_candidates is a SHARED catalog table (§17 "curated catalog
-- maintained in admin" / "retailer affiliate feeds" / de-duplicated
-- user-pasted URLs), not user-owned data. Many users can reference the same
-- canonical product row. It has no user_id and is not subject to per-user RLS
-- isolation — see 20260728100900_rls_policies.sql for its (read-all,
-- write-service-role-only) policy.
create table if not exists public.product_candidates (
  id                 uuid primary key default gen_random_uuid(),
  canonical_url      text not null,
  retailer           text,
  brand              text,
  name               text not null,
  category           clothing_category,
  price              numeric(10,2) check (price >= 0),
  currency           text not null default 'USD' check (char_length(currency) = 3),
  image_url          text,
  affiliate_url      text,
  availability       jsonb not null default '{}'::jsonb,
  attributes         jsonb not null default '{}'::jsonb,
  last_checked_at    timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint product_candidates_canonical_url_unique unique (canonical_url)
);

comment on table public.product_candidates is
  'Shared, de-duplicated product catalog (§17). Populated by curated admin entry, retailer affiliate feeds, or POST /products/extract when a user pastes a URL (§14). Global table: no user_id, no per-user RLS isolation.';
comment on column public.product_candidates.canonical_url is
  'Normalized product URL (tracking params stripped) used as the de-duplication key so repeated pastes of the same product resolve to one row.';
comment on column public.product_candidates.attributes is
  'Structured extracted attributes (color, material, sizes available, fit notes) used as compatibility-scoring input, analogous to closet_items'' discrete attribute columns but kept as jsonb since candidates arrive from heterogeneous, less-trustworthy extraction sources.';

-- ----------------------------------------------------------------------------
-- user_product_evaluations
-- ----------------------------------------------------------------------------
-- §9 lists no explicit `id`/primary key for this table and no explicit
-- uniqueness constraint. We add a surrogate `id` and deliberately do NOT add a
-- unique(user_id, product_candidate_id) constraint: a user's evaluation of a
-- product can and should be recomputed as their wardrobe changes (a new
-- closet item can change outfits_unlocked/redundancy_score for a
-- previously-evaluated product), and keeping evaluation history lets Kyra
-- explain "this used to unlock 4 outfits, now unlocks 11" and lets analytics
-- track verdict-accuracy over time. Callers fetch the latest evaluation via
-- `order by created_at desc limit 1` (see the composite index in
-- 20260728101100_indexes_and_search.sql).
create table if not exists public.user_product_evaluations (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references auth.users(id) on delete cascade,
  product_candidate_id      uuid not null references public.product_candidates(id) on delete cascade,
  compatibility_score       smallint check (compatibility_score between 0 and 100),
  redundancy_score          smallint check (redundancy_score between 0 and 100),
  outfits_unlocked          integer check (outfits_unlocked >= 0),
  expected_cost_per_wear    numeric(10,2) check (expected_cost_per_wear >= 0),
  verdict                   kyra_verdict not null,
  reasoning                 text,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

comment on table public.user_product_evaluations is
  'One Kyra product-decision evaluation (§6.19, §5.5). History-preserving by design — see table comment above on why there is no unique(user_id, product_candidate_id).';

-- Attach the foreign key that could not be declared in outfits.sql because
-- product_candidates did not exist yet at that point in the migration order.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'outfit_items_product_candidate_id_fkey'
  ) then
    alter table public.outfit_items
      add constraint outfit_items_product_candidate_id_fkey
      foreign key (product_candidate_id)
      references public.product_candidates(id)
      on delete set null;
  end if;
end
$$;

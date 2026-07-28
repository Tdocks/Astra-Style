-- ============================================================================
-- Astra Style — 05. Outfits
-- ============================================================================
-- Tables: outfits, outfit_items, outfit_wears
--
-- Note on ordering: outfit_items.product_candidate_id references
-- product_candidates(id), but product_candidates is created in
-- 20260728100600_commerce.sql, later than this file. We declare the column
-- here as a plain uuid and attach its foreign key constraint at the end of
-- commerce.sql once the target table exists. This keeps the migration
-- decomposition matching the suggested split (outfits before commerce) without
-- forward-referencing an undefined table.
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- outfits
-- ----------------------------------------------------------------------------
create table if not exists public.outfits (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references auth.users(id) on delete cascade,
  name                     text,
  description              text,
  occasion_tags            jsonb not null default '[]'::jsonb,
  -- Canonical unit: Celsius, regardless of profiles.units display preference.
  weather_min_celsius      numeric(5,2),
  weather_max_celsius      numeric(5,2),
  formality_score          smallint check (formality_score between 0 and 100),
  compatibility_score      smallint check (compatibility_score between 0 and 100),
  source                   outfit_source not null default 'ai_generated',
  hero_image_url           text,
  generated_preview_url    text,
  is_favorite              boolean not null default false,
  -- Added beyond §9's literal outfits field list. Outfits are referenced by
  -- outfit_wears (wear history / cost-per-wear analytics must survive), so a
  -- hard delete would either cascade-destroy wear history or require ON DELETE
  -- SET NULL on outfit_wears.outfit_id, silently orphaning history rows. An
  -- archive flag lets users remove an outfit from active lists (there is no
  -- explicit "delete outfit" action described in §6.12/§6.13, but there must be
  -- some way to retire an outfit) while keeping analytics intact. Documented
  -- in docs/04-data-model.md.
  archived_at              timestamptz,
  -- vector(1536): see docs/04-data-model.md. Powers "outfits like this one" /
  -- style-similar retrieval for Kyra and Discover.
  embedding                extensions.vector(1536),
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  check (weather_max_celsius is null or weather_min_celsius is null or weather_max_celsius >= weather_min_celsius)
);

comment on table public.outfits is
  'A concrete combination of closet items and/or product candidates. The "unlocks"/"pairs_with" wardrobe-graph edges are materialized as outfit_items rows, per ADR 0003.';
comment on column public.outfits.compatibility_score is
  'Cached output of the §10 weighted compatibility formula. Must be recomputed when any referenced outfit_items row, closet_item, or the server-side weights config changes — see docs/04-data-model.md "cache invalidation".';
comment on column public.outfits.source is
  'How the outfit came to exist: ai_generated (outfit generation §5.4), user_created (outfit builder §6.13), kyra_suggested (chat §6.20), studio_derived (built from a Style Studio session).';

-- ----------------------------------------------------------------------------
-- outfit_items
-- ----------------------------------------------------------------------------
-- user_id is denormalized from outfits.user_id (see closet_item_images comment
-- in 20260728100300_closet.sql for the same pattern and rationale).
create table if not exists public.outfit_items (
  id                     uuid primary key default gen_random_uuid(),
  outfit_id              uuid not null references public.outfits(id) on delete cascade,
  user_id                uuid not null references auth.users(id) on delete cascade,
  closet_item_id         uuid references public.closet_items(id) on delete set null,
  -- FK to product_candidates attached in 20260728100600_commerce.sql.
  product_candidate_id   uuid,
  role                   clothing_category not null,
  sort_order             integer not null default 0,
  is_required            boolean not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint outfit_items_exactly_one_item check (
    num_nonnulls(closet_item_id, product_candidate_id) = 1
  )
);

comment on table public.outfit_items is
  'One garment slot within an outfit. Exactly one of closet_item_id (owned) / product_candidate_id (a "missing item" / shop-the-look slot, §6.18) must be set — enforced by outfit_items_exactly_one_item.';
comment on column public.outfit_items.role is
  'Reuses clothing_category rather than a separate enum: the outfit builder''s category rail (§6.13: Tops, Bottoms, Outerwear, Shoes, Watches, Accessories, Fragrance) is exactly clothing_category''s value set.';
comment on constraint outfit_items_exactly_one_item on public.outfit_items is
  'Enforces "exactly one of closet_item_id / product_candidate_id is non-null" per spec requirement.';

-- An owned item should not appear twice in the same outfit slot list; likewise
-- a given "missing" product candidate should not be double-listed.
create unique index if not exists outfit_items_unique_closet_item_per_outfit
  on public.outfit_items (outfit_id, closet_item_id)
  where closet_item_id is not null;

create unique index if not exists outfit_items_unique_product_candidate_per_outfit
  on public.outfit_items (outfit_id, product_candidate_id)
  where product_candidate_id is not null;

-- ----------------------------------------------------------------------------
-- outfit_wears
-- ----------------------------------------------------------------------------
create table if not exists public.outfit_wears (
  id                 uuid primary key default gen_random_uuid(),
  outfit_id          uuid not null references public.outfits(id) on delete cascade,
  user_id            uuid not null references auth.users(id) on delete cascade,
  worn_at            timestamptz not null default now(),
  occasion           text,
  -- Deliberate exception to the *_score = int 0-100 convention: this is a
  -- subjective 1-5 star rating captured from a UI control, not a computed
  -- compatibility/formality score, so it is scaled and named accordingly.
  rating             smallint check (rating between 1 and 5),
  feedback           text,
  weather_snapshot   jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.outfit_wears is
  'One "mark worn" event (§5.2, §6.12). Drives wear_count/last_worn_at on closet_items via bump_closet_item_wear_stats() trigger (20260728101200_functions_and_triggers.sql) and cost-per-wear calculations.';
comment on column public.outfit_wears.rating is
  '1-5 user star rating of how the outfit performed, distinct from the 0-100 *_score columns used elsewhere.';

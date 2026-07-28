-- ============================================================================
-- Astra Style — 04. Closet
-- ============================================================================
-- Tables: closet_items, closet_item_images
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- closet_items
-- ----------------------------------------------------------------------------
create table if not exists public.closet_items (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references auth.users(id) on delete cascade,
  name                      text,
  brand                     text,
  category                  clothing_category not null,
  subcategory               text,
  primary_color             text,
  secondary_colors          jsonb not null default '[]'::jsonb,
  pattern                   text,
  material                  jsonb not null default '[]'::jsonb,
  size                      text,
  fit                       fit_preference,
  condition                 condition,
  seasonality               jsonb not null default '[]'::jsonb,
  formality_score           smallint check (formality_score between 0 and 100),
  warmth_score              smallint check (warmth_score between 0 and 100),
  water_resistance_score    smallint check (water_resistance_score between 0 and 100),
  purchase_date             date,
  price_paid                numeric(10,2) check (price_paid >= 0),
  currency                  text not null default 'USD' check (char_length(currency) = 3),
  retailer                  text,
  product_url               text,
  wear_count                integer not null default 0 check (wear_count >= 0),
  last_worn_at              timestamptz,
  laundry_state             laundry_state not null default 'clean',
  availability_state        availability_state not null default 'available',
  -- Explicit soft-delete column from §9 ("archived_at") and the §6.15 "Archive"
  -- item-detail action. Archived items stay for historical wear/cost-per-wear
  -- analytics and outfit_items references, but are excluded from active
  -- closet/outfit-generation queries by every index and RLS-adjacent query
  -- pattern (see 20260728101100_indexes_and_search.sql).
  archived_at               timestamptz,
  -- vector(1536): see docs/04-data-model.md. Used for "find items like this
  -- one" / redundancy-score / duplicate-detection queries (§6.15 "Redundancy
  -- score", §10 "duplicates" edge).
  embedding                 extensions.vector(1536),
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

comment on table public.closet_items is
  'A single owned garment/accessory. The core node of the Wardrobe Graph (§10) — outfit_items, style_feedback, and outfit compatibility scoring all key off this table.';
comment on column public.closet_items.material is
  'jsonb array of {"fiber": "cotton", "percentage": 100} objects; composition can be multi-fiber and is not a fixed enum.';
comment on column public.closet_items.seasonality is
  'jsonb array of season strings, e.g. ["spring","fall"]. Kept as jsonb (not a season[] column) because §6.14 treats it as a filterable multi-value tag rather than a normalized dimension the schema needs to join on elsewhere.';
comment on column public.closet_items.availability_state is
  'Overall wearability gate consumed by outfit generation (§5.4 step 2 "laundry availability"). Distinct from laundry_state: an item can be laundry_state=clean but availability_state=packed_for_travel.';
comment on column public.closet_items.embedding is
  'Visual/semantic embedding of the normalized cutout image + extracted attributes. Dimension: 1536, see docs/04-data-model.md.';

-- ----------------------------------------------------------------------------
-- closet_item_images
-- ----------------------------------------------------------------------------
-- user_id is denormalized (not in §9's literal field list) from
-- closet_items.user_id via the set_child_user_id() trigger family in
-- 20260728101200_functions_and_triggers.sql. This lets the RLS policy on this
-- table be a direct `user_id = (select auth.uid())` predicate instead of an
-- EXISTS subquery against closet_items on every row check, and it also gives
-- the trigger a natural place to reject inserts against another user's
-- closet_item (see rls_policies.sql comment on this table).
create table if not exists public.closet_item_images (
  id                        uuid primary key default gen_random_uuid(),
  closet_item_id            uuid not null references public.closet_items(id) on delete cascade,
  user_id                   uuid not null references auth.users(id) on delete cascade,
  image_type                image_type not null default 'front',
  storage_path              text not null,
  background_removed_path   text,
  is_primary                boolean not null default false,
  analysis_metadata         jsonb not null default '{}'::jsonb,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

comment on table public.closet_item_images is
  'Source + processed photos for a closet item (§5.3, §6.16). storage_path/background_removed_path are object paths in the private "user-content" bucket, not public URLs — see 20260728101000_storage_buckets.sql.';
comment on column public.closet_item_images.user_id is
  'Denormalized copy of the parent closet_items.user_id, set by trigger. Never set directly by client code.';
comment on column public.closet_item_images.analysis_metadata is
  'Per-image CV pipeline output: confidence scores per inferred field, blur/lighting flags (§12). Low-confidence fields drive the "visibly marked" UI requirement in §12.';

-- At most one primary image per closet item.
create unique index if not exists closet_item_images_one_primary_per_item
  on public.closet_item_images (closet_item_id)
  where is_primary;

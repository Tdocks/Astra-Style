-- ============================================================================
-- Astra Style — vertical slice seed data
-- ============================================================================
-- Populates a believable 25-item men's wardrobe for ONE user, so the
-- `POST /outfits/generate` Edge Function (supabase/functions/outfits-generate)
-- has something real to choose from, and so a developer testing the slice's
-- manual "add a garment" form doesn't also have to hand-enter 25 items first.
--
-- This is a fixture, not filler: every brand is one a well-dressed man
-- plausibly owns, colors were chosen to actually work together (navy /
-- charcoal / olive / stone / camel, with white/ecru neutrals), formality and
-- warmth scores are internally consistent (a waxed field jacket is warmer
-- than a cotton shirt; a grenadine tie is more formal than a pocket tee), and
-- wear_count/last_worn_at are deliberately varied — several items have never
-- been worn (last_worn_at IS NULL), several were worn recently, and several
-- haven't been worn in months, so `outfits-generate`'s
-- `LeastRecentlyWornScorer` (supabase/functions/outfits-generate/scorer.ts)
-- actually has a meaningful order to sort by instead of 25 identical rows.
--
-- Every literal value below was checked against
-- `supabase/migrations/20260728100100_core_enums.sql` by hand, member for
-- member, against the enum types `closet_items` actually declares
-- (clothing_category, fit_preference, condition, laundry_state,
-- availability_state) — see that migration for the authoritative list. If
-- you add a new item below, do the same before adding it: an invalid enum
-- value fails at INSERT time with "invalid input value for enum ...", not at
-- parse time.
--
-- ----------------------------------------------------------------------------
-- USAGE
-- ----------------------------------------------------------------------------
-- 1. Find your user id. This is the `id` column of `auth.users` for the
--    account you signed in with (Sign in with Apple, per the vertical
--    slice). Easiest ways to get it:
--      a) Supabase Studio -> Authentication -> Users -> copy the UUID, or
--      b) `select id, email from auth.users order by created_at desc;`
--         run against the project (Studio's SQL Editor, or `psql`), or
--      c) `scripts/seed-slice.sh <user-id>` (supabase/../scripts/) prints
--         this same query's instructions if you don't already have the id.
--
-- 2. Run this file with that id passed as the `seed_user_id` psql variable
--    (bare UUID text, no quotes — this file quotes it itself via `:'...'`),
--    e.g.:
--
--      psql "$DATABASE_URL" \
--        -v seed_user_id=00000000-0000-0000-0000-000000000000 \
--        -f supabase/seed/slice_seed.sql
--
--    `scripts/seed-slice.sh <user-id> [database-url]` wraps exactly this
--    invocation with argument validation; prefer it over calling psql by
--    hand unless you have a reason not to.
--
--    If you omit `-v seed_user_id=...` entirely, this file falls back to an
--    all-zeros placeholder UUID (see the `\if` block below) purely so the
--    file is syntactically runnable standalone — that placeholder will not
--    match any real auth.users row, so the existence check a few lines down
--    will fail loudly rather than silently seeding an orphaned wardrobe.
--
--    Alternatively, if you're pasting this directly into Supabase Studio's
--    SQL Editor (which does not expand psql `:variables`), replace every
--    occurrence of `:'seed_user_id'` below with your literal
--    `'00000000-0000-0000-0000-000000000000'` before running.
--
-- ----------------------------------------------------------------------------
-- IDEMPOTENCY
-- ----------------------------------------------------------------------------
-- Each item's primary key is derived deterministically from
-- (seed_user_id, item name) via an md5-based UUID, and the insert is
-- `ON CONFLICT (id) DO UPDATE`. Re-running this file for the same user id
-- updates the same 25 rows in place instead of duplicating them — safe to
-- re-run after editing a value below, or as part of a CI/local reset loop.
-- Running it for a *different* user id seeds a second, independent 25-item
-- wardrobe (different deterministic ids), since the id is a function of both
-- the user id and the item name.
-- ============================================================================

\if :{?seed_user_id}
\else
\set seed_user_id 00000000-0000-0000-0000-000000000000
\endif

\echo Seeding vertical-slice wardrobe for user :seed_user_id ...

-- Fail loudly and early if the target user doesn't exist, rather than
-- succeeding with 25 orphaned rows that violate closet_items' FK the moment
-- something else touches them (or, on a real Supabase project, simply never
-- appearing under RLS because the id was wrong).
--
-- NOTE: psql does NOT expand `:'seed_user_id'`-style variables inside a
-- dollar-quoted (`$$ ... $$`) function/DO body — it deliberately leaves
-- dollar-quoted text untouched so it doesn't collide with PL/pgSQL's own
-- `:=` assignment syntax. We work around that by handing the value to the
-- session as a GUC (`set_config`, evaluated in ordinary — not dollar-quoted
-- — SQL, where substitution does happen) and reading it back inside the DO
-- block with `current_setting()`.
select set_config('astra.seed_user_id', :'seed_user_id', false);

do $$
declare
  v_seed_user_id uuid := current_setting('astra.seed_user_id')::uuid;
begin
  if to_regclass('auth.users') is null then
    raise notice 'auth.users not found (not a Supabase project) — skipping user-existence check.';
    return;
  end if;
  if not exists (select 1 from auth.users where id = v_seed_user_id) then
    raise exception
      'No auth.users row for id %. Sign in once (Sign in with Apple, via the vertical slice) '
      'so a profile exists, then find the id via Supabase Studio -> Authentication -> Users, '
      'or `select id, email from auth.users;`, and pass it to this script.',
      v_seed_user_id;
  end if;
end
$$;

with seed_user as (
  select :'seed_user_id'::uuid as user_id
),
-- One row per garment. Columns map 1:1 onto closet_items' non-default
-- columns; anything not listed here (secondary_colors, material,
-- seasonality default to their table defaults except where meaningfully
-- varied below).
items (
  name, brand, category, subcategory, primary_color, secondary_colors, pattern,
  material, size, fit, condition, seasonality,
  formality_score, warmth_score, water_resistance_score,
  price_paid, currency, retailer,
  wear_count, days_since_last_worn, laundry_state, availability_state
) as (
  values
  -- ---------------------------------------------------------------------
  -- TOPS (8) — from lightest/most casual to heaviest/most formal
  -- ---------------------------------------------------------------------
  ('Riviera Cotton T-Shirt', 'Sunspel', 'top'::clothing_category, 't-shirt', 'White',
    '[]'::jsonb, 'solid', '[{"fiber":"cotton","percentage":100}]'::jsonb, 'M',
    'slim'::fit_preference, 'good'::condition, '["spring","summer"]'::jsonb,
    15, 20, 0, 95.00, 'USD', 'Sunspel',
    34, 4, 'clean'::laundry_state, 'available'::availability_state),

  ('Heavyweight Pocket Tee', 'Buck Mason', 'top'::clothing_category, 't-shirt', 'Heather Grey',
    '[]'::jsonb, 'solid', '[{"fiber":"cotton","percentage":100}]'::jsonb, 'M',
    'regular'::fit_preference, 'good'::condition, '["spring","summer","fall"]'::jsonb,
    10, 25, 0, 42.00, 'USD', 'Buck Mason',
    21, 11, 'clean'::laundry_state, 'available'::availability_state),

  ('Long-Sleeve Riviera Polo', 'Sunspel', 'top'::clothing_category, 'polo', 'Navy',
    '[]'::jsonb, 'solid', '[{"fiber":"cotton","percentage":100}]'::jsonb, 'M',
    'slim'::fit_preference, 'like_new'::condition, '["spring","fall"]'::jsonb,
    25, 30, 0, 115.00, 'USD', 'Sunspel',
    9, 18, 'clean'::laundry_state, 'available'::availability_state),

  ('End-on-End Cotton Shirt', 'Drake''s', 'top'::clothing_category, 'dress shirt', 'White',
    '["sky blue"]'::jsonb, 'end-on-end weave', '[{"fiber":"cotton","percentage":100}]'::jsonb, '15.5/33',
    'tailored'::fit_preference, 'good'::condition, '["all_season"]'::jsonb,
    50, 25, 0, 245.00, 'USD', 'Drake''s',
    16, 6, 'clean'::laundry_state, 'available'::availability_state),

  ('Cotton Oxford Shirt', 'Drake''s', 'top'::clothing_category, 'oxford shirt', 'Sky Blue',
    '["white"]'::jsonb, 'oxford weave', '[{"fiber":"cotton","percentage":100}]'::jsonb, '15.5/33',
    'tailored'::fit_preference, 'fair'::condition, '["all_season"]'::jsonb,
    45, 30, 0, 225.00, 'USD', 'Drake''s',
    58, 2, 'worn_once'::laundry_state, 'available'::availability_state),

  ('Wool Cardigan', 'Aime Leon Dore', 'top'::clothing_category, 'cardigan', 'Olive',
    '[]'::jsonb, 'solid', '[{"fiber":"wool","percentage":100}]'::jsonb, 'M',
    'relaxed'::fit_preference, 'like_new'::condition, '["fall","winter"]'::jsonb,
    35, 60, 0, 295.00, 'USD', 'Aime Leon Dore',
    4, 40, 'clean'::laundry_state, 'available'::availability_state),

  ('Merino Crewneck Sweater "Lundy"', 'John Smedley', 'top'::clothing_category, 'sweater', 'Charcoal',
    '[]'::jsonb, 'solid', '[{"fiber":"merino wool","percentage":100}]'::jsonb, 'M',
    'slim'::fit_preference, 'good'::condition, '["fall","winter"]'::jsonb,
    40, 65, 0, 275.00, 'USD', 'John Smedley',
    27, 9, 'clean'::laundry_state, 'available'::availability_state),

  ('Italian Wool Half-Zip Sweater', 'Todd Snyder', 'top'::clothing_category, 'sweater', 'Camel',
    '[]'::jsonb, 'solid', '[{"fiber":"wool","percentage":90},{"fiber":"nylon","percentage":10}]'::jsonb, 'M',
    'tailored'::fit_preference, 'new_with_tags'::condition, '["fall","winter"]'::jsonb,
    45, 70, 0, 248.00, 'USD', 'Todd Snyder',
    0, null, 'clean'::laundry_state, 'available'::availability_state),

  -- ---------------------------------------------------------------------
  -- BOTTOMS (6)
  -- ---------------------------------------------------------------------
  ('Cotton Chino Short', 'Todd Snyder', 'bottom'::clothing_category, 'shorts', 'Navy',
    '[]'::jsonb, 'solid', '[{"fiber":"cotton","percentage":98},{"fiber":"elastane","percentage":2}]'::jsonb, '32',
    'slim'::fit_preference, 'good'::condition, '["summer"]'::jsonb,
    15, 10, 0, 98.00, 'USD', 'Todd Snyder',
    12, 30, 'clean'::laundry_state, 'available'::availability_state),

  ('Petit Standard Selvedge Jean', 'A.P.C.', 'bottom'::clothing_category, 'jeans', 'Indigo',
    '[]'::jsonb, 'solid', '[{"fiber":"cotton","percentage":100}]'::jsonb, '32x32',
    'slim'::fit_preference, 'worn'::condition, '["all_season"]'::jsonb,
    20, 35, 0, 230.00, 'USD', 'A.P.C.',
    72, 3, 'clean'::laundry_state, 'available'::availability_state),

  ('Slim Straight Jean', 'Left Field NYC', 'bottom'::clothing_category, 'jeans', 'Washed Black',
    '[]'::jsonb, 'solid', '[{"fiber":"cotton","percentage":99},{"fiber":"elastane","percentage":1}]'::jsonb, '32x32',
    'slim'::fit_preference, 'good'::condition, '["all_season"]'::jsonb,
    20, 35, 0, 225.00, 'USD', 'Left Field NYC',
    19, 14, 'clean'::laundry_state, 'available'::availability_state),

  ('Italian Chino', 'Todd Snyder', 'bottom'::clothing_category, 'chino trouser', 'Khaki',
    '[]'::jsonb, 'solid', '[{"fiber":"cotton","percentage":97},{"fiber":"elastane","percentage":3}]'::jsonb, '32x32',
    'tailored'::fit_preference, 'good'::condition, '["spring","fall"]'::jsonb,
    40, 30, 0, 128.00, 'USD', 'Todd Snyder',
    25, 7, 'clean'::laundry_state, 'available'::availability_state),

  ('Slim-Fit Wool Trouser', 'Incotex', 'bottom'::clothing_category, 'dress trouser', 'Charcoal Grey',
    '[]'::jsonb, 'solid', '[{"fiber":"wool","percentage":100}]'::jsonb, '32x32',
    'slim'::fit_preference, 'like_new'::condition, '["fall","winter"]'::jsonb,
    70, 45, 0, 395.00, 'USD', 'Incotex',
    11, 21, 'clean'::laundry_state, 'available'::availability_state),

  ('Cotton-Linen Trouser', 'Incotex', 'bottom'::clothing_category, 'dress trouser', 'Stone',
    '[]'::jsonb, 'solid', '[{"fiber":"cotton","percentage":70},{"fiber":"linen","percentage":30}]'::jsonb, '32x32',
    'tailored'::fit_preference, 'new_with_tags'::condition, '["spring","summer"]'::jsonb,
    55, 20, 0, 345.00, 'USD', 'Incotex',
    0, null, 'clean'::laundry_state, 'available'::availability_state),

  -- ---------------------------------------------------------------------
  -- OUTERWEAR (3)
  -- ---------------------------------------------------------------------
  ('Bedale Waxed Jacket', 'Barbour', 'outerwear'::clothing_category, 'field jacket', 'Sage Green',
    '["brown corduroy"]'::jsonb, 'solid', '[{"fiber":"cotton","percentage":100}]'::jsonb, '40',
    'regular'::fit_preference, 'good'::condition, '["fall","winter"]'::jsonb,
    30, 60, 70, 400.00, 'USD', 'Barbour',
    14, 25, 'clean'::laundry_state, 'available'::availability_state),

  ('Wool Field Jacket', 'Private White V.C.', 'outerwear'::clothing_category, 'field jacket', 'Olive',
    '[]'::jsonb, 'solid', '[{"fiber":"wool","percentage":80},{"fiber":"nylon","percentage":20}]'::jsonb, '40',
    'tailored'::fit_preference, 'good'::condition, '["fall","winter"]'::jsonb,
    40, 65, 40, 595.00, 'USD', 'Private White V.C.',
    8, 33, 'clean'::laundry_state, 'available'::availability_state),

  ('K-Jacket Unstructured Sport Coat', 'Boglioli', 'outerwear'::clothing_category, 'sport coat', 'Navy',
    '[]'::jsonb, 'hopsack weave', '[{"fiber":"wool","percentage":100}]'::jsonb, '40R',
    'tailored'::fit_preference, 'like_new'::condition, '["spring","fall"]'::jsonb,
    75, 45, 0, 1095.00, 'USD', 'Boglioli',
    6, 47, 'clean'::laundry_state, 'available'::availability_state),

  -- ---------------------------------------------------------------------
  -- SHOES (4)
  -- ---------------------------------------------------------------------
  ('Achilles Low Sneaker', 'Common Projects', 'shoes'::clothing_category, 'sneaker', 'White',
    '[]'::jsonb, 'solid', '[{"fiber":"leather","percentage":100}]'::jsonb, '10',
    null, 'fair'::condition, '["all_season"]'::jsonb,
    20, 10, 0, 430.00, 'USD', 'Common Projects',
    61, 1, 'clean'::laundry_state, 'available'::availability_state),

  ('Iron Ranger Boot', 'Red Wing', 'shoes'::clothing_category, 'boot', 'Amber Harness',
    '[]'::jsonb, 'solid', '[{"fiber":"leather","percentage":100}]'::jsonb, '9.5 D',
    null, 'good'::condition, '["fall","winter"]'::jsonb,
    35, 40, 60, 330.00, 'USD', 'Red Wing Heritage',
    28, 15, 'clean'::laundry_state, 'available'::availability_state),

  ('Leisure Handsewn Loafer', 'Alden', 'shoes'::clothing_category, 'loafer', 'Snuff Suede',
    '[]'::jsonb, 'solid', '[{"fiber":"suede","percentage":100}]'::jsonb, '9.5 D',
    null, 'good'::condition, '["spring","fall"]'::jsonb,
    55, 15, 0, 650.00, 'USD', 'Alden',
    17, 20, 'clean'::laundry_state, 'available'::availability_state),

  ('Harvard Oxford', 'Crockett & Jones', 'shoes'::clothing_category, 'oxford', 'Black Calf',
    '[]'::jsonb, 'solid', '[{"fiber":"leather","percentage":100}]'::jsonb, '9.5 E',
    null, 'like_new'::condition, '["all_season"]'::jsonb,
    85, 20, 0, 595.00, 'USD', 'Crockett & Jones',
    5, 60, 'clean'::laundry_state, 'available'::availability_state),

  -- ---------------------------------------------------------------------
  -- ACCESSORY (2)
  -- ---------------------------------------------------------------------
  ('Woven Leather Belt', 'Anderson''s', 'accessory'::clothing_category, 'belt', 'Brown',
    '[]'::jsonb, 'woven', '[{"fiber":"leather","percentage":100}]'::jsonb, '34',
    null, 'good'::condition, '["all_season"]'::jsonb,
    40, 0, 0, 195.00, 'USD', 'Anderson''s',
    30, 5, 'clean'::laundry_state, 'available'::availability_state),

  ('Grenadine Silk Tie', 'Drake''s', 'accessory'::clothing_category, 'tie', 'Navy',
    '[]'::jsonb, 'solid grenadine', '[{"fiber":"silk","percentage":100}]'::jsonb, 'One Size',
    null, 'like_new'::condition, '["all_season"]'::jsonb,
    80, 0, 0, 175.00, 'USD', 'Drake''s',
    7, 90, 'clean'::laundry_state, 'available'::availability_state),

  -- ---------------------------------------------------------------------
  -- WATCH (1)
  -- ---------------------------------------------------------------------
  ('Club Campus', 'Nomos Glashütte', 'watch'::clothing_category, 'dress watch', 'Steel / White Dial',
    '[]'::jsonb, 'solid', '[{"fiber":"stainless steel","percentage":100},{"fiber":"leather","percentage":100}]'::jsonb, '38mm',
    null, 'like_new'::condition, '["all_season"]'::jsonb,
    60, 0, 30, 1900.00, 'USD', 'Nomos Glashütte',
    3, 50, 'clean'::laundry_state, 'available'::availability_state),

  -- ---------------------------------------------------------------------
  -- FRAGRANCE (1)
  -- ---------------------------------------------------------------------
  ('Santal 33 EDP', 'Le Labo', 'fragrance'::clothing_category, 'eau de parfum', 'N/A',
    '[]'::jsonb, null, '[]'::jsonb, '50ml',
    null, 'good'::condition, '["all_season"]'::jsonb,
    0, 0, 0, 280.00, 'USD', 'Le Labo',
    1, 60, 'clean'::laundry_state, 'available'::availability_state)
)
insert into public.closet_items (
  id, user_id, name, brand, category, subcategory, primary_color, secondary_colors, pattern,
  material, size, fit, condition, seasonality,
  formality_score, warmth_score, water_resistance_score,
  price_paid, currency, retailer,
  wear_count, last_worn_at, laundry_state, availability_state
)
select
  -- Deterministic id: stable across re-runs for the same (user, item name),
  -- distinct across users, so ON CONFLICT below updates instead of
  -- duplicating. Not a cryptographic UUID (v4/v5) — just a stable-format
  -- 36-character value the `uuid` column type accepts.
  (regexp_replace(
    md5('astra-vertical-slice-seed:' || su.user_id::text || ':' || i.name),
    '^(.{8})(.{4})(.{4})(.{4})(.{12})$', '\1-\2-\3-\4-\5'
  ))::uuid,
  su.user_id,
  i.name, i.brand, i.category, i.subcategory, i.primary_color, i.secondary_colors, i.pattern,
  i.material, i.size, i.fit, i.condition, i.seasonality,
  i.formality_score, i.warmth_score, i.water_resistance_score,
  i.price_paid, i.currency, i.retailer,
  i.wear_count,
  case when i.days_since_last_worn is null then null
       else now() - (i.days_since_last_worn || ' days')::interval
  end,
  i.laundry_state, i.availability_state
from items i
cross join seed_user su
on conflict (id) do update set
  name                   = excluded.name,
  brand                  = excluded.brand,
  category                = excluded.category,
  subcategory             = excluded.subcategory,
  primary_color           = excluded.primary_color,
  secondary_colors        = excluded.secondary_colors,
  pattern                 = excluded.pattern,
  material                = excluded.material,
  size                    = excluded.size,
  fit                     = excluded.fit,
  condition               = excluded.condition,
  seasonality             = excluded.seasonality,
  formality_score         = excluded.formality_score,
  warmth_score            = excluded.warmth_score,
  water_resistance_score  = excluded.water_resistance_score,
  price_paid              = excluded.price_paid,
  currency                = excluded.currency,
  retailer                = excluded.retailer,
  wear_count              = excluded.wear_count,
  last_worn_at            = excluded.last_worn_at,
  laundry_state           = excluded.laundry_state,
  availability_state      = excluded.availability_state,
  updated_at               = now();

\echo Done. 25 closet_items rows upserted for :seed_user_id.
\echo Verify with: select category, count(*) from closet_items where user_id = :seed_user_id group by category order by category;

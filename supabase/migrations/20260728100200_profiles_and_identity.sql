-- ============================================================================
-- Astra Style — 03. Profiles & identity
-- ============================================================================
-- Tables: profiles, style_profiles, body_profiles, lifestyle_profiles
--
-- SCORE CONVENTION (applies to every migration in this project, documented once
-- here and referenced elsewhere):
--   - Any column named `*_score` is an INTEGER 0-100 (inclusive), enforced with a
--     `check (col between 0 and 100)`. This matches §10's "Compatibility score
--     0-100" and §26's `compatibilityScore: Int`.
--   - Any column representing a probability/confidence (not a product "score" in
--     the stylist sense) is `numeric(3,2)` constrained to `[0, 1]`, e.g.
--     style_memories.confidence, kyra_messages.model_metadata confidence fields.
--   - `outfit_wears.rating` is an exception: it is a 1-5 user star rating, not a
--     computed score, and is documented as such at its declaration.
--
-- SOFT DELETE CONVENTION:
--   Only tables where the product spec explicitly calls for reversible removal,
--   or where hard-deleting would break downstream historical analytics (cost per
--   wear, wear history), use a nullable `archived_at` / `deleted_at` timestamptz.
--   Everywhere else, ordinary `on delete cascade` foreign keys to auth.users(id)
--   handle removal, and privacy-sensitive tables (style_memories) are hard-delete
--   only by design — see docs/04-data-model.md.
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- profiles
-- ----------------------------------------------------------------------------
-- Deliberate exception to "every table has a `user_id` column defaulting via
-- gen_random_uuid() PK": profiles.id *is* the auth.users.id. This is the
-- standard Supabase 1:1 profile pattern, and it's how handle_new_user()
-- (20260728101200_functions_and_triggers.sql) creates the row on signup — it
-- inserts `id = new.id` from the auth.users trigger, so a default here would be
-- actively wrong (the row's own generated uuid would never match the auth user).
create table if not exists public.profiles (
  id                       uuid primary key references auth.users(id) on delete cascade,
  display_name             text,
  avatar_url               text,
  location_name            text,
  timezone                 text not null default 'UTC',
  units                    units_preference not null default 'imperial',
  theme                    theme_preference not null default 'system',
  onboarding_completed_at  timestamptz,
  subscription_tier        subscription_tier not null default 'free',
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

comment on table public.profiles is
  'One row per auth.users identity, created by handle_new_user(). id is the auth user id, not an independently generated uuid.';
comment on column public.profiles.subscription_tier is
  'Denormalized read-fast copy of entitlement state; the authoritative record is subscriptions, reconciled via POST /subscriptions/sync and the App Store webhook (§14/§16).';

-- ----------------------------------------------------------------------------
-- style_profiles (1:1 with a user)
-- ----------------------------------------------------------------------------
create table if not exists public.style_profiles (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null unique references auth.users(id) on delete cascade,
  primary_identity       style_identity,
  secondary_identities   jsonb not null default '[]'::jsonb,
  -- Onboarding step §6.4 ("Style goals", multi-select) is not listed in §9's
  -- style_profiles field list, but the onboarding flow requires storing it
  -- somewhere; style_profiles is the natural home alongside the other identity
  -- signals. Documented as an addition beyond the literal §9 table in
  -- docs/04-data-model.md.
  style_goals            jsonb not null default '[]'::jsonb,
  preferred_colors       jsonb not null default '[]'::jsonb,
  avoided_colors         jsonb not null default '[]'::jsonb,
  preferred_fit          fit_preference,
  formality_preference   formality_preference,
  logo_tolerance         smallint check (logo_tolerance between 0 and 100),
  trend_tolerance        smallint check (trend_tolerance between 0 and 100),
  accessory_preference   accessory_preference,
  style_summary          text,
  -- vector(1536): see docs/04-data-model.md "Vector dimension choice". Changing
  -- this dimension later requires a full column rewrite + re-embedding backfill
  -- of every existing row — it is not a metadata-only migration.
  embedding              extensions.vector(1536),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

comment on table public.style_profiles is
  'Style DNA: the output of onboarding (§6.5, §6.9, §6.10) plus its embedding for style-similarity queries.';
comment on column public.style_profiles.secondary_identities is
  'jsonb array of style_identity string values (§6.5: "choose three, then rank one primary" -> primary_identity + 2 secondary_identities entries).';
comment on column public.style_profiles.embedding is
  'Semantic embedding of style_summary + preference vector, used for style-similar outfit/product retrieval. Dimension: 1536, see docs/04-data-model.md.';

-- ----------------------------------------------------------------------------
-- body_profiles (1:1 with a user)
-- ----------------------------------------------------------------------------
create table if not exists public.body_profiles (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null unique references auth.users(id) on delete cascade,
  -- Canonical storage unit is metric (cm / kg) regardless of profiles.units,
  -- which only controls display formatting on the client. This avoids ambiguous
  -- unit-tagged numeric columns.
  height_value_cm   numeric(5,2) check (height_value_cm > 0),
  weight_value_kg   numeric(5,2) check (weight_value_kg > 0),
  chest_cm          numeric(5,2) check (chest_cm > 0),
  waist_cm          numeric(5,2) check (waist_cm > 0),
  inseam_cm         numeric(5,2) check (inseam_cm > 0),
  neck_cm           numeric(5,2) check (neck_cm > 0),
  shoe_size         text,
  shirt_size        text,
  trouser_size      text,
  fit_notes         jsonb not null default '[]'::jsonb,
  -- §6.7 Appearance profile is not part of §9's literal body_profiles field
  -- list but is a required onboarding step feeding Style Studio's reference
  -- image handling (§13). Folded into a single catch-all jsonb here rather than
  -- adding six more nullable columns, since every field is optional,
  -- free-form, and user-omittable by design ("Explain why each is used and
  -- allow omission", §6.7). Documented in docs/04-data-model.md.
  appearance        jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.body_profiles is
  'Measurements + fit issues + optional appearance attributes from §6.6/§6.7. "I don''t know" is represented by leaving a column null, not a sentinel value.';
comment on column public.body_profiles.fit_notes is
  'jsonb array of free-text/short-code fit issues, e.g. ["broad_chest","short_torso"] (§6.6: "broad chest, short torso, long legs, large thighs, etc." — an open-ended list, hence jsonb rather than an enum).';
comment on column public.body_profiles.appearance is
  'Optional §6.7 fields: skin_undertone, hair_color, eye_color, facial_hair, wears_glasses, tattoos_visible, reference_selfie_paths (storage paths under users/{user_id}/references/, not the images themselves).';

-- ----------------------------------------------------------------------------
-- lifestyle_profiles (1:1 with a user)
-- ----------------------------------------------------------------------------
create table if not exists public.lifestyle_profiles (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null unique references auth.users(id) on delete cascade,
  occupation_category    text,
  dress_code             dress_code,
  common_occasions       jsonb not null default '[]'::jsonb,
  climate_preferences    jsonb not null default '{}'::jsonb,
  monthly_budget         numeric(10,2) check (monthly_budget >= 0),
  currency               text not null default 'USD' check (char_length(currency) = 3),
  preferred_brands       jsonb not null default '[]'::jsonb,
  avoided_brands         jsonb not null default '[]'::jsonb,
  -- Left as free text rather than an enum: §6.8 lists "laundry cadence" as a
  -- profile field without enumerating a fixed value set, and cadence phrasing
  -- ("twice a week", "whenever I run out") is naturally free-form input rather
  -- than a small closed set. Documented as an intentional choice.
  laundry_cadence        text,
  travel_frequency       text,
  religious_service_attire_needs text,
  sustainability_preference text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

comment on table public.lifestyle_profiles is
  'Onboarding §6.8 lifestyle inputs used by outfit generation and packing (weather/dress-code/laundry constraints).';
comment on column public.lifestyle_profiles.currency is
  'ISO 4217 currency code for monthly_budget; also the default currency assumed for closet_items.price_paid entries when not otherwise specified.';

-- ============================================================================
-- Wave 6 — women's second graph (ADR 0019)
-- Additive clothing_category values + profiles.wardrobe_graph.
-- Does NOT insert dress/skirt rows here (ADD VALUE same-transaction footgun).
-- ============================================================================

alter type public.clothing_category add value if not exists 'dress';
alter type public.clothing_category add value if not exists 'skirt';

do $$ begin
  create type public.wardrobe_graph as enum ('menswear_3_role', 'womenswear');
exception when duplicate_object then null; end $$;

comment on type public.wardrobe_graph is
  'Product picker chosen once at onboarding (ADR 0019). Not a Settings gender toggle.';

alter table public.profiles
  add column if not exists wardrobe_graph public.wardrobe_graph not null default 'menswear_3_role';

comment on column public.profiles.wardrobe_graph is
  'menswear_3_role keeps the current top/bottom/shoes graph. womenswear is dress-or-separates plus shoes.';

drop function if exists public.complete_onboarding(jsonb, jsonb, jsonb);
drop function if exists public.complete_onboarding(jsonb, jsonb, jsonb, text);

create function public.complete_onboarding(
  p_style_profile     jsonb,
  p_body_profile      jsonb,
  p_lifestyle_profile jsonb,
  p_wardrobe_graph    text default 'menswear_3_role'
)
returns public.profiles
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_profile public.profiles;
begin
  -- The ONLY identity source. There is no p_user_id parameter, so a caller
  -- cannot name a user at all — the ownership requirement in P2-ONBOARD-12
  -- ("rejects writes to a user_id other than the caller's") has no code path
  -- to be violated through, rather than being checked after the fact.
  if v_user_id is null then
    raise exception 'complete_onboarding() requires an authenticated caller'
      using errcode = '28000';
  end if;

  -- ---------------------------------------------------------------------
  -- style_profiles (§6.4 goals, §6.5 identity, §6.6 fit, §6.9 vector)
  -- ---------------------------------------------------------------------
  insert into public.style_profiles as sp (
    user_id,
    primary_identity,
    secondary_identities,
    style_goals,
    preferred_fit,
    preference_vector
  )
  values (
    v_user_id,
    nullif(p_style_profile ->> 'primary_identity', '')::public.style_identity,
    coalesce(p_style_profile -> 'secondary_identities', '[]'::jsonb),
    coalesce(p_style_profile -> 'style_goals', '[]'::jsonb),
    nullif(p_style_profile ->> 'preferred_fit', '')::public.fit_preference,
    -- '{}' (the column default) means the §6.9 step was skipped, which the
    -- spec permits. Stored verbatim: an axis absent from `dimensions` was
    -- never asked about and an axis present with observations 0 was asked
    -- and drew no preference, and only passing the document through
    -- unaltered keeps those two facts distinguishable.
    coalesce(p_style_profile -> 'preference_vector', '{}'::jsonb)
  )
  on conflict (user_id) do update set
    primary_identity     = excluded.primary_identity,
    secondary_identities = excluded.secondary_identities,
    style_goals          = excluded.style_goals,
    preferred_fit        = excluded.preferred_fit,
    preference_vector    = excluded.preference_vector;

  -- ---------------------------------------------------------------------
  -- body_profiles (§6.6 measurements, §6.7 appearance)
  -- ---------------------------------------------------------------------
  -- Every measurement is nullable and null IS the answer for "I don't know"
  -- (§6.6, and the table's own comment). The frame axes (frame_taper,
  -- frame_proportion, frame_scale, muscularity_hint) are NOT written here:
  -- derive_frame_axes() (20260729120000_frame_profile.sql) is a BEFORE
  -- INSERT OR UPDATE trigger that computes them from the measurements this
  -- statement writes, and writing them from here would fight it.
  insert into public.body_profiles as bp (
    user_id,
    height_value_cm, weight_value_kg,
    chest_cm, waist_cm, inseam_cm, neck_cm,
    shoe_size, shirt_size, trouser_size,
    fit_notes, appearance
  )
  values (
    v_user_id,
    (p_body_profile ->> 'height_value_cm')::numeric,
    (p_body_profile ->> 'weight_value_kg')::numeric,
    (p_body_profile ->> 'chest_cm')::numeric,
    (p_body_profile ->> 'waist_cm')::numeric,
    (p_body_profile ->> 'inseam_cm')::numeric,
    (p_body_profile ->> 'neck_cm')::numeric,
    nullif(p_body_profile ->> 'shoe_size', ''),
    nullif(p_body_profile ->> 'shirt_size', ''),
    nullif(p_body_profile ->> 'trouser_size', ''),
    coalesce(p_body_profile -> 'fit_notes', '[]'::jsonb),
    coalesce(p_body_profile -> 'appearance', '{}'::jsonb)
  )
  on conflict (user_id) do update set
    height_value_cm = excluded.height_value_cm,
    weight_value_kg = excluded.weight_value_kg,
    chest_cm        = excluded.chest_cm,
    waist_cm        = excluded.waist_cm,
    inseam_cm       = excluded.inseam_cm,
    neck_cm         = excluded.neck_cm,
    shoe_size       = excluded.shoe_size,
    shirt_size      = excluded.shirt_size,
    trouser_size    = excluded.trouser_size,
    fit_notes       = excluded.fit_notes,
    appearance      = excluded.appearance;

  -- ---------------------------------------------------------------------
  -- lifestyle_profiles (§6.8)
  -- ---------------------------------------------------------------------
  insert into public.lifestyle_profiles as lp (
    user_id,
    occupation_category, dress_code, common_occasions, typical_week,
    climate_preferences, monthly_budget, currency,
    preferred_brands, avoided_brands,
    laundry_cadence, travel_frequency,
    religious_service_attire_needs, sustainability_preference
  )
  values (
    v_user_id,
    nullif(p_lifestyle_profile ->> 'occupation_category', ''),
    nullif(p_lifestyle_profile ->> 'dress_code', '')::public.dress_code,
    coalesce(p_lifestyle_profile -> 'common_occasions', '[]'::jsonb),
    nullif(p_lifestyle_profile ->> 'typical_week', ''),
    coalesce(p_lifestyle_profile -> 'climate_preferences', '[]'::jsonb),
    (p_lifestyle_profile ->> 'monthly_budget')::numeric,
    -- NOT NULL with a 'USD' default and a char_length(currency) = 3 check,
    -- so an absent or empty value must fall back rather than be written.
    coalesce(nullif(p_lifestyle_profile ->> 'currency', ''), 'USD'),
    coalesce(p_lifestyle_profile -> 'preferred_brands', '[]'::jsonb),
    coalesce(p_lifestyle_profile -> 'avoided_brands', '[]'::jsonb),
    nullif(p_lifestyle_profile ->> 'laundry_cadence', ''),
    nullif(p_lifestyle_profile ->> 'travel_frequency', ''),
    nullif(p_lifestyle_profile ->> 'religious_service_attire_needs', ''),
    nullif(p_lifestyle_profile ->> 'sustainability_preference', '')
  )
  on conflict (user_id) do update set
    occupation_category           = excluded.occupation_category,
    dress_code                    = excluded.dress_code,
    common_occasions              = excluded.common_occasions,
    typical_week                  = excluded.typical_week,
    climate_preferences           = excluded.climate_preferences,
    monthly_budget                = excluded.monthly_budget,
    currency                      = excluded.currency,
    preferred_brands              = excluded.preferred_brands,
    avoided_brands                = excluded.avoided_brands,
    laundry_cadence               = excluded.laundry_cadence,
    travel_frequency              = excluded.travel_frequency,
    religious_service_attire_needs = excluded.religious_service_attire_needs,
    sustainability_preference     = excluded.sustainability_preference;

  -- ---------------------------------------------------------------------
  -- profiles.onboarding_completed_at — the criterion the whole ticket turns on
  -- ---------------------------------------------------------------------
  -- coalesce, not now(), so re-submitting (the user edits an answer and
  -- finishes again, or a retry lands after a response was lost in transit)
  -- does not move the date he actually finished. Idempotent by construction
  -- rather than by the caller remembering to check first.
  update public.profiles
  set
    onboarding_completed_at = coalesce(onboarding_completed_at, now()),
    -- Chosen once: later resubmits keep the graph already stamped.
    wardrobe_graph = case
      when onboarding_completed_at is null then
        coalesce(
          nullif(p_wardrobe_graph, '')::public.wardrobe_graph,
          'menswear_3_role'::public.wardrobe_graph
        )
      else wardrobe_graph
    end
  where id = v_user_id
  returning * into v_profile;

  if v_profile is null then
    -- Unreachable in normal operation: handle_new_user() creates this row
    -- from the auth.users trigger before any session exists. Raising rather
    -- than returning null means the whole transaction rolls back, so the
    -- three profile tables are never written for a user with no profiles
    -- row — the exact partial state this function exists to prevent.
    raise exception 'no profiles row for the authenticated user'
      using errcode = 'P0002';
  end if;

  return v_profile;
end;
$$;

comment on function public.complete_onboarding(jsonb, jsonb, jsonb, text) is
  'Atomic onboarding submission. Fourth arg is wardrobe_graph (ADR 0019), chosen once. Anonymous JWTs are authenticated and may call this.';

revoke all on function public.complete_onboarding(jsonb, jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.complete_onboarding(jsonb, jsonb, jsonb, text) to authenticated;

do $$
declare
  v_secdef boolean;
  v_config text[];
begin
  select p.prosecdef, p.proconfig
    into v_secdef, v_config
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'complete_onboarding';

  if not found then
    raise exception 'complete_onboarding() was not created';
  end if;
  if v_secdef then
    raise exception 'complete_onboarding() must be SECURITY INVOKER so RLS remains the boundary';
  end if;
  -- Postgres records `set search_path = ''` in proconfig as `search_path=""`.
  if v_config is null or not ('search_path=""' = any(v_config)) then
    raise exception 'complete_onboarding() must pin an empty search_path, got %', v_config;
  end if;
end $$;

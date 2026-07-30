-- ============================================================================
-- Astra Style — 20. complete_onboarding() RPC
-- ============================================================================
-- `POST /profile/complete-onboarding` (spec §14, ticket P2-ONBOARD-12) writes
-- four tables in one request: style_profiles, body_profiles,
-- lifestyle_profiles, and profiles.onboarding_completed_at.
--
-- WHY AN RPC RATHER THAN FOUR POSTGREST CALLS FROM THE EDGE FUNCTION.
--
-- Four separate `supabase.from(...).upsert(...)` calls are four separate
-- transactions. A network blip or a cold-start timeout between the second and
-- the third leaves a user with measurements saved, lifestyle missing, and
-- onboarding_completed_at set or not depending on where it stopped — a
-- half-written profile that every downstream consumer (Style DNA generation,
-- compatibility scoring, Kyra's context packet) then reads as complete but
-- thin. The client, meanwhile, keeps its local draft until the server
-- accepts (OnboardingViewModel.submit clears it only on success), so a
-- FAILED call costs the user one retry tap and loses nothing, while a
-- PARTIALLY SUCCEEDED one is silent and permanent. A partial profile is
-- strictly worse than a failed one, so the write is made all-or-nothing:
-- a plpgsql function body runs inside a single transaction, and any
-- exception rolls back every statement in it.
--
-- WHY SECURITY INVOKER.
--
-- Following 20260730170000_narrow_security_definer_scope.sql's reasoning:
-- DEFINER is for operations RLS cannot express, not for convenience. Every
-- write below is one `authenticated` is already allowed to make on its own
-- rows — style_profiles/body_profiles/lifestyle_profiles each have
-- `*_insert_own` and `*_update_own` policies, and profiles has
-- `profiles_update_own` (20260728100900_rls_policies.sql). Running as
-- INVOKER means RLS is still the boundary: even if the function body had a
-- predicate bug, Postgres would refuse a write to another user's row. A
-- DEFINER version would move that guarantee out of the database and into
-- this file's own correctness, for no capability gained.
--
-- WHY THE PARAMETERS ARE jsonb.
--
-- The three profile tables carry ~35 columns between them. Thirty-five
-- positional parameters is a signature nobody can call correctly twice, and
-- adding a column later would mean a new overload rather than an edit.
-- jsonb keeps the shape identical to the wire payload the Edge Function
-- already validated (`profile/schema.ts`), so there is one mapping step
-- (JSON -> column) in one place rather than two (JSON -> args -> column).
-- The Edge Function validates every enum-typed value against the same value
-- set Postgres would, so a bad value is a 400 from `schema.ts` rather than
-- a 22P02 cast error surfacing as a 500.
--
-- WHAT THIS FUNCTION DELIBERATELY DOES NOT WRITE.
--
-- style_profiles.formality_preference, .logo_tolerance, .trend_tolerance and
-- .accessory_preference are absent from the INSERT and from the ON CONFLICT
-- update list. That is not an oversight — it is the rule
-- 20260730180000_style_preference_vector.sql spells out: those four columns
-- are the Style DNA generator's considered summary across goals, identity,
-- lifestyle AND the preference vector (§6.10), not the quiz's raw inference.
-- `POST /style-dna/generate` owns them. Letting onboarding write them would
-- let three photographs overwrite a judgement made from everything the user
-- said, and — because ON CONFLICT DO UPDATE would run on every resubmission
-- — would silently revert a regenerated Style DNA the next time the user
-- edited an answer. preferred_colors, avoided_colors, style_summary and
-- embedding are left alone for the same reason.
-- ============================================================================

create or replace function public.complete_onboarding(
  p_style_profile     jsonb,
  p_body_profile      jsonb,
  p_lifestyle_profile jsonb
)
returns public.profiles
language plpgsql
security invoker
-- Empty search_path per 20260728101400_harden_function_search_path.sql: every
-- relation and type below is schema-qualified, so this is the strictest
-- setting that still works, and it fails loudly if an unqualified reference
-- is ever added rather than resolving it somewhere unexpected.
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
  set onboarding_completed_at = coalesce(onboarding_completed_at, now())
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

comment on function public.complete_onboarding(jsonb, jsonb, jsonb) is
  'Atomic §6.4-§6.9 onboarding submission behind POST /profile/complete-onboarding (P2-ONBOARD-12). Writes style_profiles, body_profiles, lifestyle_profiles and stamps profiles.onboarding_completed_at in ONE transaction, so a failure leaves nothing written rather than a half-populated profile. auth.uid() is the only identity source — there is no user-id parameter to substitute. SECURITY INVOKER: every write is one RLS already permits for the caller''s own rows. Deliberately does NOT write formality_preference/logo_tolerance/trend_tolerance/accessory_preference/preferred_colors/avoided_colors/style_summary — those are POST /style-dna/generate''s output (see 20260730180000_style_preference_vector.sql).';

-- Supabase grants EXECUTE on every newly created public-schema function to
-- anon/authenticated directly, so `revoke ... from public` alone does not
-- undo it — see 20260728101200_functions_and_triggers.sql's note. Revoke
-- from all three, then grant back only to `authenticated`: an anonymous
-- caller has no profile to complete, and auth.uid() would be null for one
-- anyway (guests never reach this endpoint at all — ADR 0011).
revoke all on function public.complete_onboarding(jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.complete_onboarding(jsonb, jsonb, jsonb) to authenticated;

-- ============================================================================
-- Verification
-- ============================================================================
-- Same pattern as 20260730170000_narrow_security_definer_scope.sql: fail the
-- migration now rather than discover at runtime that the function was created
-- with the wrong security mode or an unpinned search_path.
-- ============================================================================
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

  if v_secdef is null then
    raise exception 'complete_onboarding() was not created';
  end if;
  if v_secdef then
    raise exception 'complete_onboarding() must be SECURITY INVOKER so RLS remains the boundary';
  end if;
  -- Postgres records `set search_path = ''` in proconfig as the literal
  -- string `search_path=""` (the empty value is stored quoted), NOT as
  -- `search_path=`. Comparing against the unquoted form fails this block on a
  -- correctly-pinned function — which it did, on the first attempt to apply
  -- this migration, and is worth the two lines to say so here rather than
  -- rediscover.
  if v_config is null or not ('search_path=""' = any(v_config)) then
    raise exception 'complete_onboarding() must pin an empty search_path, got %', v_config;
  end if;
end
$$;

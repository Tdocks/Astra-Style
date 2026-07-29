-- 20260729120000_frame_profile.sql
--
-- Frame-aware fit (docs/14-frame-fit.md).
--
-- `body_profiles` already stores the measurements spec §6.6 collects. Nothing
-- read them. This migration adds the three derived axes, and — critically —
-- derives them IN THE DATABASE rather than on the client.
--
-- Why server-side: the axes feed two consumers that must agree. The iOS client
-- ranks outfits locally for the builder's live compatibility meter (§6.13),
-- and the Edge Functions rank them server-side for generation and for Kyra's
-- context. If each derived the frame from raw measurements independently, the
-- two would drift the first time either rounding rule changed, and the symptom
-- would be a score that differs between the meter and the result — which reads
-- to a user as the app being broken, and to us as unreproducible.
--
-- One derivation, one place, both consumers read the answer.

-- MARK: - Enums
--
-- Raw values must match the Swift cases in Domain/Models/FrameProfile.swift
-- exactly. scripts/check_schema_drift.py enforces this; the project has
-- already shipped 14+ Swift/Postgres enum mismatches that compile cleanly and
-- fail at INSERT.

create type frame_taper as enum ('straight', 'moderate', 'strong');
create type frame_proportion as enum ('long_torso', 'balanced', 'long_leg');
create type frame_scale as enum ('compact', 'average', 'tall');

alter table public.body_profiles
    add column frame_taper                   frame_taper,
    add column frame_taper_confidence        double precision,
    add column frame_proportion              frame_proportion,
    add column frame_proportion_confidence   double precision,
    add column frame_scale                   frame_scale,
    add column frame_scale_confidence        double precision,
    add column muscularity_hint              double precision;

-- Every column is nullable and every one stays null for a user who skipped the
-- measurements step. That is the majority case, not the edge case — spec §6.6
-- requires "I don't know" on every field — and the app must behave exactly as
-- it did before this migration when they are all null.

comment on column public.body_profiles.frame_taper is
    'Derived from the chest-waist drop. Never user-entered, never displayed as a label.';
comment on column public.body_profiles.frame_taper_confidence is
    '0-1. Drives whether fit advice is phrased as a reason or as a suggestion.';
comment on column public.body_profiles.muscularity_hint is
    'Neck against chest, 0-1. Modulates fabric-tension rules. Weight is deliberately not an input.';

-- MARK: - Derivation
--
-- Mirrors Domain/Services/FrameDerivation.swift. The two are kept in step by
-- FrameDerivationParityTests, which runs the same fixture cases through both.

create or replace function public.derive_frame_axes()
returns trigger
language plpgsql
security invoker
-- `search_path = ''` is required by 20260728101400_harden_function_search_path
-- (a mutable search_path on a SECURITY-adjacent function is a documented
-- injection vector). The consequence is that NOTHING unqualified resolves in
-- this body -- including the enum types in the casts below, which is why every
-- one of them reads `::public.frame_taper` rather than `::frame_taper`. An
-- unqualified cast here does not fail at migration time; it fails at the first
-- INSERT, with "type frame_taper does not exist".
set search_path = ''
as $$
declare
    v_to_inches      constant double precision := 1 / 2.54;
    v_height         double precision;
    v_chest          double precision;
    v_waist          double precision;
    v_inseam         double precision;
    v_neck           double precision;
    v_drop           double precision;
    v_ratio          double precision;
    v_edge           double precision;
begin
    -- `body_profiles` stores centimetres, always, regardless of profiles.units
    -- (which is display formatting only -- see the column comments on the
    -- creating migration, 20260728100200). An earlier draft of this function
    -- joined `profiles` to read the unit and scaled accordingly; that was built
    -- on a false premise and would have divided every metric user's
    -- measurements by 2.54 a second time.
    --
    -- The bands below are stated in INCHES because a "7 drop" is a real, named
    -- grade in tailoring -- restating it as 17.78 would make it look arbitrary.
    -- So there is exactly one conversion, cm to inches, and it is unconditional.

    -- Plausible adult ranges in inches, applied after conversion. These catch a
    -- value entered in inches into a centimetre column, a typo'd extra digit,
    -- and a field left at zero -- each of which otherwise yields authoritative
    -- nonsense that no one can see is wrong.
    v_height := nullif(new.height_value_cm, 0) * v_to_inches;
    if v_height is not null and (v_height < 48 or v_height > 90) then v_height := null; end if;

    v_chest := nullif(new.chest_cm, 0) * v_to_inches;
    if v_chest is not null and (v_chest < 26 or v_chest > 70) then v_chest := null; end if;

    v_waist := nullif(new.waist_cm, 0) * v_to_inches;
    if v_waist is not null and (v_waist < 22 or v_waist > 70) then v_waist := null; end if;

    v_inseam := nullif(new.inseam_cm, 0) * v_to_inches;
    if v_inseam is not null and (v_inseam < 22 or v_inseam > 42) then v_inseam := null; end if;

    v_neck := nullif(new.neck_cm, 0) * v_to_inches;
    if v_neck is not null and (v_neck < 11 or v_neck > 24) then v_neck := null; end if;

    -- Reset before recomputing, so clearing a measurement clears its axis
    -- rather than leaving a stale conclusion behind.
    new.frame_taper := null;
    new.frame_taper_confidence := null;
    new.frame_proportion := null;
    new.frame_proportion_confidence := null;
    new.frame_scale := null;
    new.frame_scale_confidence := null;
    new.muscularity_hint := null;

    -- Taper: the tailoring drop. 7"+ athletic, 4.5-7" regular, below straight.
    if v_chest is not null and v_waist is not null then
        v_drop := v_chest - v_waist;
        new.frame_taper := case
            when v_drop >= 7   then 'strong'
            when v_drop >= 4.5 then 'moderate'
            else 'straight'
        end::public.frame_taper;
        -- Confidence falls off near a band edge: 6.9" and 7.1" are not
        -- meaningfully different, and flipping the advice between them is false
        -- precision the user can feel.
        v_edge := least(abs(v_drop - 7), abs(v_drop - 4.5));
        new.frame_taper_confidence := 0.65 + 0.35 * least(v_edge / 2.0, 1);
    end if;

    -- Proportion: leg length against height.
    if v_height is not null and v_inseam is not null then
        v_ratio := v_inseam / v_height;
        -- Guard the RELATIONSHIP as well as each value. An inseam over 58% of
        -- height is anatomically impossible and means the two were entered in
        -- different units or transposed.
        if v_ratio >= 0.35 and v_ratio <= 0.58 then
            new.frame_proportion := case
                when v_ratio >= 0.48 then 'long_leg'
                when v_ratio >= 0.45 then 'balanced'
                else 'long_torso'
            end::public.frame_proportion;
            v_edge := least(abs(v_ratio - 0.48), abs(v_ratio - 0.45));
            new.frame_proportion_confidence := 0.7 + 0.3 * least(v_edge / 0.02, 1);
        end if;
    end if;

    -- Scale.
    if v_height is not null then
        new.frame_scale := case
            when v_height >= 73 then 'tall'
            when v_height >= 67 then 'average'
            else 'compact'
        end::public.frame_scale;
        v_edge := least(abs(v_height - 73), abs(v_height - 67));
        new.frame_scale_confidence := 0.75 + 0.25 * least(v_edge / 2.0, 1);
    end if;

    -- Muscularity hint: neck against chest. Separates muscular from broad at
    -- the same chest. Weight would be the obvious input and is deliberately
    -- unused -- most shame-adjacent field, least informative.
    if v_neck is not null and v_chest is not null and v_chest > 0 then
        new.muscularity_hint := greatest(0, least(1, ((v_neck / v_chest) - 0.33) / 0.05));
    end if;

    -- Stated fit issues override derived axes, at full confidence. The user has
    -- stood in front of a mirror; we have divided two numbers. When they
    -- disagree he is right, and an app that quietly overrules a man's own
    -- account of his body has failed at something more important than fit.
    if new.fit_notes is not null then
        if new.fit_notes ? 'broad_chest' then
            new.frame_taper := 'strong'::public.frame_taper;
            new.frame_taper_confidence := 1;
        end if;
        if new.fit_notes ? 'narrow_shoulders' then
            new.frame_taper := 'straight'::public.frame_taper;
            new.frame_taper_confidence := 1;
        end if;
        if new.fit_notes ? 'short_torso' or new.fit_notes ? 'long_legs' then
            new.frame_proportion := 'long_leg'::public.frame_proportion;
            new.frame_proportion_confidence := 1;
        end if;
        if new.fit_notes ? 'long_torso' or new.fit_notes ? 'short_legs' then
            new.frame_proportion := 'long_torso'::public.frame_proportion;
            new.frame_proportion_confidence := 1;
        end if;
        if new.fit_notes ? 'tall_frame' then
            new.frame_scale := 'tall'::public.frame_scale;
            new.frame_scale_confidence := 1;
        end if;
        if new.fit_notes ? 'short_frame' then
            new.frame_scale := 'compact'::public.frame_scale;
            new.frame_scale_confidence := 1;
        end if;
        -- `large_thighs` is deliberately NOT mapped to an axis. It is a fact
        -- about legs; filing it into `frame_taper` would turn it into advice
        -- about jackets, which is not what the user said. The scorer reads it
        -- straight off fit_notes.
    end if;

    return new;
end;
$$;

create trigger body_profiles_derive_frame
    before insert or update of
        height_value_cm, weight_value_kg, chest_cm, waist_cm, inseam_cm, neck_cm, fit_notes
    on public.body_profiles
    for each row
    execute function public.derive_frame_axes();

-- Backfill existing rows through the same trigger, so there is exactly one
-- derivation path and no possibility of backfilled rows disagreeing with
-- freshly written ones.
--
-- `set chest_cm = chest_cm` rather than the more natural `set updated_at = updated_at`:
-- the trigger is declared `before update OF (height_value_cm, ..., fit_notes)`, and
-- that clause fires on the columns MENTIONED in the SET list, not on the ones
-- whose values actually changed. Touching `updated_at` therefore does not fire
-- the trigger at all -- the backfill would have run, reported rows updated, and
-- left every existing frame null. `chest_cm` is in the list, so this fires.
update public.body_profiles set chest_cm = chest_cm;

-- No new RLS policy is needed: these are columns on `body_profiles`, which is
-- already covered by its owner-only policies from 20260728100900_rls_policies.
-- Verified rather than assumed -- adding columns to an RLS-protected table
-- inherits the table's policies, and a derived column exposing a user's
-- proportions to another account would be a serious leak.

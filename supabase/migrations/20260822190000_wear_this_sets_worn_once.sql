-- ============================================================================
-- Astra Style — Wear This must leave a mark the next brief can see
-- ============================================================================
-- `outfit_wears` insert already fires `bump_closet_item_wear_stats()`, which
-- increments `wear_count` and advances `last_worn_at`. Home's Wear This, the
-- outfit-detail Wear This, and Kyra's `mark_item_worn` all go through that
-- insert, so the count cannot drift from the rows.
--
-- What it did NOT do is move `laundry_state`. Closet's item-level "Mark worn"
-- writes `worn_once` itself (`LiveClosetRepository.markWorn`). Wear This
-- never called that path — on purpose: calling it after `recordWear` would
-- double-count `wear_count`. The result was that a man who tapped Wear This
-- still had every garment `laundry_state = clean`, so tomorrow's brief could
-- honestly pick the same look. The 0.05 availability weight cannot beat
-- colour. Habit requires the state change, not a hope that scoring will
-- notice a timestamp it was not even mapping.
--
-- WHY THIS IS ITS OWN MIGRATION. `20260728101200_functions_and_triggers.sql`
-- has shipped. Editing it in place would silently change the function anyone
-- who already ran that file is holding. CREATE OR REPLACE here is the
-- append-only description of the change.
--
-- WHAT CHANGES. On wear, `clean` becomes `worn_once`. `laundry` and
-- `unavailable` are left alone: Wear This is not "Into the wash", and a
-- garment already in the hamper or marked unavailable must not be rewritten
-- as wearable-once. `worn_once` stays `worn_once` (idempotent).
--
-- SEARCH_PATH. `20260728101400_harden_function_search_path.sql` pinned this
-- function to `search_path = ''`. CREATE OR REPLACE would drop that catalog
-- setting unless it is restated here, so it is restated. Every relation and
-- enum is schema-qualified for the same reason.
-- ============================================================================

create or replace function public.bump_closet_item_wear_stats()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.closet_items ci
  set wear_count = ci.wear_count + 1,
      last_worn_at = greatest(coalesce(ci.last_worn_at, new.worn_at), new.worn_at),
      laundry_state = case
        when ci.laundry_state = 'clean'::public.laundry_state
          then 'worn_once'::public.laundry_state
        else ci.laundry_state
      end
  from public.outfit_items oi
  where oi.outfit_id = new.outfit_id
    and oi.closet_item_id = ci.id
    and ci.user_id = new.user_id;

  return new;
end;
$$;

comment on function public.bump_closet_item_wear_stats() is
  'On outfit_wears insert, increments wear_count, advances last_worn_at, and moves laundry_state from clean to worn_once for every owned closet_item in that outfit. Does not touch laundry or unavailable — Wear This is not Into the wash. Feeds cost_per_wear = price_paid / wear_count, computed at read time rather than stored.';

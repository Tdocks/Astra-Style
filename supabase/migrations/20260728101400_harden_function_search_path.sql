-- ============================================================================
-- Astra Style — 15. Harden trigger-function search_path
-- ============================================================================
-- Supabase's security advisor (lint 0011_function_search_path_mutable) flagged
-- six functions created in 20260728101200_functions_and_triggers.sql as having
-- a role-mutable search_path:
--
--   set_updated_at, set_user_id_from_closet_item, set_user_id_from_outfit,
--   set_user_id_from_kyra_thread, touch_kyra_thread,
--   bump_closet_item_wear_stats
--
-- The other functions in that migration (handle_new_user, archive_closet_item,
-- restore_closet_item, the mark_account_deletion_* family) already pin it.
-- These six were simply missed.
--
-- WHY THIS MATTERS HERE
--
-- All six are SECURITY INVOKER, so this is not the classic SECURITY DEFINER
-- privilege-escalation hole, and exploitability on hosted Supabase is limited
-- because `authenticated` cannot create schemas or tables. It is still worth
-- closing, because three of these functions are what populate the `user_id`
-- column that RLS then filters on:
--
--   set_user_id_from_outfit reads public.outfits to stamp
--   outfit_items.user_id, and that value is what outfit_items' RLS policy
--   compares against auth.uid().
--
-- Any resolution path that could make those reads hit a different relation is
-- a path toward writing a row with someone else's user_id. The cost of
-- removing that class of question entirely is one line per function.
--
-- WHY `search_path = ''` RATHER THAN `= public`
--
-- Every one of the six bodies already schema-qualifies every relation it
-- touches (verified before writing this migration), and the only bare
-- identifiers are built-ins like now(), which always resolve from pg_catalog
-- regardless of search_path. An empty search_path is therefore the strictest
-- setting that still works, and it fails loudly if someone later adds an
-- unqualified reference rather than silently resolving it somewhere
-- unexpected. `= public` would keep working in that case, which is precisely
-- the failure mode worth avoiding.
--
-- Migrations are append-only (see CLAUDE.md), so this is a new file rather
-- than an edit to 20260728101200. ALTER FUNCTION ... SET is a catalog-only
-- change: it does not rewrite the function body, take a heavy lock, or
-- invalidate the triggers that reference these functions.
-- ============================================================================

do $$
declare
  fn text;
  fns text[] := array[
    'public.set_updated_at()',
    'public.set_user_id_from_closet_item()',
    'public.set_user_id_from_outfit()',
    'public.set_user_id_from_kyra_thread()',
    'public.touch_kyra_thread()',
    'public.bump_closet_item_wear_stats()'
  ];
begin
  foreach fn in array fns loop
    -- to_regprocedure returns null rather than raising if the function is
    -- absent, which keeps this migration safe to run against a database where
    -- an earlier migration has been partially applied.
    if to_regprocedure(fn) is not null then
      execute format('alter function %s set search_path = %L', fn, '');
      raise notice 'Pinned search_path for %', fn;
    else
      raise warning 'Skipped % — function not found', fn;
    end if;
  end loop;
end
$$;

-- ============================================================================
-- Verification
-- ============================================================================
-- Fails the migration if any of the six is still unpinned, so this cannot
-- silently no-op. proconfig is null when no per-function setting exists.
-- ============================================================================

do $$
declare
  unpinned text[];
begin
  select array_agg(p.proname order by p.proname)
    into unpinned
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'set_updated_at',
      'set_user_id_from_closet_item',
      'set_user_id_from_outfit',
      'set_user_id_from_kyra_thread',
      'touch_kyra_thread',
      'bump_closet_item_wear_stats'
    )
    and (
      p.proconfig is null
      or not exists (
        select 1 from unnest(p.proconfig) as cfg
        where cfg like 'search_path=%'
      )
    );

  if unpinned is not null then
    raise exception
      'search_path still mutable on: %. Expected all six trigger functions pinned.',
      array_to_string(unpinned, ', ');
  end if;
end
$$;

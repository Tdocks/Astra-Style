-- ============================================================================
-- Astra Style — 17. Narrow SECURITY DEFINER scope on the closet archive RPCs
-- ============================================================================
-- Supabase's security advisor (lint 0029_authenticated_security_definer_
-- function_executable) flagged three SECURITY DEFINER functions callable by
-- `authenticated`:
--
--   archive_closet_item(uuid), restore_closet_item(uuid),
--   request_account_deletion()
--
-- All three were written SECURITY DEFINER in
-- 20260728101200_functions_and_triggers.sql /
-- 20260728101300_account_deletion.sql. On inspection, only one of them
-- actually needs it — the other two were doing nothing RLS didn't already
-- allow, which is exactly the "probably intentional, so it's easy to miss
-- the one that isn't" shape this class of lint exists to catch.
--
-- WHY request_account_deletion() STAYS SECURITY DEFINER
-- -------------------------------------------------------
-- account_deletions has NO insert policy granted to `authenticated` at all
-- (20260728101300_account_deletion.sql: "No insert/update/delete policy is
-- granted to authenticated: rows are only ever written by the SECURITY
-- DEFINER functions below"). That is deliberate: the table's only
-- client-reachable write path is meant to be this one function, which
-- validates auth.uid() and the "no deletion already in progress" invariant
-- itself before inserting. A SECURITY INVOKER version would fail outright
-- for every caller — RLS blocks the INSERT unconditionally, regardless of
-- what the function body checks first — so DEFINER is not a convenience
-- here, it is the only mechanism by which this RPC can do its job at all.
-- Left unchanged; only its comment is refreshed below to say so explicitly,
-- so the next person reading this function doesn't have to re-derive it.
--
-- WHY archive_closet_item(uuid) / restore_closet_item(uuid) DO NOT
-- ------------------------------------------------------------------
-- closet_items is an ordinary entry in 20260728100900_rls_policies.sql's
-- owned_tables loop: `authenticated` already has a full UPDATE policy on it
-- — `using (user_id = (select auth.uid())) with check (user_id = (select
-- auth.uid()))`. Both functions' own UPDATE statements already filter on
-- `user_id = (select auth.uid())`; that predicate is not new, it was
-- already the ownership check the function body performed by hand. Running
-- the identical UPDATE, against the identical table, with the identical
-- predicate, as SECURITY INVOKER instead of DEFINER changes nothing about
-- which rows a caller can touch — RLS now enforces the same restriction the
-- function body already enforces, redundantly rather than exclusively.
-- There is no capability these two functions need that plain
-- `authenticated` table privileges plus RLS do not already grant, so
-- SECURITY DEFINER here was excess privilege, not a requirement. Narrowing
-- it removes the function from this advisor's WARN list without changing
-- its observable behavior (see supabase/tests/20_rls_isolation_tests.sql
-- SECTION 7, added alongside this migration, which asserts the pre-existing
-- ownership/idempotency behavior still holds under SECURITY INVOKER).
--
-- `ALTER FUNCTION ... SECURITY INVOKER` is a catalog-only change: it does
-- not rewrite the function body or take a heavy lock, consistent with how
-- 20260728101400_harden_function_search_path.sql treats the same kind of
-- edit. Migrations are append-only (see CLAUDE.md), so this is a new file
-- rather than an edit to 20260728101200_functions_and_triggers.sql.
-- ============================================================================

alter function public.archive_closet_item(uuid) security invoker;
alter function public.restore_closet_item(uuid) security invoker;

comment on function public.archive_closet_item(uuid) is
  'Soft-delete RPC for §6.15 "Archive" action. SECURITY INVOKER (narrowed from DEFINER by 20260730170000_narrow_security_definer_scope.sql): closet_items'' own RLS update policy already restricts `authenticated` to user_id = auth.uid(), identical to this function''s own WHERE clause, so DEFINER added no capability here — only extra attack surface the security advisor correctly flagged. auth.uid() (not a client-supplied user id) remains the only identity source.';

comment on function public.restore_closet_item(uuid) is
  'Reverses archive_closet_item(). SECURITY INVOKER for the same reason as archive_closet_item() — see that function''s comment and 20260730170000_narrow_security_definer_scope.sql. availability_state is reset to available; the caller/Edge Function is responsible for re-checking laundry_state if that matters for the specific flow.';

comment on function public.request_account_deletion() is
  'Uses auth.uid() only — never a client-supplied user id — so a caller can only request deletion of their own account. Returns the deletion_id the client polls via account_deletions. Deliberately left SECURITY DEFINER (see 20260730170000_narrow_security_definer_scope.sql), unlike archive_closet_item()/restore_closet_item(): account_deletions grants `authenticated` NO insert policy at all (20260728101300_account_deletion.sql), so this function''s elevated privilege is not a convenience, it is the only mechanism by which this INSERT can happen for any caller.';

-- ============================================================================
-- Verification
-- ============================================================================
-- Fails the migration if the three functions aren't in exactly the expected
-- DEFINER/INVOKER state, so a typo above (e.g. narrowing the wrong function,
-- or narrowing request_account_deletion by mistake and breaking it) cannot
-- silently pass. Same pattern as
-- 20260728101400_harden_function_search_path.sql's verification block.
-- ============================================================================

do $$
declare
  v_bad text[];
begin
  select array_agg(format('%s(%s): prosecdef=%s', p.proname, pg_get_function_identity_arguments(p.oid), p.prosecdef))
    into v_bad
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and (
      (p.proname in ('archive_closet_item', 'restore_closet_item') and p.prosecdef = true)
      or (p.proname = 'request_account_deletion' and p.prosecdef = false)
    );

  if v_bad is not null then
    raise exception
      'Unexpected SECURITY DEFINER/INVOKER state after narrowing: %. Expected archive_closet_item/restore_closet_item = INVOKER (prosecdef=false), request_account_deletion = DEFINER (prosecdef=true).',
      array_to_string(v_bad, ', ');
  end if;
end
$$;

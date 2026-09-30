-- Keep the existing user-facing RPCs callable while removing SECURITY
-- DEFINER from the exposed public schema. The privileged bodies stay in the
-- non-exposed private schema and derive identity from auth.uid(); callers
-- cannot supply a user id.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

-- Referral-code lookup needs to see another user's code, and setting
-- profiles.referred_by is intentionally restricted by RLS. Keep that narrow
-- operation in private; the public API entry point below is SECURITY INVOKER.
create or replace function private.apply_referral_code(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_referrer_id uuid;
  v_already_referred_by uuid;
  v_normalized_code text := pg_catalog.upper(pg_catalog.btrim(p_code));
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;
  if v_normalized_code is null or pg_catalog.length(v_normalized_code) = 0 then
    raise exception 'Enter a code.';
  end if;

  select profile.id
    into v_referrer_id
    from public.profiles as profile
   where profile.referral_code = v_normalized_code;

  if v_referrer_id is null then
    raise exception 'That code is not one of ours.';
  end if;
  if v_referrer_id = v_user_id then
    raise exception 'You cannot use your own code.';
  end if;

  select profile.referred_by
    into v_already_referred_by
    from public.profiles as profile
   where profile.id = v_user_id;

  if v_already_referred_by is not null then
    if v_already_referred_by = v_referrer_id then
      return;
    end if;
    raise exception 'A referral is already on this account.';
  end if;

  update public.profiles as profile
     set referred_by = v_referrer_id
   where profile.id = v_user_id
     and profile.referred_by is null;
end;
$$;

revoke all on function private.apply_referral_code(text) from public, anon, authenticated, service_role;
grant execute on function private.apply_referral_code(text) to authenticated, service_role;

comment on function private.apply_referral_code(text) is
  'Internal referral operation. Reads the caller only from auth.uid(), resolves one shareable code, and can set only that caller''s referred_by value.';

create or replace function public.apply_referral_code(p_code text)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.apply_referral_code(p_code);
$$;

revoke all on function public.apply_referral_code(text) from public, anon, authenticated, service_role;
grant execute on function public.apply_referral_code(text) to authenticated, service_role;

comment on function public.apply_referral_code(text) is
  'Authenticated RPC entry point. SECURITY INVOKER delegates the narrowly guarded privileged operation to private.apply_referral_code(text).';

-- Account deletion requests must insert into a table with no client INSERT
-- policy. Keep that single insert operation in private and derive its owner
-- from auth.uid(), preserving the one-in-flight-request guard.
create or replace function private.request_account_deletion()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_deletion_id uuid;
begin
  if v_user_id is null then
    raise exception 'request_account_deletion() requires an authenticated caller';
  end if;

  if exists (
    select 1
      from public.account_deletions as deletion
     where deletion.user_id = v_user_id
       and deletion.status in ('pending', 'processing')
  ) then
    raise exception 'An account deletion is already in progress for this user';
  end if;

  insert into public.account_deletions (user_id, status)
  values (v_user_id, 'pending')
  returning id into v_deletion_id;

  return v_deletion_id;
end;
$$;

revoke all on function private.request_account_deletion() from public, anon, authenticated, service_role;
grant execute on function private.request_account_deletion() to authenticated, service_role;

comment on function private.request_account_deletion() is
  'Internal account-deletion request operation. Requires auth.uid(), writes only that caller''s pending row, and rejects a second in-flight request.';

create or replace function public.request_account_deletion()
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.request_account_deletion();
$$;

revoke all on function public.request_account_deletion() from public, anon, authenticated, service_role;
grant execute on function public.request_account_deletion() to authenticated, service_role;

comment on function public.request_account_deletion() is
  'Authenticated RPC entry point. SECURITY INVOKER delegates to a private helper which uses auth.uid() and preserves the one-pending-request invariant.';

-- Fail the migration if the exposed wrappers are SECURITY DEFINER, if the
-- private bodies are not, or if role grants drift from the intended boundary.
do $$
declare
  v_bad_functions text[];
begin
  select array_agg(format('%I.%I(%s): prosecdef=%s', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid), p.prosecdef))
    into v_bad_functions
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
   where (n.nspname = 'public'
          and p.proname in ('apply_referral_code', 'request_account_deletion')
          and p.prosecdef)
      or (n.nspname = 'private'
          and p.proname in ('apply_referral_code', 'request_account_deletion')
          and not p.prosecdef);

  if v_bad_functions is not null then
    raise exception 'Unexpected SECURITY DEFINER state for callable RPCs: %', array_to_string(v_bad_functions, ', ');
  end if;

  if has_function_privilege('anon', 'public.apply_referral_code(text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.request_account_deletion()', 'EXECUTE')
     or has_function_privilege('anon', 'private.apply_referral_code(text)', 'EXECUTE')
     or has_function_privilege('anon', 'private.request_account_deletion()', 'EXECUTE') then
    raise exception 'Anonymous role must not execute either public RPC or private helper';
  end if;

  if not has_function_privilege('authenticated', 'public.apply_referral_code(text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.request_account_deletion()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.apply_referral_code(text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.request_account_deletion()', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.apply_referral_code(text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.request_account_deletion()', 'EXECUTE')
     or not has_function_privilege('service_role', 'private.apply_referral_code(text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'private.request_account_deletion()', 'EXECUTE') then
    raise exception 'Authenticated and service_role grants must preserve the existing RPC call paths';
  end if;

  if has_schema_privilege('anon', 'private', 'USAGE')
     or not has_schema_privilege('authenticated', 'private', 'USAGE')
     or not has_schema_privilege('service_role', 'private', 'USAGE') then
    raise exception 'Unexpected private schema USAGE grants';
  end if;
end
$$;

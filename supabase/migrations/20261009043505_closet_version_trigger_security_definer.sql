-- Supabase Auth deletes auth.users as `supabase_auth_admin`. The closet
-- cascade trigger maintains the scoring version on public.profiles, which
-- that managed role intentionally cannot update directly. Keep this narrow
-- trigger operation privileged through the function owner instead of
-- granting Auth (or application callers) broader profile-table access.
create or replace function public.bump_closet_state_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_user uuid;
begin
  -- Auth deletion can enqueue this child-row DELETE after the profile row
  -- has already been cascaded. In that case there is no counter to maintain.
  if tg_op = 'DELETE' and not exists (
    select 1 from public.profiles where id = old.user_id
  ) then
    return old;
  end if;

  if tg_op = 'DELETE' then
    affected_user := old.user_id;
  else
    affected_user := new.user_id;
  end if;
  if tg_op = 'UPDATE' and old.user_id is distinct from new.user_id then
    update public.profiles
       set closet_state_version = closet_state_version + 1
     where id = old.user_id;
  end if;
  update public.profiles
     set closet_state_version = closet_state_version + 1
   where id = affected_user;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.bump_closet_state_version() from public, anon, authenticated, service_role;

comment on function public.bump_closet_state_version() is
  'Trigger-only scoring-version maintenance. SECURITY DEFINER is required so Supabase Auth user deletion can cascade closet rows without granting supabase_auth_admin update access to profiles; affected user IDs come only from the trigger row.';

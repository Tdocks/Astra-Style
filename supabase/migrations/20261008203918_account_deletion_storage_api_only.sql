-- Account deletion: Storage API owns blob and metadata deletion.
-- Supabase now blocks direct DELETE on storage.objects, even when empty.
-- Keep the post-API verification so incomplete storage cleanup fails closed.
create or replace function public.finalize_account_deletion(p_deletion_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  select user_id into v_user_id
  from public.account_deletions
  where id = p_deletion_id;
  if v_user_id is null then
    raise exception 'Deletion request not found or already finalized';
  end if;

  if exists (
    select 1 from storage.objects
    where bucket_id = 'user-content'
      and (storage.foldername(name))[1] = 'users'
      and (storage.foldername(name))[2] = v_user_id::text
  ) then
    raise exception 'Storage API cleanup is incomplete';
  end if;

  update public.account_deletions
  set status = 'processing',
      user_id_hash = encode(extensions.digest(v_user_id::text, 'sha256'), 'hex')
  where id = p_deletion_id;
end;
$$;
comment on function public.finalize_account_deletion(uuid) is
  'Service-role only. Verifies Storage API cleanup before identity cascade; never mutates storage metadata directly.';
revoke all on function public.finalize_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.finalize_account_deletion(uuid) to service_role;


-- Caller-scoped append avoids restoring stale whole-profile snapshots.
create function public.associate_reference_photo(p_path text,p_acknowledged boolean)
returns setof public.body_profiles
language plpgsql security invoker set search_path='' as $$
declare u uuid:=(select auth.uid()); b public.body_profiles;
begin
  if u is null or coalesce((select auth.jwt())->>'is_anonymous','false')='true' then
    raise insufficient_privilege using message='reference_sign_in_required';
  end if;
  if p_acknowledged is distinct from true then raise exception 'reference_permission_required'; end if;
  if p_path is null or p_path !~ ('^users/'||u::text||'/references/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$') then
    raise exception 'reference_photo_unavailable';
  end if;
  if not exists(select 1 from storage.objects where bucket_id='user-content' and name=p_path) then
    raise exception 'reference_photo_unavailable';
  end if;
  insert into public.body_profiles(user_id) values(u) on conflict(user_id) do nothing;
  select * into b from public.body_profiles where user_id=u for update;
  if not coalesce(b.appearance->'reference_selfie_paths','[]'::jsonb) @> jsonb_build_array(p_path) then
    -- The existing body_reference_photo_guard rejects cleanup tombstones and
    -- holds path locks through this update, serializing erasure/association.
    update public.body_profiles set appearance=jsonb_set(appearance,'{reference_selfie_paths}',
      coalesce(appearance->'reference_selfie_paths','[]'::jsonb)||jsonb_build_array(p_path))
      where user_id=u returning * into b;
  end if;
  return next b;
end;
$$;
revoke all on function public.associate_reference_photo(text,boolean) from public,anon;
grant execute on function public.associate_reference_photo(text,boolean) to authenticated;

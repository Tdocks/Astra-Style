begin;
do $$
declare
  u uuid:=gen_random_uuid(); file_id uuid:=gen_random_uuid(); path text; token uuid:=gen_random_uuid();
  prepared integer; claimed public.studio_retention_jobs;
begin
  insert into auth.users(id,email) values(u,u||'@short-retention.invalid');
  path:='users/'||u||'/references/'||file_id||'.jpg';
  insert into storage.objects(bucket_id,name,created_at,updated_at)
    values('user-content',path,now()-interval '2 hours',now()-interval '2 hours');
  -- The config is transaction-local and rollback restores the production value.
  update public.studio_retention_config set enabled=true,reference_cleanup_enabled=true,
    abandoned_reference_hours=1 where singleton;
  prepared:=public.prepare_reference_retention(10);
  if prepared<>1 then raise exception 'One-hour retention did not select the two-hour-old reference'; end if;
  select * into claimed from public.claim_studio_retention(token,10)
    where kind='reference' and result_image_path=path;
  if claimed.id is null or claimed.status<>'processing' then raise exception 'Short-window reference was not claimed'; end if;
  -- Scratch SQL stand-in for the Storage API. The separate worker unit test
  -- asserts the real API removal call occurs before this fenced finalization.
  delete from storage.objects where bucket_id='user-content' and name=path;
  if not public.finish_studio_retention(claimed.id,token,true) then raise exception 'Short-window deletion did not finalize'; end if;
  if exists(select 1 from public.studio_retention_jobs where id=claimed.id and (status<>'complete' or result_image_path is not null)) then
    raise exception 'Completed reference queue retained private path or nonterminal state'; end if;
  if exists(select 1 from storage.objects where bucket_id='user-content' and name=path) then
    raise exception 'Expired reference Storage object remains'; end if;
  delete from auth.users where id=u;
end;
$$;
rollback;

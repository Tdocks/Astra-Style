begin;
do $$
declare
  u uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid();
  parent uuid:=gen_random_uuid(); child uuid:=gen_random_uuid(); active_g uuid:=gen_random_uuid();
  book uuid:=gen_random_uuid(); token uuid:=gen_random_uuid(); n integer; blocked boolean;
  j public.studio_retention_jobs; j2 public.studio_retention_jobs;
begin
  if has_table_privilege('authenticated','public.studio_generations','DELETE')
    or has_function_privilege('authenticated','public.prepare_studio_deletion(uuid,uuid)','EXECUTE')
    or has_function_privilege('anon','public.claim_studio_deletion(uuid,uuid,uuid)','EXECUTE') then
    raise exception 'Manual deletion privilege boundary is open'; end if;
  insert into auth.users(id,email) values(u,u||'@deletion.invalid'),(peer,peer||'@deletion.invalid');
  insert into public.studio_allowances(id,user_id,consumed_at) values(parent,u,now()),(child,u,now()),(active_g,u,null);
  insert into public.studio_generations(id,user_id,status,reference_image_path,result_image_path,allowance_id)
    values(parent,u,'complete','','users/'||u||'/studio/'||parent||'/result.png',parent),
      (child,u,'complete','users/'||u||'/studio/'||parent||'/result.png','users/'||u||'/studio/'||child||'/result.png',child),
      (active_g,u,'queued','',null,active_g);
  insert into public.studio_lookbooks(id,user_id,name) values(book,u,'Saved');
  insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(u,book,child);
  insert into storage.objects(bucket_id,name) values('user-content','users/'||u||'/studio/'||child||'/result.png');
  perform set_config('role','service_role',true);
  blocked:=false;
  begin perform public.prepare_studio_deletion(peer,child);
  exception when raise_exception then if sqlerrm<>'studio_delete_unavailable' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Deletion crossed owner fence'; end if;
  blocked:=false;
  begin perform public.prepare_studio_deletion(u,active_g);
  exception when raise_exception then if sqlerrm<>'studio_delete_in_progress' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Active generation deletion allowed'; end if;
  blocked:=false;
  begin perform public.prepare_studio_deletion(u,parent);
  exception when raise_exception then if sqlerrm<>'studio_delete_has_variations' then raise; end if; blocked:=true; end;
  if not blocked or exists(select 1 from public.studio_generations where id=parent and deleted_at is not null) then
    raise exception 'Dependent parent could be deleted'; end if;
  select * into j from public.prepare_studio_deletion(u,child);
  select * into j2 from public.prepare_studio_deletion(u,child);
  if j.id<>j2.id then raise exception 'Duplicate request created another job'; end if;
  select count(*) into n from public.claim_studio_deletion(peer,j.id,token);
  if n<>0 then raise exception 'Peer claimed deletion'; end if;
  select count(*) into n from public.claim_studio_deletion(u,j.id,token);
  if n<>1 then raise exception 'Owner claim failed'; end if;
  if exists(select 1 from public.claim_studio_deletion(u,j.id,gen_random_uuid())) then raise exception 'Active lease duplicated'; end if;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
  delete from storage.objects where name='users/'||u||'/studio/'||child||'/result.png';
  get diagnostics n=row_count;
  if n<>0 then raise exception 'Client bypassed Studio Storage deletion fence'; end if;
  if exists(select 1 from public.studio_lookbook_entries where generation_id=child) then raise exception 'Deleting saved look remained visible'; end if;
  blocked:=false;
  begin insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(u,book,child);
  exception when raise_exception then if sqlerrm<>'studio_save_unavailable' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Deleting generation could be saved'; end if;
  perform set_config('role','none',true);
  blocked:=false;
  begin insert into public.studio_generations(user_id,status,reference_image_path,allowance_id)
    values(u,'queued','users/'||u||'/studio/'||child||'/result.png',active_g);
  exception when raise_exception then if sqlerrm<>'studio_source_unavailable' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Deleting source admitted a reroll'; end if;
  -- Test-only metadata side effect; production removes files through Storage API.
  delete from storage.objects where name='users/'||u||'/studio/'||child||'/result.png';
  if not public.finish_studio_retention(j.id,token,true) then raise exception 'Deletion finalization failed'; end if;
  if exists(select 1 from public.studio_generations where id=child)
    or exists(select 1 from public.studio_lookbook_entries where generation_id=child) then raise exception 'Finalized deletion left generation/save'; end if;
  select * into j2 from public.prepare_studio_deletion(u,child);
  if j2.id<>j.id or j2.status<>'complete' then raise exception 'Completed request was not idempotent'; end if;
  if not exists(select 1 from public.studio_allowances where id=child and consumed_at is not null and released_at is null) then raise exception 'Deletion refunded successful usage'; end if;
  select * into j from public.prepare_studio_deletion(u,parent);
  if j.status<>'pending' then raise exception 'Removing variation did not free parent for deletion'; end if;
  delete from auth.users where id in(u,peer);
  if exists(select 1 from public.studio_retention_jobs where user_id=u) then raise exception 'Account erasure retained image cleanup'; end if;
  raise notice 'Individual deletion ownership, dependencies, idempotency, Storage fence, saves, retries and account erasure passed';
end;
$$;
rollback;

begin;
do $$
declare
  u uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid();
  old_g uuid:=gen_random_uuid(); saved_g uuid:=gen_random_uuid(); parent_g uuid:=gen_random_uuid(); child_g uuid:=gen_random_uuid();
  book uuid:=gen_random_uuid(); a uuid; n integer; token uuid:=gen_random_uuid(); j public.studio_retention_jobs;
  blocked boolean;
begin
  if has_function_privilege('authenticated','public.prepare_studio_retention(integer)','EXECUTE')
     or has_function_privilege('anon','public.authorize_studio_retention(text)','EXECUTE')
     or has_table_privilege('authenticated','public.studio_retention_config','SELECT')
     or has_column_privilege('authenticated','public.studio_retention_jobs','claim_token','SELECT') then
    raise exception 'Retention privilege boundary is open';
  end if;
  insert into auth.users(id,email) values(u,u::text||'@retention.invalid'),(peer,peer::text||'@retention.invalid');
  for a in select unnest(array[old_g,saved_g,parent_g,child_g]) loop
    insert into public.studio_allowances(id,user_id,consumed_at) values(a,u,now());
    insert into public.studio_generations(id,user_id,status,reference_image_path,result_image_path,allowance_id,retention_expires_at)
      values(a,u,'complete','','users/'||u||'/studio/'||a||'/result.png',a,now()-interval '1 day');
  end loop;
  update public.studio_generations set reference_image_path='users/'||u||'/studio/'||parent_g||'/result.png',retention_expires_at=now()+interval '1 day' where id=child_g;
  insert into public.studio_lookbooks(id,user_id,name) values(book,u,'Keep');
  insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(u,book,saved_g);
  if public.prepare_studio_retention(25)<>0 then raise exception 'Disabled cleanup prepared jobs'; end if;
  update public.studio_retention_config set enabled=true,scheduler_token_hash=encode(extensions.digest(repeat('a',64),'sha256'),'hex');
  if not public.authorize_studio_retention(repeat('a',64)) or public.authorize_studio_retention(repeat('b',64)) then
    raise exception 'Scheduler token validation failed'; end if;
  n:=public.prepare_studio_retention(25);
  if n<>1 then raise exception 'Sweep failed saved/dependent protection: prepared %',n; end if;
  if public.prepare_studio_retention(25)<>0 then raise exception 'Duplicate preparation'; end if;
  select * into j from public.claim_studio_retention(token,25);
  if j.generation_id<>old_g then raise exception 'Wrong expired job'; end if;
  if exists(select 1 from public.claim_studio_retention(gen_random_uuid(),25)) then raise exception 'Live claim duplicated'; end if;
  if public.finish_studio_retention(j.id,gen_random_uuid(),true) then raise exception 'Stale token finalized job'; end if;
  perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
  perform set_config('role','authenticated',true);
  blocked:=false;
  begin insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(u,book,old_g);
  exception when raise_exception then if sqlerrm<>'studio_save_unavailable' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Expired claimed estimate could be saved'; end if;
  select count(*) into n from public.studio_retention_jobs where user_id=u;
  if n<>1 then raise exception 'Owner cannot inspect safe cleanup metadata'; end if;
  perform set_config('request.jwt.claims',json_build_object('sub',peer,'role','authenticated')::text,true);
  select count(*) into n from public.studio_retention_jobs where user_id=u;
  if n<>0 then raise exception 'Peer cleanup metadata leaked'; end if;
  perform set_config('role','none',true);
  -- Real Storage API is not present in scratch SQL: mimic only its metadata
  -- side effect to assert the verification gate before/after removal.
  insert into storage.objects(bucket_id,name) values('user-content',j.result_image_path);
  blocked:=false;
  begin perform public.finish_studio_retention(j.id,token,true);
  exception when raise_exception then if sqlerrm<>'studio_retention_object_not_removed' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Row finalized while Storage object remained'; end if;
  perform public.finish_studio_retention(j.id,token,false);
  if exists(select 1 from public.claim_studio_retention(gen_random_uuid(),25)) then raise exception 'Retry backoff ignored'; end if;
  update public.studio_retention_jobs set claim_expires_at=now()-interval '1 second' where id=j.id;
  perform public.claim_studio_retention(token,25);
  delete from storage.objects where bucket_id='user-content' and name=j.result_image_path;
  if not public.finish_studio_retention(j.id,token,true) then raise exception 'Storage-verified finalization failed'; end if;
  if exists(select 1 from public.studio_generations where id=old_g) then raise exception 'Expired row remains'; end if;
  if not exists(select 1 from public.studio_allowances where id=old_g and consumed_at is not null) then raise exception 'Expiry refunded success'; end if;
  if not exists(select 1 from public.studio_retention_jobs where id=j.id and status='complete' and result_image_path is null and claim_token is null) then raise exception 'Completed job retains sensitive path/token'; end if;
  update public.studio_retention_config set output_retention_days=7;
  update public.studio_generations set status='queued' where id=child_g;
  update public.studio_generations set status='complete' where id=child_g;
  if not exists(select 1 from public.studio_generations where id=child_g and retention_expires_at between now()+interval '6 days' and now()+interval '8 days') then
    raise exception 'Configurable output window ignored on completion'; end if;
  delete from public.studio_lookbook_entries where generation_id=saved_g;
  if not exists(select 1 from public.studio_generations where id=saved_g and retention_expires_at between now()+interval '6 days' and now()+interval '8 days') then
    raise exception 'Configurable output window ignored after final unsave'; end if;
  delete from auth.users where id in(u,peer);
  if exists(select 1 from public.studio_retention_jobs where user_id in(u,peer)) then raise exception 'Erasure left retention jobs'; end if;
  raise notice 'Retention authorization, saved/dependent protection, claim recovery, Storage verification and erasure passed';
end;
$$;
rollback;

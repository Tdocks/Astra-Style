begin;
do $$
declare
  owner_id uuid := gen_random_uuid();
  active_owner uuid := gen_random_uuid();
  deleted_owner uuid := gen_random_uuid();
  complete_id uuid := gen_random_uuid();
  active_id uuid := gen_random_uuid();
  failed_id uuid := gen_random_uuid();
  deleted_id uuid := gen_random_uuid();
  token_a uuid := gen_random_uuid();
  token_b uuid := gen_random_uuid();
  token_c uuid := gen_random_uuid();
  path text;
  blocked boolean;
  claimed integer;
begin
  insert into auth.users(id,email) values
    (owner_id,owner_id||'@orphan-cleanup.invalid'),
    (active_owner,active_owner||'@orphan-cleanup.invalid'),
    (deleted_owner,deleted_owner||'@orphan-cleanup.invalid');
  insert into public.studio_allowances(id,user_id,consumed_at) values
    (complete_id,owner_id,now()),
    (active_id,active_owner,null),
    (failed_id,owner_id,null),
    (deleted_id,deleted_owner,null);
  insert into public.studio_generations(id,user_id,status,reference_image_path,result_image_path,allowance_id)
    values
      (complete_id,owner_id,'complete','', 'users/'||owner_id||'/studio/'||complete_id||'/result.png',complete_id),
      (active_id,active_owner,'queued','', null,active_id),
      (failed_id,owner_id,'failed','', 'users/'||owner_id||'/studio/'||failed_id||'/result.png',failed_id),
      (deleted_id,deleted_owner,'queued','', null,deleted_id);
  insert into storage.objects(bucket_id,name,owner,metadata) values
    ('user-content','users/'||owner_id||'/studio/'||complete_id||'/result.png',owner_id,'{"mimetype":"image/png"}'),
    ('user-content','users/'||owner_id||'/studio/'||failed_id||'/result.png',owner_id,'{"mimetype":"image/png"}'),
    ('user-content','users/'||deleted_owner||'/studio/'||deleted_id||'/result.png',deleted_owner,'{"mimetype":"image/png"}');

  path := 'users/'||owner_id||'/studio/'||complete_id||'/result.png';
  if has_table_privilege('service_role','auth.users','SELECT') then
    raise exception 'service_role unexpectedly has auth.users SELECT';
  end if;
  if has_table_privilege('anon','public.studio_orphan_result_cleanup_jobs','SELECT') or
     has_table_privilege('authenticated','public.studio_orphan_result_cleanup_jobs','SELECT') or
     has_table_privilege('anon','public.studio_orphan_result_cleanup_jobs','INSERT') or
     has_table_privilege('authenticated','public.studio_orphan_result_cleanup_jobs','INSERT') then
    raise exception 'orphan cleanup ledger is exposed to a client role';
  end if;
  if has_function_privilege('anon','public.enqueue_studio_orphan_result_cleanup(uuid,uuid,text)','EXECUTE') or
     has_function_privilege('authenticated','public.enqueue_studio_orphan_result_cleanup(uuid,uuid,text)','EXECUTE') or
     has_function_privilege('anon','public.claim_studio_orphan_result_cleanup(uuid,integer)','EXECUTE') or
     has_function_privilege('authenticated','public.claim_studio_orphan_result_cleanup(uuid,integer)','EXECUTE') then
    raise exception 'a client role can call the orphan cleanup RPC';
  end if;

  perform set_config('role','service_role',true);
  perform public.enqueue_studio_orphan_result_cleanup(owner_id,complete_id,path);
  blocked := false;
  begin
    perform public.enqueue_studio_orphan_result_cleanup(owner_id,complete_id,path||'/extra');
  exception when raise_exception then
    if sqlerrm = 'studio_orphan_result_path_invalid' then blocked := true; else raise; end if;
  end;
  if not blocked then raise exception 'noncanonical cleanup path was accepted'; end if;

  perform public.enqueue_studio_orphan_result_cleanup(active_owner,active_id,
    'users/'||active_owner||'/studio/'||active_id||'/result.png');
  perform public.enqueue_studio_orphan_result_cleanup(owner_id,failed_id,
    'users/'||owner_id||'/studio/'||failed_id||'/result.png');
  perform public.enqueue_studio_orphan_result_cleanup(deleted_owner,deleted_id,
    'users/'||deleted_owner||'/studio/'||deleted_id||'/result.png');

  if public.studio_orphan_result_disposition(owner_id,complete_id) <> 'preserve' then
    raise exception 'live completed generation was not protected';
  end if;
  if public.studio_orphan_result_disposition(active_owner,active_id) <> 'defer' then
    raise exception 'active generation was not deferred';
  end if;
  perform set_config('role','none',true);
  insert into public.account_deletions(user_id,status) values(active_owner,'pending');
  perform set_config('role','service_role',true);
  if public.studio_orphan_result_disposition(active_owner,active_id) <> 'remove' then
    raise exception 'pending account deletion did not make cleanup safe';
  end if;
  select count(*) into claimed from public.claim_studio_orphan_result_cleanup(token_a,25);
  if claimed <> 4 then raise exception 'worker did not lease every eligible cleanup row: %',claimed; end if;
  select count(*) into claimed from public.claim_studio_orphan_result_cleanup(token_b,25);
  if claimed <> 0 then raise exception 'a second worker bypassed the live lease'; end if;

  if not public.finish_studio_orphan_result_cleanup(
    (select id from public.studio_orphan_result_cleanup_jobs where storage_path=path),token_a,true
  ) then raise exception 'completed output cleanup intent did not finalize'; end if;
  if not exists(select 1 from storage.objects where bucket_id='user-content' and name=path) then
    raise exception 'stale cleanup intent deleted a valid completed output';
  end if;

  blocked := false;
  begin
    perform public.finish_studio_orphan_result_cleanup(
      (select id from public.studio_orphan_result_cleanup_jobs
       where storage_path='users/'||owner_id||'/studio/'||failed_id||'/result.png'),token_a,true
    );
  exception when raise_exception then
    if sqlerrm='studio_orphan_result_object_not_removed' then blocked := true; else raise; end if;
  end;
  if not blocked then raise exception 'cleanup completed while failed-job object still existed'; end if;
  if not exists(select 1 from public.studio_orphan_result_cleanup_jobs
    where storage_path='users/'||owner_id||'/studio/'||failed_id||'/result.png' and status='processing') then
    raise exception 'failed storage verification discarded the claimed retry';
  end if;
  if not public.finish_studio_orphan_result_cleanup(
    (select id from public.studio_orphan_result_cleanup_jobs
     where storage_path='users/'||owner_id||'/studio/'||failed_id||'/result.png'),token_a,false
  ) then raise exception 'failed cleanup could not return to retry queue'; end if;
  if not exists(select 1 from public.studio_orphan_result_cleanup_jobs
    where storage_path='users/'||owner_id||'/studio/'||failed_id||'/result.png' and status='pending'
      and claim_token is null and claim_expires_at is null) then
    raise exception 'failed cleanup did not retain an available retry';
  end if;
  perform set_config('role','none',true);
  delete from storage.objects where name='users/'||owner_id||'/studio/'||failed_id||'/result.png';
  perform set_config('role','service_role',true);
  update public.studio_orphan_result_cleanup_jobs set available_at=now()-interval '1 second'
    where storage_path='users/'||owner_id||'/studio/'||failed_id||'/result.png';
  select count(*) into claimed from public.claim_studio_orphan_result_cleanup(token_c,25);
  if claimed <> 1 then raise exception 'retry was not claimable after the failed object was removed'; end if;
  if not public.finish_studio_orphan_result_cleanup(
    (select id from public.studio_orphan_result_cleanup_jobs
     where storage_path='users/'||owner_id||'/studio/'||failed_id||'/result.png'),token_c,true
  ) then raise exception 'retry did not complete after successful removal'; end if;

  -- Auth deletion cascades the generation but must leave the no-FK ledger row
  -- available for the scheduled worker after the account is gone.
  perform set_config('role','none',true);
  delete from auth.users where id=deleted_owner;
  perform set_config('role','service_role',true);
  path := 'users/'||deleted_owner||'/studio/'||deleted_id||'/result.png';
  if not exists(select 1 from public.studio_orphan_result_cleanup_jobs where storage_path=path) then
    raise exception 'Auth cascade removed the durable cleanup receipt';
  end if;
  if public.studio_orphan_result_disposition(deleted_owner,deleted_id) <> 'remove' then
    raise exception 'generation removed by Auth cascade was not safely removable';
  end if;
  perform set_config('role','none',true);
  delete from storage.objects where name=path;
  perform set_config('role','service_role',true);
  if not public.finish_studio_orphan_result_cleanup(
    (select id from public.studio_orphan_result_cleanup_jobs where storage_path=path),token_a,true
  ) then raise exception 'Auth-deleted result receipt did not finish'; end if;
  if exists(select 1 from public.studio_orphan_result_cleanup_jobs where storage_path=path) then
    raise exception 'completed Auth-deletion cleanup receipt remained';
  end if;
  if public.finish_studio_orphan_result_cleanup(
    (select id from public.studio_orphan_result_cleanup_jobs
     where storage_path='users/'||active_owner||'/studio/'||active_id||'/result.png'),token_b,true
  ) then raise exception 'stale worker token finalized another lease'; end if;
end;
$$;
rollback;

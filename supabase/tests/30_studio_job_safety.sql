-- Scratch database only. All fixtures roll back; no provider calls.
begin;
do $$
declare
  u uuid:=gen_random_uuid(); other_u uuid:=gen_random_uuid();
  job public.studio_generations; retry_job public.studio_generations; duplicate public.studio_generations;
  t1 uuid:=gen_random_uuid(); t2 uuid:=gen_random_uuid(); n integer; blocked boolean;
begin
  insert into auth.users(id,email) values(u,u::text||'@studio-qa.invalid'),(other_u,other_u::text||'@studio-qa.invalid');
  if has_table_privilege('authenticated','public.studio_generations','INSERT')
     or has_table_privilege('authenticated','public.studio_generations','UPDATE')
     or has_table_privilege('authenticated','public.studio_allowances','INSERT')
     or has_table_privilege('authenticated','public.studio_allowances','UPDATE')
     or has_function_privilege('authenticated','public.enqueue_studio_generation(uuid,text,uuid,jsonb,text,uuid)','EXECUTE')
     or has_function_privilege('anon','public.claim_studio_generation(uuid,uuid,uuid)','EXECUTE') then
    raise exception 'Studio server-only grants are open';
  end if;
  perform set_config('role','service_role',true);
  insert into public.studio_allowances(user_id) values(other_u);
  select * into job from public.enqueue_studio_generation(u,'',null,'{"mode":"inspiration"}','mock');
  blocked:=false;
  begin
    perform public.enqueue_studio_generation(u,'',null,'{}','mock');
  exception when raise_exception then
    if sqlerrm <> 'studio_trial_exhausted' then raise; end if;
    blocked:=true;
  end;
  if not blocked then raise exception 'Concurrent reservation admitted a second free job'; end if;
  select count(*) into n from public.claim_studio_generation(u,job.id,t1);
  if n<>1 then raise exception 'First claim failed'; end if;
  select count(*) into n from public.claim_studio_generation(u,job.id,t2);
  if n<>0 then raise exception 'Live lease admitted a duplicate claim'; end if;
  select count(*) into n from public.claim_studio_generation(other_u,job.id,t2);
  if n<>0 then raise exception 'Claim crossed owner fence'; end if;
  update public.studio_generations set claim_expires_at=now()-interval '1 second' where id=job.id;
  select count(*) into n from public.claim_studio_generation(u,job.id,t2);
  if n<>1 then raise exception 'Expired claim could not recover'; end if;
  update public.studio_generations set status='complete' where id=job.id and claim_token=t1;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'Stale claim could update the job'; end if;
  update public.studio_generations set status='failed',prompt_payload='{"mode":"inspiration","is_retryable_failure":true}' where id=job.id;
  if exists (select 1 from public.studio_allowances where id=job.allowance_id and consumed_at is not null) then
    raise exception 'Provider failure consumed a credit';
  end if;
  select * into retry_job from public.enqueue_studio_generation(u,'',null,'{"mode":"inspiration"}','mock',job.id);
  select * into duplicate from public.enqueue_studio_generation(u,'',null,'{"mode":"inspiration"}','mock',job.id);
  if retry_job.id<>duplicate.id or retry_job.allowance_id<>job.allowance_id then raise exception 'Retry was not idempotent or charged twice'; end if;
  update public.studio_generations set status='failed',prompt_payload='{"is_retryable_failure":false}' where id=retry_job.id;
  if not exists(select 1 from public.studio_allowances where id=job.allowance_id and released_at is not null) then
    raise exception 'Terminal retry did not release the reservation';
  end if;
  select * into job from public.enqueue_studio_generation(u,'',null,'{}','mock');
  update public.studio_generations set status='complete',result_image_path='fixture/result.png' where id=job.id;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
  if not exists(select 1 from public.studio_allowances where user_id=u) then raise exception 'Owner could not export own allowance activity'; end if;
  if exists(select 1 from public.studio_allowances where user_id<>u) then raise exception 'Allowance reads crossed owner boundary'; end if;
  delete from public.studio_generations where id=job.id;
  get diagnostics n=row_count;
  if n<>1 then raise exception 'Owner could not delete a completed estimate'; end if;
  perform set_config('role','service_role',true);
  if not exists(select 1 from public.studio_allowances where id=job.allowance_id and consumed_at is not null and released_at is null) then
    raise exception 'Deleting a successful estimate refunded the free allowance';
  end if;
  blocked:=false;
  begin perform public.enqueue_studio_generation(u,'',null,'{}','mock');
  exception when raise_exception then
    if sqlerrm <> 'studio_trial_exhausted' then raise; end if;
    blocked:=true;
  end;
  if not blocked then raise exception 'Deleted success enabled another free job'; end if;
  perform set_config('role','postgres',true);
  raise notice 'Studio grants, reservations, retries, lease recovery and deletion accounting passed';
end;
$$;
rollback;

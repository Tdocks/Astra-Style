begin;
do $$
declare u uuid:=gen_random_uuid(); k uuid:=gen_random_uuid(); j uuid; r uuid; blocked boolean;
begin
  insert into auth.users(id,email) values(u,u||'@quota.invalid');
  insert into public.subscriptions(user_id,app_store_original_transaction_id,product_id,status,expires_at)
    values(u,u::text,'fixture','active',now()+interval '1 year');
  perform set_config('role','service_role',true);
  update public.studio_quota_config set premium_monthly_limit=1;
  -- Previous-month reservations do not consume this month's allowance.
  insert into public.studio_allowances(user_id,created_at)
    values(u,(date_trunc('month',now() at time zone 'UTC')-interval '1 second') at time zone 'UTC');
  select id into j from public.enqueue_studio_generation_idempotent(
    u,k,repeat('a',64),'',null,'{"mode":"inspiration"}','fixture');
  select id into r from public.enqueue_studio_generation_idempotent(
    u,k,repeat('a',64),'',null,'{"mode":"inspiration"}','fixture');
  if j is null or r<>j then raise exception 'Monthly-limit replay failed'; end if;
  blocked:=false;
  begin perform public.enqueue_studio_generation(u,'',null,'{"mode":"inspiration"}','fixture');
  exception when others then if sqlerrm='studio_monthly_quota_exhausted' then blocked:=true; else raise; end if; end;
  if not blocked then raise exception 'Monthly quota exceeded'; end if;
  update public.studio_generations set status='failed',prompt_payload='{"is_retryable_failure":true}' where id=j;
  select id into r from public.enqueue_studio_generation(u,'',null,'{"mode":"inspiration"}','fixture',j);
  if r is null then raise exception 'Retry rejected at monthly limit'; end if;
  if (select count(*) from public.studio_allowances where user_id=u)<>2 then
    raise exception 'Retry consumed another allowance'; end if;
  update public.studio_allowances set released_at=now() where user_id=u;
  perform public.enqueue_studio_generation(u,'',null,'{"mode":"inspiration"}','fixture');
  perform set_config('role','authenticated',true);
  blocked:=false;
  begin update public.studio_quota_config set premium_monthly_limit=1000;
  exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'Client changed premium quota'; end if;
end;
$$;
rollback;

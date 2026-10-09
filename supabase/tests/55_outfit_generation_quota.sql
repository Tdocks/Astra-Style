-- P7-SUB-04 contract: daily outfit generation, subscription expiry, and the
-- database-enforced guest/free closet caps. Run after the full migration set
-- and the test-only grants against an isolated scratch database.
begin;
do $$
declare
  u uuid := '15000000-0000-0000-0000-000000000001';
  peer uuid := '15000000-0000-0000-0000-000000000002';
  guest uuid := '15000000-0000-0000-0000-000000000003';
  premium uuid := '15000000-0000-0000-0000-000000000004';
  expired uuid := '15000000-0000-0000-0000-000000000005';
  quota_user uuid := '15000000-0000-0000-0000-000000000006';
  retry_user uuid := '15000000-0000-0000-0000-000000000007';
  request_a uuid := '15100000-0000-0000-0000-000000000001';
  request_b uuid := '15100000-0000-0000-0000-000000000002';
  request_c uuid := '15100000-0000-0000-0000-000000000003';
  request_d uuid := '15100000-0000-0000-0000-000000000004';
  reservation_a uuid;
  reservation_c uuid;
  reservation_d uuid;
  studio_job uuid;
  archived_id uuid;
  allowed_value boolean;
  remaining_value integer;
  resets_value timestamptz;
  payload_value jsonb;
  failed boolean;
begin
  insert into auth.users(id,email,is_anonymous) values
    (u,u||'@quota.invalid',false),
    (peer,peer||'@quota.invalid',false),
    (guest,guest||'@quota.invalid',true),
    (premium,premium||'@quota.invalid',false),
    (expired,expired||'@quota.invalid',false),
    (quota_user,quota_user||'@quota.invalid',false),
    (retry_user,retry_user||'@quota.invalid',false);
  insert into public.subscriptions(
    user_id,app_store_original_transaction_id,product_id,status,expires_at
  ) values
    (premium,'quota-premium','com.astrastyle.app.premium.monthly','active',now()+interval '1 day'),
    (expired,'quota-expired','com.astrastyle.app.premium.monthly','active',now()),
    (retry_user,'quota-retry','com.astrastyle.app.premium.monthly','in_billing_retry',now()+interval '1 day');

  -- Exercise the actual service-only RPCs, including UTC day rollover,
  -- reserved capacity, release, commit/replay and owner-bound finishing.
  perform set_config('role','service_role',true);
  update public.outfit_generation_quota_config set free_daily_limit=1 where singleton;

  -- Studio's lifetime trial remains available during billing retry, but the
  -- retry state does not unlock Premium or bypass the one-time trial limit.
  select id into studio_job from public.enqueue_studio_generation(
    retry_user,'',null,'{"mode":"inspiration"}','fixture'
  );
  if studio_job is null then raise exception 'billing-retry owner lost the Studio trial'; end if;
  failed := false;
  begin
    perform public.enqueue_studio_generation(retry_user,'',null,'{"mode":"inspiration"}','fixture');
  exception when others then
    if sqlerrm = 'studio_trial_exhausted' then failed := true; else raise; end if;
  end;
  if not failed then raise exception 'billing-retry status incorrectly bypassed the Studio trial limit'; end if;

  select allowed,remaining,resets_at,reservation_id
    into allowed_value,remaining_value,resets_value,reservation_a
    from public.reserve_outfit_generation(quota_user,request_a,repeat('a',64),'2026-10-09T23:59:59Z');
  if not allowed_value or remaining_value<>0 or resets_value<>'2026-10-10T00:00:00Z' then
    raise exception 'first reservation or UTC reset is incorrect';
  end if;
  select allowed,remaining into allowed_value,remaining_value
    from public.reserve_outfit_generation(quota_user,request_b,repeat('b',64),'2026-10-09T23:59:59Z');
  if allowed_value or remaining_value<>0 then raise exception 'active reservation did not hold the final slot'; end if;

  perform public.finish_outfit_generation(quota_user,reservation_a,false,null,'2026-10-09T23:59:59Z');
  select allowed,reservation_id into allowed_value,reservation_c
    from public.reserve_outfit_generation(quota_user,request_c,repeat('c',64),'2026-10-09T23:59:59Z');
  if not allowed_value then raise exception 'failed work did not release quota'; end if;
  begin
    perform public.finish_outfit_generation(quota_user,reservation_c,true,'[]','2026-10-09T23:59:59Z');
    raise exception 'empty result was committed';
  exception when raise_exception then
    if sqlerrm not like '%quota_result_invalid%' then raise; end if;
  end;
  perform public.finish_outfit_generation(
    quota_user,reservation_c,true,'[{"id":"fixture-recommendation"}]','2026-10-09T23:59:59Z'
  );
  select allowed,replay_payload into allowed_value,payload_value
    from public.reserve_outfit_generation(quota_user,request_c,repeat('c',64),'2026-10-09T23:59:59Z');
  if not allowed_value or payload_value is distinct from '[{"id":"fixture-recommendation"}]'::jsonb then
    raise exception 'committed request replay did not return its stored result';
  end if;
  if (select successful_count from public.outfit_generation_daily_usage
      where user_id=quota_user and quota_date='2026-10-09')<>1 then
    raise exception 'only successful non-empty output should count';
  end if;
  begin
    perform public.reserve_outfit_generation(quota_user,request_c,repeat('d',64),'2026-10-09T23:59:59Z');
    raise exception 'same request ID with a changed body was accepted';
  exception when raise_exception then
    if sqlerrm not like '%quota_request_id_reused%' then raise; end if;
  end;
  begin
    perform public.finish_outfit_generation(peer,reservation_c,false,null,'2026-10-09T23:59:59Z');
    raise exception 'peer finished another owner reservation';
  exception when raise_exception then
    if sqlerrm not like '%quota_reservation_not_found%' then raise; end if;
  end;
  select allowed,resets_at,reservation_id into allowed_value,resets_value,reservation_d
    from public.reserve_outfit_generation(quota_user,request_d,repeat('e',64),'2026-10-10T00:00:00Z');
  if not allowed_value or resets_value<>'2026-10-11T00:00:00Z' then
    raise exception 'next UTC day did not receive its independent allowance';
  end if;
  begin
    perform public.finish_outfit_generation(quota_user,reservation_d,true,'[{"id":"late"}]','2026-10-10T00:05:01Z');
    raise exception 'expired reservation committed';
  exception when raise_exception then
    if sqlerrm not like '%quota_reservation_expired%' then raise; end if;
  end;
  select allowed into allowed_value
    from public.reserve_outfit_generation(quota_user,request_d,repeat('e',64),'2026-10-10T00:05:02Z');
  if not allowed_value then raise exception 'expired reservation did not release its slot'; end if;

  -- Seed owner fixtures through the trusted server role. The actual user calls
  -- below use the authenticated role and signed JWT claim shape.
  perform set_config('role',session_user::text,true);
  insert into public.closet_items(user_id,category)
    select u,'top' from generate_series(1,30);
  insert into public.closet_items(user_id,category)
    values(u,'top') returning id into archived_id;
  update public.closet_items set archived_at=now() where id=archived_id;
  insert into public.closet_items(user_id,category)
    select guest,'top' from generate_series(1,10);
  insert into public.closet_items(user_id,category)
    select premium,'top' from generate_series(1,30);
  insert into public.closet_items(user_id,category)
    select expired,'top' from generate_series(1,30);
  insert into public.closet_items(user_id,category)
    select peer,'top' from generate_series(1,1);

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated','is_anonymous',false)::text,true);
  failed := false;
  begin
    insert into public.closet_items(user_id,category) values(u,'top');
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'closet_item_limit_reached' or sqlstate <> 'PT409'
       or sqlerrm = '' then raise; end if;
    failed := true;
  end;
  if not failed then raise exception '31st free closet insert was not blocked'; end if;

  failed := false;
  begin
    perform public.restore_closet_item(archived_id);
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'closet_item_limit_reached' then raise; end if;
    failed := true;
  end;
  if not failed then raise exception 'archived restore bypassed the active-item cap'; end if;
  update public.closet_items set name='Existing edits still allowed'
    where id=(select id from public.closet_items where user_id=u and archived_at is null limit 1);
  if not found then raise exception 'an existing over-cap owner item could not be edited'; end if;

  failed := false;
  begin
    insert into public.closet_items(user_id,category) values(peer,'top');
  exception when insufficient_privilege then
    if sqlerrm <> 'closet_owner_mismatch' then raise; end if;
    failed := true;
  end;
  if not failed then raise exception 'peer-owner insert did not fail before the cap read'; end if;

  perform set_config('request.jwt.claims',json_build_object('sub',guest,'role','authenticated','is_anonymous',true)::text,true);
  failed := false;
  begin
    insert into public.closet_items(user_id,category) values(guest,'top');
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'closet_item_limit_reached' then raise; end if;
    failed := true;
  end;
  if not failed then raise exception '11th anonymous closet insert was not blocked'; end if;

  perform set_config('request.jwt.claims',json_build_object('sub',premium,'role','authenticated','is_anonymous',false)::text,true);
  insert into public.closet_items(user_id,category) values(premium,'top');
  if (select count(*) from public.closet_items where user_id=premium and archived_at is null)<>31 then
    raise exception 'entitled Premium owner was incorrectly capped';
  end if;

  perform set_config('request.jwt.claims',json_build_object('sub',expired,'role','authenticated','is_anonymous',false)::text,true);
  failed := false;
  begin
    insert into public.closet_items(user_id,category) values(expired,'top');
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'closet_item_limit_reached' then raise; end if;
    failed := true;
  end;
  if not failed then raise exception 'expired subscription did not revert to the free closet cap'; end if;

  -- Linking the same anonymous ID changes the signed claim; the former guest
  -- now has the regular free-tier allowance rather than remaining stuck at 10.
  perform set_config('request.jwt.claims',json_build_object('sub',guest,'role','authenticated','is_anonymous',false)::text,true);
  insert into public.closet_items(user_id,category) values(guest,'top');

  perform set_config('request.jwt.claims',json_build_object('sub',quota_user,'role','authenticated')::text,true);
  if (select count(*) from public.outfit_generation_daily_usage) <> 0
     or (select count(*) from public.outfit_generation_reservations) <> 0 then
    raise exception 'authenticated caller can read another owner quota state';
  end if;
  reset role;
  if not (select relrowsecurity from pg_class where oid='public.outfit_generation_daily_usage'::regclass)
     or not (select relrowsecurity from pg_class where oid='public.outfit_generation_reservations'::regclass)
     or exists (select 1 from pg_policies where schemaname='public'
       and tablename in ('outfit_generation_daily_usage','outfit_generation_reservations'))
     or has_function_privilege('authenticated','public.reserve_outfit_generation(uuid,uuid,text,timestamp with time zone)','EXECUTE')
     or not has_function_privilege('service_role','public.reserve_outfit_generation(uuid,uuid,text,timestamp with time zone)','EXECUTE') then
    raise exception 'quota state or RPC is exposed to a client role';
  end if;
end;
$$;
rollback;

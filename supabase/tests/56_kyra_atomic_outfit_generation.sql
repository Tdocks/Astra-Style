-- Kyra create_outfit: atomic outfit persistence, daily quota commit, and
-- exactly-once replay. The function remains service-role only.
begin;
-- The shared test grants intentionally open tables to exercise RLS. Restore
-- these service-only ACLs before checking the production privilege boundary.
revoke all on public.kyra_outfit_generation_operations from anon, authenticated;
revoke all on public.kyra_conversation_daily_usage from anon, authenticated;
revoke all on public.kyra_thread_creation_operations from anon, authenticated;
revoke insert on public.kyra_threads from anon, authenticated;
do $$
declare
  owner_id uuid := '16000000-0000-4000-8000-000000000001';
  peer_id uuid := '16000000-0000-4000-8000-000000000002';
  premium_id uuid := '16000000-0000-4000-8000-000000000003';
  top_id uuid := '16100000-0000-4000-8000-000000000001';
  bottom_id uuid := '16100000-0000-4000-8000-000000000002';
  shoes_id uuid := '16100000-0000-4000-8000-000000000003';
  peer_item_id uuid := '16100000-0000-4000-8000-000000000004';
  premium_top_id uuid := '16100000-0000-4000-8000-000000000005';
  premium_bottom_id uuid := '16100000-0000-4000-8000-000000000006';
  premium_shoes_id uuid := '16100000-0000-4000-8000-000000000007';
  free_request_id uuid := '16200000-0000-4000-8000-000000000001';
  invalid_request_id uuid := '16200000-0000-4000-8000-000000000002';
  expired_request_id uuid := '16200000-0000-4000-8000-000000000003';
  premium_request_id uuid := '16200000-0000-4000-8000-000000000004';
  peer_thread_request_id uuid := '16300000-0000-4000-8000-000000000001';
  peer_retry_request_id uuid := '16300000-0000-4000-8000-000000000002';
  premium_thread_request_id uuid := '16300000-0000-4000-8000-000000000003';
  premium_thread_request_id_2 uuid := '16300000-0000-4000-8000-000000000004';
  free_reservation uuid;
  invalid_reservation uuid;
  expired_reservation uuid;
  result_row jsonb;
  replay_row jsonb;
  blocked boolean;
  before_count integer;
  expected_outfit_id uuid;
  third_thread uuid;
  fourth_thread uuid;
  premium_thread uuid;
  replay_thread uuid;
  replayed_status boolean;
  thread_deleted_status boolean;
  outfit_input jsonb;
  result_input jsonb;
begin
  insert into auth.users(id,email,is_anonymous) values
    (owner_id,owner_id||'@kyra-quota.invalid',false),
    (peer_id,peer_id||'@kyra-quota.invalid',false),
    (premium_id,premium_id||'@kyra-quota.invalid',false);
  update public.profiles set wardrobe_graph='menswear_3_role'
    where id in (owner_id,peer_id,premium_id);
  insert into public.subscriptions(
    user_id,app_store_original_transaction_id,product_id,status,expires_at,environment
  ) values (
    premium_id,'kyra-atomic-premium','com.astrastyle.app.premium.monthly','active',now()+interval '1 day','sandbox'
  );
  insert into public.closet_items(id,user_id,category) values
    (top_id,owner_id,'top'),(bottom_id,owner_id,'bottom'),(shoes_id,owner_id,'shoes'),
    (peer_item_id,peer_id,'top'),
    (premium_top_id,premium_id,'top'),(premium_bottom_id,premium_id,'bottom'),
    (premium_shoes_id,premium_id,'shoes');

  select reservation_id into free_reservation
    from public.reserve_outfit_generation(owner_id,free_request_id,repeat('a',64),now());
  if free_reservation is null then raise exception 'free generation reservation was not created'; end if;
  outfit_input := jsonb_build_object(
    'name','Kyra atomic fixture',
    'description','A persisted outfit test',
    'occasion_tags',jsonb_build_array('daily'),
    'compatibility_score',75,
    'allow_product_candidates',false,
    'locked_item_ids',jsonb_build_array(top_id),
    'items',jsonb_build_array(
      jsonb_build_object('closet_item_id',top_id,'role','top','sort_order',0),
      jsonb_build_object('closet_item_id',bottom_id,'role','bottom','sort_order',1),
      jsonb_build_object('closet_item_id',shoes_id,'role','shoes','sort_order',2)
    )
  );
  result_input := jsonb_build_object(
    'compatibility_score',75,'reason','A verified owned outfit.','item_ids',jsonb_build_array(top_id,bottom_id,shoes_id)
  );
  result_row := public.commit_kyra_outfit_generation(
    owner_id,free_request_id,repeat('a',64),free_reservation,outfit_input,result_input,now()
  );
  expected_outfit_id := (result_row->>'outfit_id')::uuid;
  if expected_outfit_id is null
     or (select count(*) from public.outfit_items where outfit_id=expected_outfit_id and user_id=owner_id)<>3
     or (select successful_count from public.outfit_generation_daily_usage where user_id=owner_id and quota_date=(now() at time zone 'UTC')::date)<>1
     or (select state from public.outfit_generation_reservations where id=free_reservation)<>'committed' then
    raise exception 'atomic free outfit did not persist and commit one quota unit';
  end if;
  replay_row := public.commit_kyra_outfit_generation(
    owner_id,free_request_id,repeat('a',64),free_reservation,outfit_input,result_input,now()
  );
  if replay_row <> result_row
     or (select count(*) from public.outfits where user_id=owner_id)<>1
     or (select successful_count from public.outfit_generation_daily_usage where user_id=owner_id and quota_date=(now() at time zone 'UTC')::date)<>1 then
    raise exception 'free replay duplicated the outfit or quota debit';
  end if;

  blocked := false;
  begin
    perform public.commit_kyra_outfit_generation(
      owner_id,free_request_id,repeat('b',64),free_reservation,outfit_input,result_input,now()
    );
  exception when others then
    if sqlerrm <> 'kyra_outfit_request_id_reused' then raise; end if;
    blocked := true;
  end;
  if not blocked then raise exception 'same request ID with changed fingerprint was accepted'; end if;

  select reservation_id into invalid_reservation
    from public.reserve_outfit_generation(owner_id,invalid_request_id,repeat('c',64),now());
  before_count := (select count(*) from public.outfits where user_id=owner_id);
  blocked := false;
  begin
    perform public.commit_kyra_outfit_generation(
      owner_id,invalid_request_id,repeat('c',64),invalid_reservation,
      jsonb_set(outfit_input,'{items,2,closet_item_id}',to_jsonb(peer_item_id::text)),result_input,now()
    );
  exception when others then
    if sqlerrm <> 'kyra_outfit_item_unavailable' then raise; end if;
    blocked := true;
  end;
  if not blocked
     or (select count(*) from public.outfits where user_id=owner_id)<>before_count
     or (select state from public.outfit_generation_reservations where id=invalid_reservation)<>'reserved' then
    raise exception 'invalid peer item wrote outfit rows or committed quota';
  end if;
  perform public.finish_outfit_generation(owner_id,invalid_reservation,false,null,now());

  select reservation_id into expired_reservation
    from public.reserve_outfit_generation(owner_id,expired_request_id,repeat('d',64),now());
  update public.outfit_generation_reservations set expires_at=now()-interval '1 second'
    where id=expired_reservation;
  blocked := false;
  begin
    perform public.commit_kyra_outfit_generation(
      owner_id,expired_request_id,repeat('d',64),expired_reservation,outfit_input,result_input,now()
    );
  exception when others then
    if sqlerrm <> 'outfit_generation_reservation_unavailable' then raise; end if;
    blocked := true;
  end;
  if not blocked then raise exception 'expired quota reservation was accepted'; end if;

  -- A premium operation is atomic and idempotent without consuming the free ledger.
  outfit_input := jsonb_set(outfit_input,'{items}',jsonb_build_array(
    jsonb_build_object('closet_item_id',premium_top_id,'role','top','sort_order',0),
    jsonb_build_object('closet_item_id',premium_bottom_id,'role','bottom','sort_order',1),
    jsonb_build_object('closet_item_id',premium_shoes_id,'role','shoes','sort_order',2)
  ));
  result_input := jsonb_build_object(
    'compatibility_score',75,'reason','A premium owned outfit.',
    'item_ids',jsonb_build_array(premium_top_id,premium_bottom_id,premium_shoes_id)
  );
  outfit_input := jsonb_set(outfit_input,'{locked_item_ids}','[]'::jsonb);
  result_row := public.commit_kyra_outfit_generation(
    premium_id,premium_request_id,repeat('e',64),null,outfit_input,result_input,now()
  );
  replay_row := public.commit_kyra_outfit_generation(
    premium_id,premium_request_id,repeat('e',64),null,outfit_input,result_input,now()
  );
  if result_row->>'outfit_id' is null or replay_row<>result_row
     or exists (select 1 from public.outfit_generation_daily_usage where user_id=premium_id) then
    raise exception 'premium atomic replay failed or consumed the free ledger';
  end if;

  -- The last free conversation slot is admitted once; a fourth is denied.
  perform set_config('role','service_role',true);
  insert into public.kyra_threads(user_id,title) values
    (peer_id,'legacy conversation one'),(peer_id,'legacy conversation two');
  select thread_id into third_thread from public.create_kyra_thread_with_daily_limit(
    peer_id,'third conversation',3,now(),peer_thread_request_id,repeat('f',64)
  );
  -- The service fixture only has the production INSERT path; use the trusted
  -- scratch database role to simulate the owner's ordinary thread deletion.
  perform set_config('role',session_user::text,true);
  delete from public.kyra_threads where id=third_thread;
  perform set_config('role','service_role',true);
  select thread_id,allowed,replayed,thread_deleted
    into replay_thread,blocked,replayed_status,thread_deleted_status
    from public.create_kyra_thread_with_daily_limit(
      peer_id,'third conversation',3,now(),peer_thread_request_id,repeat('f',64)
    );
  if replay_thread is not null or blocked or not replayed_status or not thread_deleted_status then
    raise exception 'a deleted thread retry was recreated or charged again';
  end if;
  blocked := false;
  begin
    perform public.create_kyra_thread_with_daily_limit(
      peer_id,'changed content',3,now(),peer_thread_request_id,repeat('a',64)
    );
  exception when others then
    if sqlerrm <> 'kyra_thread_request_id_reused' then raise; end if;
    blocked := true;
  end;
  if not blocked then raise exception 'same thread request ID accepted changed input'; end if;
  select thread_id,allowed into fourth_thread,blocked
    from public.create_kyra_thread_with_daily_limit(
      peer_id,'fourth conversation',3,now(),peer_retry_request_id,repeat('b',64)
    );
  if third_thread is null or fourth_thread is not null or blocked
     or (select count(*) from public.kyra_threads where user_id=peer_id)<>2
     or (select successful_count from public.kyra_conversation_daily_usage
       where user_id=peer_id and quota_date=(now() at time zone 'UTC')::date)<>3 then
    raise exception 'free daily conversation cap admitted a deleted conversation twice';
  end if;
  select thread_id into premium_thread from public.create_kyra_thread_with_daily_limit(
    premium_id,'premium conversation',1,now(),premium_thread_request_id,repeat('c',64)
  );
  select allowed into blocked from public.create_kyra_thread_with_daily_limit(
    premium_id,'premium conversation two',1,now(),premium_thread_request_id_2,repeat('d',64)
  );
  if premium_thread is null or not blocked then
    raise exception 'Premium conversations were incorrectly capped';
  end if;
  if (select successful_count from public.kyra_conversation_daily_usage
      where user_id=premium_id and quota_date=(now() at time zone 'UTC')::date)<>0 then
    raise exception 'Premium conversation starts were charged to the free ledger';
  end if;

  -- Caller roles cannot invoke the service-only function or read operation rows.
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',json_build_object('sub',peer_id,'role','authenticated')::text,true);
  blocked := false;
  begin
    perform public.commit_kyra_outfit_generation(
      peer_id,free_request_id,repeat('a',64),null,outfit_input,result_input,now()
    );
  exception when insufficient_privilege then blocked := true;
  end;
  if not blocked then raise exception 'authenticated caller executed the service-only RPC'; end if;
  blocked := false;
  begin
    perform count(*) from public.kyra_outfit_generation_operations;
  exception when insufficient_privilege then blocked := true;
  end;
  if not blocked then raise exception 'authenticated caller read service-only operation state'; end if;
  blocked := false;
  begin
    insert into public.kyra_threads(user_id,title) values(peer_id,'direct bypass');
  exception when insufficient_privilege then blocked := true;
  end;
  if not blocked then raise exception 'authenticated caller bypassed the daily conversation gate'; end if;
  reset role;

  if not (select relrowsecurity from pg_class where oid='public.kyra_outfit_generation_operations'::regclass)
     or not (select relrowsecurity from pg_class where oid='public.kyra_thread_creation_operations'::regclass)
     or has_function_privilege('anon','public.commit_kyra_outfit_generation(uuid,uuid,text,uuid,jsonb,jsonb,timestamp with time zone)','EXECUTE')
     or has_function_privilege('authenticated','public.commit_kyra_outfit_generation(uuid,uuid,text,uuid,jsonb,jsonb,timestamp with time zone)','EXECUTE')
     or not has_function_privilege('service_role','public.commit_kyra_outfit_generation(uuid,uuid,text,uuid,jsonb,jsonb,timestamp with time zone)','EXECUTE')
     or has_function_privilege('anon','public.create_kyra_thread_with_daily_limit(uuid,text,integer,timestamp with time zone,uuid,text)','EXECUTE')
     or has_function_privilege('authenticated','public.create_kyra_thread_with_daily_limit(uuid,text,integer,timestamp with time zone,uuid,text)','EXECUTE')
     or not has_function_privilege('service_role','public.create_kyra_thread_with_daily_limit(uuid,text,integer,timestamp with time zone,uuid,text)','EXECUTE')
     or has_table_privilege('authenticated','public.kyra_threads','INSERT')
     or has_table_privilege('authenticated','public.kyra_conversation_daily_usage','SELECT')
     or has_table_privilege('authenticated','public.kyra_thread_creation_operations','SELECT')
     or not has_table_privilege('service_role','public.kyra_thread_creation_operations','INSERT')
     or not has_table_privilege('service_role','public.kyra_threads','INSERT')
     or not (select relrowsecurity from pg_class where oid='public.kyra_conversation_daily_usage'::regclass) then
    raise exception 'atomic operation storage or function privileges are unsafe';
  end if;
end;
$$;
rollback;

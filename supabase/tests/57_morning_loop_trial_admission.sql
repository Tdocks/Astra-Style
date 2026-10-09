-- Atomic, owner-scoped lifetime admission for Daily Brief and product verdicts.
begin;

-- Test-only broad table grants run before this file; re-establish production
-- write boundaries while retaining authenticated owner DELETE for account UI.
revoke insert, update on public.daily_briefs from anon, authenticated;
revoke insert, update on public.user_product_evaluations from anon, authenticated;
revoke all on public.morning_loop_trial_usage, public.morning_loop_trial_operations from anon, authenticated;

do $$
declare
  owner_id uuid := '57000000-0000-4000-8000-000000000001';
  peer_id uuid := '57000000-0000-4000-8000-000000000002';
  premium_id uuid := '57000000-0000-4000-8000-000000000003';
  expired_id uuid := '57000000-0000-4000-8000-000000000004';
  candidate_id uuid := '57100000-0000-4000-8000-000000000001';
  closet_id uuid := '57200000-0000-4000-8000-000000000001';
  result_row jsonb;
  replay_row jsonb;
  blocked_row jsonb;
  idx integer;
  did_raise boolean;
begin
  if has_table_privilege('authenticated','public.daily_briefs','INSERT') or
     has_table_privilege('authenticated','public.daily_briefs','UPDATE') or
     has_table_privilege('authenticated','public.user_product_evaluations','INSERT') or
     has_table_privilege('authenticated','public.user_product_evaluations','UPDATE') then
    raise exception 'authenticated can bypass atomic morning-loop persistence';
  end if;
  if not has_table_privilege('authenticated','public.daily_briefs','DELETE') or
     not has_table_privilege('authenticated','public.user_product_evaluations','DELETE') then
    raise exception 'owner deletion was unintentionally removed';
  end if;
  if has_function_privilege('anon',
       'public.finalize_daily_brief(uuid,text,text,date,boolean,jsonb,jsonb,jsonb,jsonb,jsonb)','EXECUTE') or
     has_function_privilege('authenticated',
       'public.persist_product_evaluation(uuid,text,text,jsonb,jsonb)','EXECUTE') or
     has_function_privilege('authenticated',
       'public.get_morning_loop_trial_operation(uuid,text,text,text)','EXECUTE') then
    raise exception 'client role can invoke service-only morning-loop RPC';
  end if;
  if not has_function_privilege('service_role',
       'public.finalize_daily_brief(uuid,text,text,date,boolean,jsonb,jsonb,jsonb,jsonb,jsonb)','EXECUTE') or
     not has_function_privilege('service_role',
       'public.persist_product_evaluation(uuid,text,text,jsonb,jsonb)','EXECUTE') then
    raise exception 'service role cannot invoke atomic persistence';
  end if;

  insert into auth.users(id,email,is_anonymous) values
    (owner_id,owner_id||'@morning-trial.invalid',false),
    (peer_id,peer_id||'@morning-trial.invalid',false),
    (premium_id,premium_id||'@morning-trial.invalid',false),
    (expired_id,expired_id||'@morning-trial.invalid',false);
  insert into public.closet_items(id,user_id,category)
    values (closet_id,owner_id,'top');
  insert into public.product_candidates(id,canonical_url,name,category)
    values (candidate_id,'https://morning-trial.invalid/item','Trial shirt','top');
  insert into public.subscriptions(user_id,app_store_original_transaction_id,product_id,status,expires_at,environment)
    values
      (premium_id,'morning-trial-premium','premium','active',now()+interval '2 days','sandbox'),
      (expired_id,'morning-trial-expired','premium','active',now()-interval '1 minute','sandbox');

  -- Historical usage is backfilled, while newly persisted empty briefs are
  -- valid successes under the pre-existing Daily Brief behavior.
  for idx in 1..3 loop
    result_row := public.finalize_daily_brief(
      owner_id,'daily-'||idx,repeat('a',64),('2026-10-'||lpad((idx+1)::text,2,'0'))::date,
      false,'{}'::jsonb,'{"event_count":0}'::jsonb,null,null,'[]'::jsonb
    );
    if result_row->>'status' <> 'success' then raise exception 'daily brief % was not admitted',idx; end if;
  end loop;
  if (select daily_brief_successes from public.morning_loop_trial_usage where user_id=owner_id) <> 3 then
    raise exception 'three persisted briefs did not produce exactly three lifetime uses';
  end if;

  -- Concurrent same-day cold requests serialize into one saved row/outfit set.
  result_row := public.finalize_daily_brief(
    owner_id,'daily-same-date',repeat('b',64),'2026-10-02',false,
    '{}'::jsonb,'{"event_count":0}'::jsonb,null,null,'[]'::jsonb
  );
  if result_row->>'status' <> 'existing' or
     (select daily_brief_successes from public.morning_loop_trial_usage where user_id=owner_id) <> 3 then
    raise exception 'same-day non-regenerate request changed usage';
  end if;

  -- A measured-context refresh of a still-existing day remains allowed at
  -- the cap, but a missing row cannot use the exemption to create a fourth.
  result_row := public.finalize_daily_brief(
    owner_id,'daily-refresh',repeat('c',64),'2026-10-02',false,
    '{"temperature_high":70}'::jsonb,'{"event_count":0}'::jsonb,
    '{"temperature_high":70}'::jsonb,null,'[]'::jsonb
  );
  if result_row->>'status' <> 'success' or
     (select daily_brief_successes from public.morning_loop_trial_usage where user_id=owner_id) <> 3 then
    raise exception 'existing-day measured refresh consumed quota or failed';
  end if;
  result_row := public.finalize_daily_brief(
    owner_id,'daily-fourth',repeat('d',64),'2026-10-05',false,
    '{}'::jsonb,'{"event_count":0}'::jsonb,'{"temperature_high":70}'::jsonb,null,'[]'::jsonb
  );
  if result_row->>'status' <> 'limit' then raise exception 'cold fourth date used refresh exemption'; end if;
  result_row := public.finalize_daily_brief(
    owner_id,'daily-regen',repeat('e',64),'2026-10-02',true,
    '{}'::jsonb,'{"event_count":0}'::jsonb,null,null,'[]'::jsonb
  );
  if result_row->>'status' <> 'limit' then raise exception 'explicit regeneration bypassed full lifetime cap'; end if;
  delete from public.daily_briefs where user_id=owner_id and brief_date='2026-10-03';
  did_raise := false;
  begin
    perform public.get_morning_loop_trial_operation(owner_id,'daily_brief','daily-2',repeat('a',64));
  exception when others then
    if sqlerrm <> 'morning_loop_result_deleted' then raise; end if;
    did_raise := true;
  end;
  if not did_raise then raise exception 'deleted brief was returned from the replay ledger'; end if;
  result_row := public.finalize_daily_brief(
    owner_id,'daily-delete-no-refund',repeat('f',64),'2026-10-06',false,
    '{}'::jsonb,'{"event_count":0}'::jsonb,null,null,'[]'::jsonb
  );
  if result_row->>'status' <> 'limit' then raise exception 'deleting brief refunded lifetime use'; end if;

  -- An owned item is validated inside the transaction. Any later failure
  -- rolls the outfit and its items back with the brief and ledger.
  did_raise := false;
  begin
    perform public.finalize_daily_brief(
      peer_id,'peer-item-denied',repeat('1',64),'2026-10-02',false,
      '{}'::jsonb,'{"event_count":0}'::jsonb,null,null,
      jsonb_build_array(jsonb_build_object(
        'reason','invalid peer reference','compatibility_score',50,
        'items',jsonb_build_array(jsonb_build_object('closet_item_id',closet_id,'role','top','sort_order',0))
      ))
    );
  exception when others then
    if sqlerrm <> 'daily_brief_item_not_owned' then raise; end if;
    did_raise := true;
  end;
  if not did_raise or exists(select 1 from public.daily_briefs where user_id=peer_id and brief_date='2026-10-02') or
     exists(select 1 from public.outfits where user_id=peer_id) or
     coalesce((select daily_brief_successes from public.morning_loop_trial_usage where user_id=peer_id),0) <> 0 then
    raise exception 'peer closet reference was not rejected atomically';
  end if;

  -- First evaluation persists once. Exact request replay returns identical
  -- payload; different request after deletion remains over its lifetime cap.
  result_row := public.persist_product_evaluation(
    owner_id,'eval-1',repeat('1',64),
    jsonb_build_object('user_id',owner_id,'product_candidate_id',candidate_id,
      'compatibility_score',70,'redundancy_score',10,'outfits_unlocked',3,
      'expected_cost_per_wear',null,'verdict','consider','reasoning','synthetic'),
    jsonb_build_object('user_id',owner_id,'product_candidate_id',candidate_id,'verdict','consider')
  );
  if result_row->>'status' <> 'success' then raise exception 'first product evaluation was not admitted'; end if;
  replay_row := public.get_morning_loop_trial_operation(owner_id,'product_evaluation','eval-1',repeat('1',64));
  if replay_row->'result' <> result_row->'result' or
     (select product_evaluation_successes from public.morning_loop_trial_usage where user_id=owner_id) <> 1 or
     (select count(*) from public.user_product_evaluations where user_id=owner_id) <> 1 then
    raise exception 'product replay changed DTO, row count, or usage';
  end if;
  did_raise := false;
  begin
    perform public.get_morning_loop_trial_operation(owner_id,'product_evaluation','eval-1',repeat('2',64));
  exception when others then
    if sqlerrm <> 'morning_loop_request_id_reused' then raise; end if;
    did_raise := true;
  end;
  if not did_raise then raise exception 'request ID reuse with changed intent was accepted'; end if;
  delete from public.user_product_evaluations where user_id=owner_id;
  did_raise := false;
  begin
    perform public.get_morning_loop_trial_operation(owner_id,'product_evaluation','eval-1',repeat('1',64));
  exception when others then
    if sqlerrm <> 'morning_loop_result_deleted' then raise; end if;
    did_raise := true;
  end;
  if not did_raise then raise exception 'deleted evaluation was returned from the replay ledger'; end if;
  blocked_row := public.persist_product_evaluation(
    owner_id,'eval-after-delete',repeat('3',64),
    jsonb_build_object('user_id',owner_id,'product_candidate_id',candidate_id,
      'compatibility_score',71,'redundancy_score',11,'outfits_unlocked',4,
      'expected_cost_per_wear',null,'verdict','consider','reasoning','retry'),
    jsonb_build_object('user_id',owner_id,'product_candidate_id',candidate_id,'verdict','consider')
  );
  if blocked_row->>'status' <> 'limit' then raise exception 'deleting evaluation refunded lifetime use'; end if;

  -- Commit-time subscription reads allow a valid premium owner and reject an
  -- expired entitlement without accepting a stale edge-side premium flag.
  result_row := public.finalize_daily_brief(
    premium_id,'premium-brief',repeat('4',64),'2026-10-20',false,
    '{}'::jsonb,'{"event_count":0}'::jsonb,null,null,'[]'::jsonb
  );
  if result_row->>'status' <> 'success' then raise exception 'active premium generation was denied'; end if;
  result_row := public.finalize_daily_brief(
    expired_id,'expired-brief',repeat('5',64),'2026-10-20',false,
    '{}'::jsonb,'{"event_count":0}'::jsonb,null,null,'[]'::jsonb
  );
  if result_row->>'status' <> 'success' then raise exception 'first expired-user trial was denied'; end if;
  for idx in 2..5 loop
    result_row := public.finalize_daily_brief(
      expired_id,'expired-after-first-'||idx,repeat('6',64),('2026-10-'||lpad((20+idx)::text,2,'0'))::date,
      false,'{}'::jsonb,'{"event_count":0}'::jsonb,null,null,'[]'::jsonb
    );
  end loop;
  if result_row->>'status' <> 'limit' then
    raise exception 'expired premium expected limit, got status %, usage %, expiry %',
      result_row->>'status',
      (select daily_brief_successes from public.morning_loop_trial_usage where user_id=expired_id),
      (select expires_at from public.subscriptions where user_id=expired_id);
  end if;
end;
$$;
rollback;

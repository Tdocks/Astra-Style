-- Lifetime trial accounting for Daily Brief and paste-evaluations.
-- Successful usage is monotonic for the account lifetime: deleting a brief or
-- evaluation row never refunds a trial. Auth deletion still cascades the
-- account's private ledger and idempotency payloads.

create table public.morning_loop_trial_usage (
  user_id uuid primary key references auth.users(id) on delete cascade,
  daily_brief_successes integer not null default 0 check (daily_brief_successes >= 0),
  product_evaluation_successes integer not null default 0 check (product_evaluation_successes >= 0),
  updated_at timestamptz not null default now()
);
alter table public.morning_loop_trial_usage enable row level security;
revoke all on public.morning_loop_trial_usage from public, anon, authenticated;
grant select, insert, update, delete on public.morning_loop_trial_usage to service_role;

insert into public.morning_loop_trial_usage(user_id, daily_brief_successes, product_evaluation_successes)
select u.id,
  coalesce(b.successes, 0),
  coalesce(e.successes, 0)
from auth.users u
left join (
  select user_id, count(*)::integer as successes
  from public.daily_briefs group by user_id
) b on b.user_id = u.id
left join (
  select user_id, count(*)::integer as successes
  from public.user_product_evaluations group by user_id
) e on e.user_id = u.id
on conflict (user_id) do update set
  daily_brief_successes = greatest(public.morning_loop_trial_usage.daily_brief_successes, excluded.daily_brief_successes),
  product_evaluation_successes = greatest(public.morning_loop_trial_usage.product_evaluation_successes, excluded.product_evaluation_successes);

create table public.morning_loop_trial_operations (
  user_id uuid not null references auth.users(id) on delete cascade,
  feature text not null check (feature in ('daily_brief', 'product_evaluation')),
  request_id text not null,
  request_fingerprint text not null,
  source_row_id uuid,
  result_payload jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id, feature, request_id)
);
comment on table public.morning_loop_trial_operations is
  'Private request replay data. Per-result payloads remain until account deletion; deleting a source brief/evaluation prevents replay and never refunds the lifetime ledger.';
alter table public.morning_loop_trial_operations enable row level security;
revoke all on public.morning_loop_trial_operations from public, anon, authenticated;
grant select, insert, update, delete on public.morning_loop_trial_operations to service_role;

-- Data API writes would bypass the server's atomic finalization boundary.
-- Reads and owner-scoped deletion remain available; account deletion uses the
-- service role and cascades the rows.
revoke insert, update on public.daily_briefs from authenticated;
revoke insert, update on public.user_product_evaluations from authenticated;

create function public.finalize_daily_brief(
  p_user_id uuid,
  p_request_id text,
  p_request_fingerprint text,
  p_brief_date date,
  p_regenerate boolean,
  p_weather_snapshot jsonb,
  p_schedule_snapshot jsonb,
  p_requested_weather_snapshot jsonb,
  p_requested_schedule_snapshot jsonb,
  p_drafts jsonb
) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare
  v_existing_op public.morning_loop_trial_operations%rowtype;
  v_existing_brief public.daily_briefs%rowtype;
  v_has_brief boolean;
  v_measured_refresh boolean := false;
  v_used integer;
  v_limit integer := 3;
  v_is_premium boolean;
  v_outfit_id uuid;
  v_outfit_ids uuid[] := array[]::uuid[];
  v_draft jsonb;
  v_item jsonb;
  v_result jsonb;
begin
  if p_user_id is null or p_request_id is null or length(p_request_id) = 0 or
     length(p_request_id) > 128 or p_request_fingerprint is null or length(p_request_fingerprint) <> 64 or
     p_brief_date is null or p_regenerate is null or p_drafts is null or
     jsonb_typeof(p_drafts) <> 'array' then
    raise exception 'invalid_daily_brief_request';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('morning-loop:' || p_user_id::text, 0)
  );

  select * into v_existing_op from public.morning_loop_trial_operations
    where user_id = p_user_id and feature = 'daily_brief' and request_id = p_request_id;
  if found then
    if v_existing_op.request_fingerprint <> p_request_fingerprint then
      raise exception 'morning_loop_request_id_reused';
    end if;
    if v_existing_op.source_row_id is null or not exists (
      select 1 from public.daily_briefs b
      where b.id = v_existing_op.source_row_id and b.user_id = p_user_id
    ) then
      raise exception 'morning_loop_result_deleted';
    end if;
    return v_existing_op.result_payload || jsonb_build_object('status', 'replay');
  end if;

  select * into v_existing_brief from public.daily_briefs
    where user_id = p_user_id and brief_date = p_brief_date for update;
  v_has_brief := found;
  if v_has_brief and not p_regenerate then
    v_measured_refresh := (
      (p_requested_weather_snapshot is not null and
        p_requested_weather_snapshot <> '{}'::jsonb and
        v_existing_brief.weather_snapshot = '{}'::jsonb)
      or
      (p_requested_schedule_snapshot is not null and
        v_existing_brief.schedule_snapshot is distinct from p_requested_schedule_snapshot)
    );
  end if;
  -- Cold concurrent ordinary requests converge under this lock. A context
  -- refresh is recognized from the locked row, not from a stale pre-read.
  if v_has_brief and not p_regenerate and not v_measured_refresh then
    v_result := jsonb_build_object('status', 'existing', 'brief', to_jsonb(v_existing_brief));
    insert into public.morning_loop_trial_operations(user_id, feature, request_id, request_fingerprint, source_row_id, result_payload)
      values (p_user_id, 'daily_brief', p_request_id, p_request_fingerprint, v_existing_brief.id, v_result);
    return v_result;
  end if;

  insert into public.morning_loop_trial_usage(user_id) values (p_user_id) on conflict do nothing;
  select daily_brief_successes into strict v_used from public.morning_loop_trial_usage
    where user_id = p_user_id for update;
  select exists (
    select 1 from public.subscriptions s
    where s.user_id = p_user_id
      and s.status::text in ('trialing', 'active', 'in_grace_period')
      and (s.expires_at is null or s.expires_at > clock_timestamp())
  ) into v_is_premium;
  if not v_is_premium and not (v_has_brief and not p_regenerate and v_measured_refresh) and v_used >= v_limit then
    return jsonb_build_object('status', 'limit', 'limit', v_limit, 'remaining', 0);
  end if;

  for v_draft in select value from jsonb_array_elements(p_drafts) loop
    insert into public.outfits(user_id, name, description, compatibility_score, source)
      values (
        p_user_id,
        'Today''s Outfit',
        v_draft ->> 'reason',
        (v_draft ->> 'compatibility_score')::smallint,
        'ai_generated'
      ) returning id into v_outfit_id;
    v_outfit_ids := array_append(v_outfit_ids, v_outfit_id);

    for v_item in select value from jsonb_array_elements(coalesce(v_draft -> 'items', '[]'::jsonb)) loop
      if not exists (
        select 1 from public.closet_items c
        where c.id = (v_item ->> 'closet_item_id')::uuid
          and c.user_id = p_user_id and c.archived_at is null
      ) then
        raise exception 'daily_brief_item_not_owned';
      end if;
      insert into public.outfit_items(user_id, outfit_id, closet_item_id, role, sort_order, is_required)
        values (
          p_user_id, v_outfit_id, (v_item ->> 'closet_item_id')::uuid,
          (v_item ->> 'role')::public.clothing_category,
          (v_item ->> 'sort_order')::integer, true
        );
    end loop;
  end loop;

  insert into public.daily_briefs as stored_brief(
    user_id, brief_date, primary_outfit_id, alternative_outfit_ids,
    weather_snapshot, schedule_snapshot
  ) values (
    p_user_id, p_brief_date, v_outfit_ids[1],
    coalesce(to_jsonb(v_outfit_ids[2:]), '[]'::jsonb),
    coalesce(p_weather_snapshot, '{}'::jsonb), coalesce(p_schedule_snapshot, '{}'::jsonb)
  )
  on conflict (user_id, brief_date) do update set
    primary_outfit_id = excluded.primary_outfit_id,
    alternative_outfit_ids = excluded.alternative_outfit_ids,
    weather_snapshot = excluded.weather_snapshot,
    schedule_snapshot = excluded.schedule_snapshot,
    updated_at = now()
  returning to_jsonb(stored_brief) into v_result;

  if not v_has_brief then
    update public.morning_loop_trial_usage set
      daily_brief_successes = daily_brief_successes + 1, updated_at = now()
      where user_id = p_user_id;
  end if;
  v_result := jsonb_build_object('status', 'success', 'brief', v_result);
  insert into public.morning_loop_trial_operations(user_id, feature, request_id, request_fingerprint, source_row_id, result_payload)
    values (p_user_id, 'daily_brief', p_request_id, p_request_fingerprint, (v_result->'brief'->>'id')::uuid, v_result);
  return v_result;
end;
$$;

create function public.persist_product_evaluation(
  p_user_id uuid,
  p_request_id text,
  p_request_fingerprint text,
  p_evaluation jsonb,
  p_result_payload jsonb
) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare
  v_existing_op public.morning_loop_trial_operations%rowtype;
  v_used integer;
  v_limit integer := 1;
  v_is_premium boolean;
  v_created_at timestamptz;
  v_source_row_id uuid;
  v_result jsonb;
begin
  if p_user_id is null or p_request_id is null or length(p_request_id) = 0 or
     length(p_request_id) > 128 or p_request_fingerprint is null or length(p_request_fingerprint) <> 64 or
     p_evaluation is null or p_result_payload is null or
     jsonb_typeof(p_evaluation) <> 'object' or jsonb_typeof(p_result_payload) <> 'object' or
     p_evaluation ->> 'user_id' is distinct from p_user_id::text then
    raise exception 'invalid_product_evaluation_request';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('morning-loop:' || p_user_id::text, 0)
  );

  select * into v_existing_op from public.morning_loop_trial_operations
    where user_id = p_user_id and feature = 'product_evaluation' and request_id = p_request_id;
  if found then
    if v_existing_op.request_fingerprint <> p_request_fingerprint then
      raise exception 'morning_loop_request_id_reused';
    end if;
    if v_existing_op.source_row_id is null or not exists (
      select 1 from public.user_product_evaluations e
      where e.id = v_existing_op.source_row_id and e.user_id = p_user_id
    ) then
      raise exception 'morning_loop_result_deleted';
    end if;
    return jsonb_build_object('status', 'replay', 'result', v_existing_op.result_payload);
  end if;

  insert into public.morning_loop_trial_usage(user_id) values (p_user_id) on conflict do nothing;
  select product_evaluation_successes into strict v_used from public.morning_loop_trial_usage
    where user_id = p_user_id for update;
  select exists (
    select 1 from public.subscriptions s
    where s.user_id = p_user_id
      and s.status::text in ('trialing', 'active', 'in_grace_period')
      and (s.expires_at is null or s.expires_at > clock_timestamp())
  ) into v_is_premium;
  if not v_is_premium and v_used >= v_limit then
    return jsonb_build_object('status', 'limit', 'limit', v_limit, 'remaining', 0);
  end if;

  insert into public.user_product_evaluations(
    user_id, product_candidate_id, compatibility_score, redundancy_score,
    outfits_unlocked, expected_cost_per_wear, verdict, reasoning
  ) values (
    p_user_id, (p_evaluation ->> 'product_candidate_id')::uuid,
    (p_evaluation ->> 'compatibility_score')::smallint,
    (p_evaluation ->> 'redundancy_score')::smallint,
    (p_evaluation ->> 'outfits_unlocked')::integer,
    nullif(p_evaluation ->> 'expected_cost_per_wear', '')::numeric,
    (p_evaluation ->> 'verdict')::public.kyra_verdict,
    p_evaluation ->> 'reasoning'
  ) returning id, created_at into v_source_row_id, v_created_at;
  update public.morning_loop_trial_usage set
    product_evaluation_successes = product_evaluation_successes + 1, updated_at = now()
    where user_id = p_user_id;

  v_result := p_result_payload || jsonb_build_object('created_at', v_created_at);
  insert into public.morning_loop_trial_operations(user_id, feature, request_id, request_fingerprint, source_row_id, result_payload)
    values (p_user_id, 'product_evaluation', p_request_id, p_request_fingerprint, v_source_row_id, v_result);
  return jsonb_build_object('status', 'success', 'result', v_result);
end;
$$;

revoke all on function public.finalize_daily_brief(uuid, text, text, date, boolean, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.persist_product_evaluation(uuid, text, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.finalize_daily_brief(uuid, text, text, date, boolean, jsonb, jsonb, jsonb, jsonb, jsonb) to service_role;
grant execute on function public.persist_product_evaluation(uuid, text, text, jsonb, jsonb) to service_role;

create function public.get_morning_loop_trial_operation(
  p_user_id uuid,
  p_feature text,
  p_request_id text,
  p_request_fingerprint text
) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare v_operation public.morning_loop_trial_operations%rowtype;
begin
  if p_user_id is null or p_feature is null or p_feature not in ('daily_brief', 'product_evaluation') or
     p_request_id is null or length(p_request_id) = 0 or length(p_request_id) > 128 or
     p_request_fingerprint is null or length(p_request_fingerprint) <> 64 then
    raise exception 'invalid_morning_loop_request_identity';
  end if;
  select * into v_operation from public.morning_loop_trial_operations
    where user_id = p_user_id and feature = p_feature and request_id = p_request_id;
  if not found then return null; end if;
  if v_operation.request_fingerprint <> p_request_fingerprint then
    raise exception 'morning_loop_request_id_reused';
  end if;
  if p_feature = 'daily_brief' then
    if v_operation.source_row_id is null or not exists (
      select 1 from public.daily_briefs b
      where b.id = v_operation.source_row_id and b.user_id = p_user_id
    ) then raise exception 'morning_loop_result_deleted'; end if;
    return jsonb_build_object('status', 'replay', 'brief', v_operation.result_payload -> 'brief');
  end if;
  if v_operation.source_row_id is null or not exists (
    select 1 from public.user_product_evaluations e
    where e.id = v_operation.source_row_id and e.user_id = p_user_id
  ) then raise exception 'morning_loop_result_deleted'; end if;
  return jsonb_build_object('status', 'replay', 'result', v_operation.result_payload);
end;
$$;
revoke all on function public.get_morning_loop_trial_operation(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.get_morning_loop_trial_operation(uuid, text, text, text) to service_role;

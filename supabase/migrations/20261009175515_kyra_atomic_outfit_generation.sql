-- Kyra's create_outfit tool must share the durable daily generation quota
-- while persisting the outfit and marking its quota operation complete in
-- the same transaction. A separate idempotency row also covers Premium
-- operations, which do not reserve a free-tier allowance.
create table public.kyra_outfit_generation_operations (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  request_fingerprint text not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  reservation_id uuid references public.outfit_generation_reservations(id) on delete set null,
  result_payload jsonb not null check (jsonb_typeof(result_payload) = 'object'),
  created_at timestamptz not null default now(),
  primary key (user_id, request_id),
  unique (reservation_id)
);
alter table public.kyra_outfit_generation_operations enable row level security;
revoke all on public.kyra_outfit_generation_operations from public, anon, authenticated;
grant select, insert, update, delete on public.kyra_outfit_generation_operations to service_role;

create function public.commit_kyra_outfit_generation(
  p_user_id uuid,
  p_request_id uuid,
  p_fingerprint text,
  p_reservation_id uuid,
  p_outfit jsonb,
  p_result jsonb,
  p_now timestamptz
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_existing public.kyra_outfit_generation_operations%rowtype;
  v_reservation public.outfit_generation_reservations%rowtype;
  v_is_premium boolean;
  v_graph text;
  v_name text;
  v_description text;
  v_tags jsonb;
  v_score integer;
  v_items jsonb;
  v_locked jsonb;
  v_allow_products boolean;
  v_item jsonb;
  v_item_id uuid;
  v_product_id uuid;
  v_role text;
  v_category text;
  v_ordinal integer;
  v_count integer;
  v_has_top boolean := false;
  v_has_bottom boolean := false;
  v_has_shoes boolean := false;
  v_has_dress boolean := false;
  v_locked_role text;
  v_outfit_id uuid;
  v_result jsonb;
  v_result_array jsonb;
begin
  if p_user_id is null or p_request_id is null or p_now is null
     or p_fingerprint is null or p_fingerprint !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(p_outfit) is distinct from 'object'
     or jsonb_typeof(p_result) is distinct from 'object' then
    raise exception 'kyra_outfit_request_invalid';
  end if;

  -- The service-only caller is bound to the authenticated user by the Edge
  -- Function before invoking this RPC. Serialize retries of the same turn.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('kyra-outfit:' || p_user_id::text || ':' || p_request_id::text, 0)
  );
  select * into v_existing
    from public.kyra_outfit_generation_operations
    where user_id = p_user_id and request_id = p_request_id
    for update;
  if found then
    if v_existing.request_fingerprint <> p_fingerprint then
      raise exception 'kyra_outfit_request_id_reused';
    end if;
    return v_existing.result_payload;
  end if;

  if p_reservation_id is null then
    select exists (
      select 1 from public.subscriptions s
      where s.user_id = p_user_id
        and s.status::text in ('trialing', 'active', 'in_grace_period')
        and (s.expires_at is null or s.expires_at > p_now)
    ) into v_is_premium;
    if not v_is_premium then raise exception 'outfit_generation_reservation_required'; end if;
  else
    select * into v_reservation
      from public.outfit_generation_reservations r
      where r.id = p_reservation_id and r.user_id = p_user_id
      for update;
    if not found
       or v_reservation.request_id <> p_request_id
       or v_reservation.request_fingerprint <> p_fingerprint
       or v_reservation.state <> 'reserved'
       or v_reservation.expires_at <= p_now
       or v_reservation.quota_date <> (p_now at time zone 'UTC')::date then
      raise exception 'outfit_generation_reservation_unavailable';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'outfit-generation:' || p_user_id::text || ':' || v_reservation.quota_date::text,
        0
      )
    );
  end if;

  v_name := nullif(btrim(p_outfit->>'name'), '');
  v_description := nullif(btrim(p_outfit->>'description'), '');
  v_tags := p_outfit->'occasion_tags';
  v_items := p_outfit->'items';
  v_locked := coalesce(p_outfit->'locked_item_ids', '[]'::jsonb);
  if p_outfit ? 'allow_product_candidates'
     and (p_outfit->>'allow_product_candidates') not in ('true','false') then
    raise exception 'kyra_outfit_request_invalid';
  end if;
  v_allow_products := coalesce((p_outfit->>'allow_product_candidates')::boolean, false);
  if v_name is not null and char_length(v_name) > 120 then raise exception 'kyra_outfit_name_invalid'; end if;
  if v_description is not null and char_length(v_description) > 500 then raise exception 'kyra_outfit_description_invalid'; end if;
  if jsonb_typeof(v_tags) is distinct from 'array' or jsonb_array_length(v_tags) > 10 then
    raise exception 'kyra_outfit_tags_invalid';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_tags) tag
    where jsonb_typeof(tag) <> 'string' or char_length(tag #>> '{}') > 80
  ) then raise exception 'kyra_outfit_tags_invalid'; end if;
  if (p_outfit->>'compatibility_score') !~ '^(0|[1-9][0-9]?|100)$'
     or (p_outfit->>'compatibility_score')::integer > 100 then
    raise exception 'kyra_outfit_score_invalid';
  end if;
  v_score := (p_outfit->>'compatibility_score')::integer;
  if jsonb_typeof(v_items) is distinct from 'array' then raise exception 'kyra_outfit_items_invalid'; end if;
  v_count := jsonb_array_length(v_items);
  if v_count < 1 or v_count > 12 then raise exception 'kyra_outfit_item_count_invalid'; end if;
  if jsonb_typeof(v_locked) is distinct from 'array' or jsonb_array_length(v_locked) > 12 then
    raise exception 'kyra_outfit_locked_items_invalid';
  end if;
  select p.wardrobe_graph::text into v_graph from public.profiles p where p.id = p_user_id;
  if v_graph is null then raise exception 'kyra_outfit_profile_unavailable'; end if;

  for v_item, v_ordinal in
    select value, ordinality::integer from jsonb_array_elements(v_items) with ordinality
  loop
    if jsonb_typeof(v_item) <> 'object'
       or (v_item->>'sort_order') !~ '^(0|[1-9][0-9]*)$'
       or (v_item->>'sort_order')::integer <> v_ordinal - 1 then
      raise exception 'kyra_outfit_items_invalid';
    end if;
    v_role := v_item->>'role';
    if v_role not in ('top','bottom','outerwear','shoes','accessory','watch','fragrance','dress','skirt') then
      raise exception 'kyra_outfit_role_invalid';
    end if;
    v_item_id := null;
    v_product_id := null;
    if nullif(v_item->>'closet_item_id', '') is not null then
      if (v_item->>'closet_item_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         or nullif(v_item->>'product_candidate_id', '') is not null then
        raise exception 'kyra_outfit_items_invalid';
      end if;
      v_item_id := (v_item->>'closet_item_id')::uuid;
      select ci.category::text into v_category from public.closet_items ci
        where ci.id = v_item_id and ci.user_id = p_user_id and ci.archived_at is null
        for update;
      if v_category is null then raise exception 'kyra_outfit_item_unavailable'; end if;
      if v_category <> v_role then raise exception 'kyra_outfit_role_mismatch'; end if;
      v_has_top := v_has_top or v_role = 'top';
      v_has_bottom := v_has_bottom or v_role = 'bottom';
      v_has_shoes := v_has_shoes or v_role = 'shoes';
      v_has_dress := v_has_dress or v_role = 'dress';
    elsif nullif(v_item->>'product_candidate_id', '') is not null then
      if not v_allow_products
         or (v_item->>'product_candidate_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         or nullif(v_item->>'closet_item_id', '') is not null then
        raise exception 'kyra_outfit_product_unavailable';
      end if;
      v_product_id := (v_item->>'product_candidate_id')::uuid;
      select pc.category::text into v_category from public.product_candidates pc where pc.id = v_product_id;
      if not found then raise exception 'kyra_outfit_product_unavailable'; end if;
      if v_category is not null and v_category <> v_role then raise exception 'kyra_outfit_role_mismatch'; end if;
      v_has_top := v_has_top or v_role = 'top';
      v_has_bottom := v_has_bottom or v_role = 'bottom';
      v_has_shoes := v_has_shoes or v_role = 'shoes';
      v_has_dress := v_has_dress or v_role = 'dress';
    else
      raise exception 'kyra_outfit_items_invalid';
    end if;
  end loop;

  if (v_graph = 'menswear_3_role' and not (v_has_top and v_has_bottom and v_has_shoes))
     or (v_graph = 'womenswear' and not (
       (v_has_dress and v_has_shoes) or (v_has_top and v_has_bottom and v_has_shoes)
     )) then
    raise exception 'kyra_outfit_minimum_roles_not_met';
  end if;

  for v_item in select value from jsonb_array_elements(v_locked)
  loop
    if jsonb_typeof(v_item) <> 'string'
       or (v_item #>> '{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'kyra_outfit_locked_items_invalid';
    end if;
    v_item_id := (v_item #>> '{}')::uuid;
    select ci.category::text into v_locked_role from public.closet_items ci
      where ci.id = v_item_id and ci.user_id = p_user_id and ci.archived_at is null
      for update;
    if v_locked_role is null or not exists (
      select 1 from jsonb_array_elements(v_items) entry
      where entry->>'closet_item_id' = v_item_id::text
    ) then raise exception 'kyra_outfit_locked_item_missing'; end if;
    if exists (
      select 1 from jsonb_array_elements(v_items) entry
      where entry->>'role' = v_locked_role
        and coalesce(entry->>'closet_item_id','') <> v_item_id::text
    ) then raise exception 'kyra_outfit_locked_role_conflict'; end if;
  end loop;

  insert into public.outfits(user_id, name, description, occasion_tags, compatibility_score, source)
    values (p_user_id, v_name, v_description, v_tags, v_score, 'kyra_suggested')
    returning id into v_outfit_id;
  insert into public.outfit_items(outfit_id, user_id, closet_item_id, product_candidate_id, role, sort_order)
    select v_outfit_id, p_user_id,
      nullif(entry->>'closet_item_id','')::uuid,
      nullif(entry->>'product_candidate_id','')::uuid,
      (entry->>'role')::public.clothing_category,
      (entry->>'sort_order')::integer
    from jsonb_array_elements(v_items) entry;

  v_result := p_result || jsonb_build_object(
    'outfit_id', v_outfit_id,
    'source', 'kyra_suggested'
  );
  if p_reservation_id is not null then
    update public.outfit_generation_daily_usage
      set successful_count = successful_count + 1
      where user_id = p_user_id and quota_date = v_reservation.quota_date;
    if not found then raise exception 'outfit_generation_usage_unavailable'; end if;
    v_result_array := jsonb_build_array(v_result);
    update public.outfit_generation_reservations
      set state = 'committed', result_payload = v_result_array, finished_at = p_now
      where id = p_reservation_id;
  end if;
  insert into public.kyra_outfit_generation_operations(
    user_id, request_id, request_fingerprint, reservation_id, result_payload
  ) values (p_user_id, p_request_id, p_fingerprint, p_reservation_id, v_result);
  return v_result;
end;
$$;
revoke all on function public.commit_kyra_outfit_generation(uuid,uuid,text,uuid,jsonb,jsonb,timestamptz)
  from public, anon, authenticated;
grant execute on function public.commit_kyra_outfit_generation(uuid,uuid,text,uuid,jsonb,jsonb,timestamptz)
  to service_role;

-- New free conversations are counted under a per-owner/day transaction lock.
-- The app only starts conversations through /kyra/respond, so clients cannot
-- bypass the cap by inserting directly through the Data API.
revoke insert on public.kyra_threads from public, anon, authenticated;
grant insert on public.kyra_threads to service_role;

create table public.kyra_conversation_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  quota_date date not null,
  successful_count integer not null check (successful_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, quota_date)
);
alter table public.kyra_conversation_daily_usage enable row level security;
revoke all on public.kyra_conversation_daily_usage from public, anon, authenticated;
grant select, insert, update, delete on public.kyra_conversation_daily_usage to service_role;
-- Carry today's pre-migration conversations into the durable counter. Earlier
-- Kyra enforced the cap by counting existing threads, including any created
-- while a subscription was active; this preserves that already-visible usage.
insert into public.kyra_conversation_daily_usage(user_id,quota_date,successful_count)
select t.user_id, (clock_timestamp() at time zone 'UTC')::date, count(*)::integer
from public.kyra_threads t
where (t.created_at at time zone 'UTC')::date = (clock_timestamp() at time zone 'UTC')::date
group by t.user_id
on conflict (user_id,quota_date) do nothing;

create table public.kyra_thread_creation_operations (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  request_fingerprint text not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  thread_id uuid references public.kyra_threads(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (user_id,request_id)
);
alter table public.kyra_thread_creation_operations enable row level security;
revoke all on public.kyra_thread_creation_operations from public, anon, authenticated;
grant select, insert, update, delete on public.kyra_thread_creation_operations to service_role;

create function public.create_kyra_thread_with_daily_limit(
  p_user_id uuid,
  p_title text,
  p_limit integer,
  p_now timestamptz,
  p_request_id uuid,
  p_fingerprint text
) returns table(
  thread_id uuid,
  allowed boolean,
  limit_count integer,
  remaining integer,
  resets_at timestamptz,
  replayed boolean,
  thread_deleted boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_is_premium boolean;
  v_quota_date date;
  v_day_start timestamptz;
  v_reset timestamptz;
  v_thread_id uuid;
  v_usage_count integer;
  v_existing public.kyra_thread_creation_operations%rowtype;
begin
  if p_user_id is null or p_now is null or p_limit < 1 or p_limit > 100
     or p_request_id is null or p_fingerprint is null or p_fingerprint !~ '^[0-9a-f]{64}$'
     or p_title is null or char_length(btrim(p_title)) not between 1 and 60 then
    raise exception 'kyra_thread_request_invalid';
  end if;
  v_day_start := date_trunc('day', p_now at time zone 'UTC') at time zone 'UTC';
  v_quota_date := (p_now at time zone 'UTC')::date;
  v_reset := v_day_start + interval '1 day';
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('kyra-thread-request:' || p_user_id::text || ':' || p_request_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('kyra-thread:' || p_user_id::text || ':' || v_quota_date::text, 0)
  );

  select exists (
    select 1 from public.subscriptions s
    where s.user_id = p_user_id
      and s.status::text in ('trialing', 'active', 'in_grace_period')
      and (s.expires_at is null or s.expires_at > p_now)
  ) into v_is_premium;

  select * into v_existing from public.kyra_thread_creation_operations o
    where o.user_id = p_user_id and o.request_id = p_request_id for update;
  if found then
    if v_existing.request_fingerprint <> p_fingerprint then
      raise exception 'kyra_thread_request_id_reused';
    end if;
    if v_existing.thread_id is null then
      return query select null::uuid, false, p_limit, 0, v_reset, true, true;
      return;
    end if;
    if not v_is_premium then
      select u.successful_count into v_usage_count from public.kyra_conversation_daily_usage u
        where u.user_id = p_user_id and u.quota_date = v_quota_date;
      if not found then v_usage_count := 0; end if;
    end if;
    return query select v_existing.thread_id, true, p_limit,
      case when v_is_premium then p_limit else greatest(p_limit - v_usage_count, 0) end,
      v_reset, true, false;
    return;
  end if;

  if v_is_premium then
    -- Mark the day initialized without charging Premium starts. If the user
    -- later lapses today, those conversations remain uncharged.
    insert into public.kyra_conversation_daily_usage(user_id,quota_date,successful_count)
      values (p_user_id,v_quota_date,0) on conflict (user_id,quota_date) do nothing;
  else
    select u.successful_count into v_usage_count from public.kyra_conversation_daily_usage u
      where u.user_id = p_user_id and u.quota_date = v_quota_date for update;
    if not found then
      -- Preserve today's pre-migration usage the first time this ledger is
      -- touched. Subsequent deletions cannot refund an already-started chat.
      select count(*)::integer into v_usage_count from public.kyra_threads t
        where t.user_id = p_user_id and t.created_at >= v_day_start and t.created_at < v_reset;
      insert into public.kyra_conversation_daily_usage(user_id,quota_date,successful_count)
        values (p_user_id,v_quota_date,v_usage_count);
    end if;
    if v_usage_count >= p_limit then
      return query select null::uuid, false, p_limit, 0, v_reset, false, false;
      return;
    end if;
  end if;

  insert into public.kyra_threads(user_id, title)
    values (p_user_id, btrim(p_title)) returning id into v_thread_id;
  if not v_is_premium then
    update public.kyra_conversation_daily_usage
      set successful_count = successful_count + 1, updated_at = p_now
      where user_id = p_user_id and quota_date = v_quota_date;
  end if;
  insert into public.kyra_thread_creation_operations(
    user_id,request_id,request_fingerprint,thread_id
  ) values (p_user_id,p_request_id,p_fingerprint,v_thread_id);
  return query select v_thread_id, true, p_limit,
    case when v_is_premium then p_limit else greatest(p_limit - v_usage_count - 1, 0) end,
    v_reset, false, false;
end;
$$;
revoke all on function public.create_kyra_thread_with_daily_limit(uuid,text,integer,timestamptz,uuid,text)
  from public, anon, authenticated;
grant execute on function public.create_kyra_thread_with_daily_limit(uuid,text,integer,timestamptz,uuid,text)
  to service_role;

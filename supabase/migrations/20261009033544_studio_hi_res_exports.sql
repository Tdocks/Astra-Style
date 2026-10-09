-- One explicit Premium hi-res render per source generation. The row is a
-- normal Studio job/allowance so existing retry, retention, and account
-- deletion machinery remains authoritative.
alter table public.studio_generations
  add column hi_res_source_id uuid references public.studio_generations(id) on delete set null;
create unique index studio_hi_res_source_once
  on public.studio_generations(hi_res_source_id)
  where hi_res_source_id is not null and retry_of is null;
create index studio_hi_res_source_live_idx
  on public.studio_generations(hi_res_source_id) where hi_res_source_id is not null and deleted_at is null;

-- Standard failed-job retries reuse their allowance and must continue to
-- protect the original draft source until the retried export is removed.
create function public.inherit_studio_hi_res_source() returns trigger
language plpgsql security invoker set search_path='' as $$
declare v_source_id uuid;
begin
  if new.retry_of is not null then
    select hi_res_source_id into v_source_id from public.studio_generations
      where id=new.retry_of and user_id=new.user_id;
    new.hi_res_source_id:=v_source_id;
  end if;
  return new;
end;
$$;
revoke all on function public.inherit_studio_hi_res_source() from public,anon,authenticated;
create trigger studio_hi_res_retry_source before insert on public.studio_generations
  for each row execute function public.inherit_studio_hi_res_source();

create function public.enqueue_studio_hi_res_export(
  p_user_id uuid,
  p_source_generation_id uuid,
  p_provider text,
  p_consent_acknowledged boolean default false,
  p_consent_terms_version text default null
) returns setof public.studio_generations
language plpgsql security invoker set search_path='' as $$
declare
  v_source public.studio_generations;
  v_existing public.studio_generations;
  v_new public.studio_generations;
  v_payload jsonb;
  v_allowance uuid;
  v_premium boolean;
begin
  -- Serialize against same-user allowance reservations and source deletion.
  perform pg_advisory_xact_lock(hashtextextended('studio:'||p_user_id::text,0));
  select * into v_source from public.studio_generations
    where id=p_source_generation_id and user_id=p_user_id for update;
  if not found or v_source.status <> 'complete' or v_source.deleted_at is not null
    or (v_source.retention_expires_at is not null and v_source.retention_expires_at<=clock_timestamp())
    or coalesce(v_source.prompt_payload->>'resolution','draft') <> 'draft'
    or v_source.hi_res_source_id is not null
    or (coalesce(v_source.reference_image_path,'')<>'' and
      (length(v_source.reference_image_path)>512 or v_source.reference_image_path like '%..%'
        or v_source.reference_image_path like '/%'))
    or (coalesce(v_source.reference_image_path,'')<>'' and
      coalesce(v_source.prompt_payload->>'mode','reference') not in ('inspiration','closet_inspiration') and
      left(lower(v_source.reference_image_path),length('users/'||lower(p_user_id::text)||'/references/')) <>
        'users/'||lower(p_user_id::text)||'/references/')
    or (coalesce(v_source.reference_image_path,'')<>'' and
      coalesce(v_source.prompt_payload->>'mode','reference') in ('inspiration','closet_inspiration') and
      not exists(select 1 from public.studio_generations parent
        where parent.user_id=p_user_id and parent.result_image_path=v_source.reference_image_path
          and parent.status='complete' and parent.deleted_at is null
          and (parent.retention_expires_at is null or parent.retention_expires_at>clock_timestamp())))
    or v_source.result_image_path is distinct from
      ('users/'||lower(p_user_id::text)||'/studio/'||lower(p_source_generation_id::text)||'/result.png') then
    raise exception 'studio_export_source_unavailable';
  end if;
  if not exists(select 1 from storage.objects where bucket_id='user-content'
    and name=v_source.result_image_path) then
    raise exception 'studio_export_source_unavailable';
  end if;
  if coalesce(v_source.reference_image_path,'')<>'' and not exists(
    select 1 from storage.objects where bucket_id='user-content' and name=v_source.reference_image_path
  ) then
    raise exception 'studio_export_source_unavailable';
  end if;

  -- Existing accepted work remains addressable if the subscription changes;
  -- no second allowance is reserved on an idempotent replay.
  select candidate.* into v_existing from public.studio_generations candidate
    where candidate.hi_res_source_id=p_source_generation_id and candidate.user_id=p_user_id
      and not exists(select 1 from public.studio_generations successor
        where successor.retry_of=candidate.id and successor.user_id=p_user_id)
    order by candidate.created_at desc,candidate.id desc limit 1;
  if found then
    if v_existing.deleted_at is not null then raise exception 'studio_export_already_removed'; end if;
    return next v_existing; return;
  end if;

  if p_provider='mock' then raise exception 'studio_hi_res_provider_unavailable'; end if;

  select exists(select 1 from public.subscriptions where user_id=p_user_id
    and status in ('trialing','active','in_grace_period','in_billing_retry')
    and (expires_at is null or expires_at>clock_timestamp())) into v_premium;
  if not v_premium then raise exception 'studio_hi_res_premium_required'; end if;
  if coalesce(v_source.reference_image_path,'')<>'' and
    coalesce(v_source.prompt_payload->>'mode','reference') not in ('inspiration','closet_inspiration') and
    (p_consent_acknowledged is distinct from true or p_consent_terms_version is distinct from '2026-08-17') then
    raise exception 'studio_export_consent_required';
  end if;

  -- Keep the prompt/garments/controls/reference byte-for-byte equivalent as
  -- JSON; only the quality tier and a separate fresh consent receipt differ.
  v_payload := jsonb_set(coalesce(v_source.prompt_payload,'{}'::jsonb),'{resolution}','"hi_res"'::jsonb,true);
  v_payload := jsonb_set(v_payload,'{hi_res_source_generation_id}',to_jsonb(v_source.id::text),true);
  if coalesce(v_source.reference_image_path,'')<>'' and
    coalesce(v_source.prompt_payload->>'mode','reference') not in ('inspiration','closet_inspiration') then
    v_payload := jsonb_set(v_payload,'{hi_res_export_consent}',jsonb_build_object(
      'acknowledged',true,
      'terms_version',p_consent_terms_version,
      'attested_at',clock_timestamp()
    ),true);
  end if;

  insert into public.studio_allowances(user_id) values(p_user_id) returning id into v_allowance;
  insert into public.studio_generations(
    user_id,reference_image_path,outfit_id,prompt_payload,status,provider,allowance_id,hi_res_source_id
  ) values (
    p_user_id,v_source.reference_image_path,v_source.outfit_id,v_payload,'queued',p_provider,v_allowance,v_source.id
  ) returning * into v_new;
  update public.studio_allowances set latest_generation_id=v_new.id where id=v_allowance;
  return next v_new;
end;
$$;
revoke all on function public.enqueue_studio_hi_res_export(uuid,uuid,text,boolean,text)
  from public,anon,authenticated;
grant execute on function public.enqueue_studio_hi_res_export(uuid,uuid,text,boolean,text)
  to service_role;

-- Keep source images and their row alive while the separately retained export
-- still depends on them. The next retention sweep can expire the source after
-- that child has itself been deleted or expired.
create or replace function public.prepare_studio_retention(p_limit integer default 25) returns integer
language plpgsql security invoker set search_path='' as $$
declare g public.studio_generations; n integer:=0;
begin
  if not exists(select 1 from public.studio_retention_config where singleton and enabled) then return 0; end if;
  for g in select * from public.studio_generations s
    where s.deleted_at is null and s.status in ('complete','failed') and s.retention_expires_at < now()
      and not exists(select 1 from public.studio_lookbook_entries e where e.generation_id=s.id)
      and not exists(select 1 from public.studio_generations dependent
        where dependent.id<>s.id and dependent.deleted_at is null and s.result_image_path is not null
          and (dependent.reference_image_path=s.result_image_path or dependent.hi_res_source_id=s.id))
    order by s.retention_expires_at,s.id limit least(greatest(p_limit,1),100) for update of s skip locked
  loop
    if exists(select 1 from public.studio_lookbook_entries where generation_id=g.id)
      or exists(select 1 from public.studio_generations dependent
        where dependent.id<>g.id and dependent.deleted_at is null and dependent.hi_res_source_id=g.id) then
      continue;
    end if;
    update public.studio_generations set deleted_at=now() where id=g.id;
    insert into public.studio_retention_jobs(user_id,generation_id,generation_key,result_image_path)
      values(g.user_id,g.id,g.id,g.result_image_path) on conflict(generation_id) do nothing;
    n:=n+1;
  end loop;
  return n;
end;
$$;
revoke all on function public.prepare_studio_retention(integer) from public,anon,authenticated;
grant execute on function public.prepare_studio_retention(integer) to service_role;

create or replace function public.prepare_studio_deletion(p_user_id uuid,p_generation_id uuid)
returns public.studio_retention_jobs language plpgsql security invoker set search_path='' as $$
declare g public.studio_generations; j public.studio_retention_jobs;
begin
  select * into g from public.studio_generations where id=p_generation_id and user_id=p_user_id for update;
  if not found then
    select * into j from public.studio_retention_jobs where generation_key=p_generation_id and user_id=p_user_id and kind='studio';
    if not found then raise exception 'studio_delete_unavailable'; end if;
    return j;
  end if;
  if g.deleted_at is not null then
    select * into j from public.studio_retention_jobs where generation_id=g.id and user_id=p_user_id;
    if not found then raise exception 'studio_delete_unavailable'; end if;
    return j;
  end if;
  if g.status not in ('complete','failed') then raise exception 'studio_delete_in_progress'; end if;
  if (g.result_image_path is not null and exists(select 1 from public.studio_generations d
    where d.id<>g.id and d.deleted_at is null and d.reference_image_path=g.result_image_path))
    or exists(select 1 from public.studio_generations d
      where d.hi_res_source_id=g.id and d.user_id=p_user_id and d.deleted_at is null) then
    raise exception 'studio_delete_has_variations';
  end if;
  update public.studio_generations set deleted_at=now() where id=g.id;
  insert into public.studio_retention_jobs(user_id,generation_id,generation_key,result_image_path)
    values(g.user_id,g.id,g.id,g.result_image_path) returning * into j;
  return j;
end;
$$;
revoke all on function public.prepare_studio_deletion(uuid,uuid) from public,anon,authenticated;
grant execute on function public.prepare_studio_deletion(uuid,uuid) to service_role;

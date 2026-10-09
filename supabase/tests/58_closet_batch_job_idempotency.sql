-- Retry-safe closet batch enqueue identity: unique per authenticated owner,
-- preserving RLS isolation and accepting pre-migration jobs with NULL keys.
begin;

-- The global RLS harness intentionally grants broad client DML; restore the
-- production server-owned job boundary before checking it.
revoke all on public.closet_analysis_jobs from anon, authenticated;
grant select on public.closet_analysis_jobs to authenticated;

do $$
begin
  if has_table_privilege('authenticated', 'public.closet_analysis_jobs', 'INSERT') or
     has_table_privilege('authenticated', 'public.closet_analysis_jobs', 'UPDATE') or
     has_table_privilege('authenticated', 'public.closet_analysis_jobs', 'DELETE') or
     has_table_privilege('authenticated', 'public.closet_analysis_jobs', 'TRUNCATE') or
     has_table_privilege('authenticated', 'public.closet_analysis_jobs', 'REFERENCES') or
     has_table_privilege('authenticated', 'public.closet_analysis_jobs', 'TRIGGER') or
     has_table_privilege('anon', 'public.closet_analysis_jobs', 'INSERT') or
     has_table_privilege('anon', 'public.closet_analysis_jobs', 'UPDATE') then
    raise exception 'client role can mutate server-owned closet batch jobs';
  end if;
  if has_table_privilege('anon', 'public.closet_analysis_jobs', 'DELETE') or
     has_table_privilege('anon', 'public.closet_analysis_jobs', 'TRUNCATE') or
     has_table_privilege('anon', 'public.closet_analysis_jobs', 'REFERENCES') or
     has_table_privilege('anon', 'public.closet_analysis_jobs', 'TRIGGER') then
    raise exception 'anonymous client has privileged closet job access';
  end if;
  if not has_table_privilege('authenticated', 'public.closet_analysis_jobs', 'SELECT') or
     not has_table_privilege('service_role', 'public.closet_analysis_jobs', 'SELECT') or
     not has_table_privilege('service_role', 'public.closet_analysis_jobs', 'INSERT') or
     not has_table_privilege('service_role', 'public.closet_analysis_jobs', 'UPDATE') then
    raise exception 'owner reads or service batch processing grants are missing';
  end if;
end;
$$;

do $$
declare
  owner_id uuid := '58000000-0000-4000-8000-000000000001';
  peer_id uuid := '58000000-0000-4000-8000-000000000002';
  owner_job_id uuid := '58100000-0000-4000-8000-000000000001';
  peer_job_id uuid := '58100000-0000-4000-8000-000000000002';
  legacy_job_id uuid := '58100000-0000-4000-8000-000000000003';
  duplicate_rejected boolean := false;
  changed_rows integer;
  claimed_at timestamptz := clock_timestamp();
  first_token uuid := '58200000-0000-4000-8000-000000000001';
  recovery_token uuid := '58200000-0000-4000-8000-000000000002';
begin
  insert into auth.users(id, email, is_anonymous) values
    (owner_id, owner_id || '@batch-idempotency.invalid', false),
    (peer_id, peer_id || '@batch-idempotency.invalid', false);

  insert into public.closet_analysis_jobs(
    id, user_id, items, results, idempotency_key, request_hash
  ) values
    (owner_job_id, owner_id, '[]'::jsonb, '[]'::jsonb, 'retry-key', repeat('a', 64)),
    (peer_job_id, peer_id, '[]'::jsonb, '[]'::jsonb, 'retry-key', repeat('b', 64)),
    (legacy_job_id, owner_id, '[]'::jsonb, '[]'::jsonb, null, null);

  begin
    insert into public.closet_analysis_jobs(
      user_id, items, results, idempotency_key, request_hash
    ) values (owner_id, '[]'::jsonb, '[]'::jsonb, 'retry-key', repeat('c', 64));
  exception when unique_violation then
    duplicate_rejected := true;
  end;
  if not duplicate_rejected then
    raise exception 'owner reused a batch idempotency key with a duplicate row';
  end if;

  if (select count(*) from public.closet_analysis_jobs where id = legacy_job_id) <> 1 then
    raise exception 'legacy job without an idempotency key was not preserved';
  end if;

  -- A second poll cannot claim an active worker, but can recover an expired
  -- lease. The expired worker's token cannot overwrite the recovered result.
  update public.closet_analysis_jobs
    set status = 'generating', processing_token = first_token,
        processing_until = claimed_at + interval '60 seconds'
    where id = owner_job_id and status in ('queued', 'generating')
      and (processing_until is null or processing_until < claimed_at);
  get diagnostics changed_rows = row_count;
  if changed_rows <> 1 then raise exception 'first poll failed to claim the job'; end if;

  update public.closet_analysis_jobs
    set processing_token = recovery_token,
        processing_until = claimed_at + interval '61 seconds'
    where id = owner_job_id and status in ('queued', 'generating')
      and (processing_until is null or processing_until < claimed_at + interval '1 second');
  get diagnostics changed_rows = row_count;
  if changed_rows <> 0 then raise exception 'a second poll stole an unexpired claim'; end if;

  update public.closet_analysis_jobs
    set processing_token = recovery_token,
        processing_until = claimed_at + interval '121 seconds'
    where id = owner_job_id and status in ('queued', 'generating')
      and (processing_until is null or processing_until < claimed_at + interval '61 seconds');
  get diagnostics changed_rows = row_count;
  if changed_rows <> 1 then raise exception 'expired claim was not recoverable'; end if;

  update public.closet_analysis_jobs
    set status = 'complete', results = '[{"request_id":"stale"}]'::jsonb,
        processing_token = null, processing_until = null
    where id = owner_job_id and processing_token = first_token;
  get diagnostics changed_rows = row_count;
  if changed_rows <> 0 then raise exception 'expired worker token committed stale results'; end if;

  update public.closet_analysis_jobs
    set status = 'complete', results = '[{"request_id":"fresh"}]'::jsonb,
        processing_token = null, processing_until = null
    where id = owner_job_id and processing_token = recovery_token;
  get diagnostics changed_rows = row_count;
  if changed_rows <> 1 then raise exception 'recovered worker could not commit its result'; end if;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"58000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
do $$
begin
  if (select count(*) from public.closet_analysis_jobs where idempotency_key = 'retry-key') <> 1 then
    raise exception 'owner cannot see only its own idempotent batch job';
  end if;
  begin
    update public.closet_analysis_jobs
      set processing_token = '58200000-0000-4000-8000-000000000003'
      where idempotency_key = 'retry-key';
    raise exception 'authenticated client mutated a batch claim';
  exception when insufficient_privilege then
    null;
  end;
  begin
    insert into public.closet_analysis_jobs(user_id, items, results)
      values ('58000000-0000-4000-8000-000000000001', '[]'::jsonb, '[]'::jsonb);
    raise exception 'authenticated client inserted a fabricated batch job';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"58000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
do $$
begin
  if (select count(*) from public.closet_analysis_jobs where idempotency_key = 'retry-key') <> 1 then
    raise exception 'peer cannot see only its own same-key batch job';
  end if;
end;
$$;

reset role;
rollback;

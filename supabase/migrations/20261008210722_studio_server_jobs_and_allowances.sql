-- Studio writes are server-authoritative. Keep caller-scoped reads/storage.
-- Reservations prevent concurrent free jobs; only successful renders consume
-- the allowance permanently. Deleting a successful preview does not refund it.
create table public.studio_allowances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  consumed_at timestamptz,
  released_at timestamptz,
  latest_generation_id uuid,
  constraint studio_allowance_final_state check (consumed_at is null or released_at is null)
);
create index studio_allowances_user_active on public.studio_allowances(user_id) where released_at is null;
alter table public.studio_allowances enable row level security;
revoke all on public.studio_allowances from public, anon, authenticated;
grant all on public.studio_allowances to service_role;
grant select on public.studio_allowances to authenticated;
create policy studio_allowances_select_own on public.studio_allowances for select to authenticated
  using (user_id=(select auth.uid()));

alter table public.studio_generations add column allowance_id uuid references public.studio_allowances(id);
alter table public.studio_generations add column retry_of uuid references public.studio_generations(id) on delete set null;
alter table public.studio_generations add column claim_token uuid;
alter table public.studio_generations add column claim_expires_at timestamptz;
grant select, insert, update on public.studio_generations to service_role;
grant select on public.outfits, public.subscriptions to service_role;
create index studio_generations_allowance_idx on public.studio_generations(allowance_id);
create unique index studio_one_retry_per_job on public.studio_generations(retry_of) where retry_of is not null;

-- Existing hard-deleted trial history cannot be reconstructed. Preserve all
-- available history conservatively; pre-migration retries lack lineage.
insert into public.studio_allowances(id,user_id,created_at,consumed_at,released_at,latest_generation_id)
select id,user_id,created_at,
  case when status='complete' then updated_at end,
  case when status='failed' and coalesce(prompt_payload->>'is_retryable_failure','false') <> 'true' then updated_at end,id
from public.studio_generations;
update public.studio_generations set allowance_id=id;
create function public.enqueue_studio_generation(
  p_user_id uuid, p_reference_image_path text, p_outfit_id uuid,
  p_prompt_payload jsonb, p_provider text, p_retry_of uuid default null
) returns setof public.studio_generations
language plpgsql security invoker set search_path='' as $$
declare
  v_allowance uuid;
  v_original public.studio_generations;
  v_existing public.studio_generations;
  v_new public.studio_generations;
  v_premium boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('studio:' || p_user_id::text,0));
  if p_retry_of is not null then
    select * into v_original from public.studio_generations
      where id=p_retry_of and user_id=p_user_id and deleted_at is null;
    if v_original.id is null or v_original.status <> 'failed'
       or coalesce(v_original.prompt_payload->>'is_retryable_failure','false') <> 'true' then
      raise exception 'studio_retry_unavailable';
    end if;
    select * into v_existing from public.studio_generations where retry_of=p_retry_of and user_id=p_user_id;
    if v_existing.id is not null then return next v_existing; return; end if;
    v_allowance := v_original.allowance_id;
    if not exists (select 1 from public.studio_allowances where id=v_allowance and released_at is null and consumed_at is null) then
      raise exception 'studio_retry_unavailable';
    end if;
  else
    select exists (select 1 from public.subscriptions where user_id=p_user_id
      and status in ('trialing','active','in_grace_period','in_billing_retry')
      and (expires_at is null or expires_at > now())) into v_premium;
    if not v_premium and exists (select 1 from public.studio_allowances where user_id=p_user_id and released_at is null) then
      raise exception 'studio_trial_exhausted';
    end if;
    insert into public.studio_allowances(user_id) values(p_user_id) returning id into v_allowance;
  end if;
  if p_outfit_id is not null and not exists (select 1 from public.outfits where id=p_outfit_id and user_id=p_user_id) then
    raise exception 'studio_outfit_unavailable';
  end if;
  insert into public.studio_generations(user_id,reference_image_path,outfit_id,prompt_payload,status,provider,allowance_id,retry_of)
    values(p_user_id,p_reference_image_path,p_outfit_id,p_prompt_payload,'queued',p_provider,v_allowance,p_retry_of) returning * into v_new;
  update public.studio_allowances set latest_generation_id=v_new.id where id=v_allowance;
  return next v_new;
end;
$$;
revoke all on function public.enqueue_studio_generation(uuid,text,uuid,jsonb,text,uuid) from public,anon,authenticated;
grant execute on function public.enqueue_studio_generation(uuid,text,uuid,jsonb,text,uuid) to service_role;

create function public.claim_studio_generation(p_user_id uuid,p_generation_id uuid,p_claim_token uuid)
returns setof public.studio_generations language sql security invoker set search_path='' as $$
  update public.studio_generations set claim_token=p_claim_token,claim_expires_at=now()+interval '180 seconds'
    where id=p_generation_id and user_id=p_user_id and deleted_at is null
      and status in ('queued','generating')
      and (claim_expires_at is null or claim_expires_at < now()) returning *;
$$;
revoke all on function public.claim_studio_generation(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.claim_studio_generation(uuid,uuid,uuid) to service_role;

-- Trigger state comes from a server-only UPDATE or an owned terminal DELETE.
-- The consumed record survives deletion of the preview, but not the account.
create function public.reconcile_studio_allowance() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_allowance uuid;
begin
  if tg_op='DELETE' then v_allowance:=old.allowance_id; else v_allowance:=new.allowance_id; end if;
  if tg_op <> 'DELETE' and new.status='complete' then
    update public.studio_allowances set consumed_at=coalesce(consumed_at,now()),released_at=null where id=v_allowance;
  elsif (tg_op='DELETE' and exists (select 1 from public.studio_allowances where id=v_allowance and latest_generation_id=old.id))
     or (tg_op<>'DELETE' and new.status='failed' and coalesce(new.prompt_payload->>'is_retryable_failure','false') <> 'true') then
    update public.studio_allowances set released_at=now() where id=v_allowance and consumed_at is null
      and not exists (select 1 from public.studio_generations where allowance_id=v_allowance and deleted_at is null
        and status in ('queued','generating','complete'));
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.reconcile_studio_allowance() from public,anon,authenticated;
create trigger studio_allowance_status after update of status on public.studio_generations
  for each row execute function public.reconcile_studio_allowance();
create trigger studio_allowance_delete after delete on public.studio_generations
  for each row execute function public.reconcile_studio_allowance();

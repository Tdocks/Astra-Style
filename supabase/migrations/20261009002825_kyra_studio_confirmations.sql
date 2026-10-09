-- A model response or client-writable message cannot attest cost confirmation.
-- These records are created only by the verified server orchestration path.
grant select on public.kyra_threads, public.kyra_messages to service_role;
alter table public.kyra_messages add constraint kyra_message_scope_unique unique(id,thread_id,user_id);
alter table public.kyra_threads add constraint kyra_thread_owner_unique unique(id,user_id);
create table public.kyra_studio_confirmations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  thread_id uuid not null,
  prompt_message_id uuid not null,
  selection jsonb not null check(jsonb_typeof(selection)='object'),
  selection_key text not null check(length(selection_key) between 1 and 4000),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '30 minutes',
  closed_at timestamptz,
  foreign key(thread_id,user_id) references public.kyra_threads(id,user_id) on delete cascade,
  foreign key(prompt_message_id,thread_id,user_id) references public.kyra_messages(id,thread_id,user_id) on delete cascade,
  check(expires_at>created_at)
);
create unique index kyra_studio_one_pending on public.kyra_studio_confirmations(user_id,thread_id) where closed_at is null;
alter table public.kyra_studio_confirmations enable row level security;
revoke all on public.kyra_studio_confirmations from public,anon,authenticated;
grant select,insert,update,delete on public.kyra_studio_confirmations to service_role;

create function public.prepare_kyra_studio_confirmation(p_user_id uuid,p_thread_id uuid,p_prompt_message_id uuid,p_selection jsonb,p_selection_key text)
returns setof public.kyra_studio_confirmations
language plpgsql security invoker set search_path='' as $$
declare existing public.kyra_studio_confirmations;
begin
  if not exists(select 1 from public.kyra_threads where id=p_thread_id and user_id=p_user_id) then
    raise exception 'kyra_thread_unavailable';
  end if;
  if not exists(select 1 from public.kyra_messages where id=p_prompt_message_id and thread_id=p_thread_id and user_id=p_user_id and role='assistant' and nullif(btrim(content),'') is not null) then
    raise exception 'kyra_prompt_unavailable';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('kyra-studio:'||p_thread_id::text,0));
  select * into existing from public.kyra_studio_confirmations where user_id=p_user_id and thread_id=p_thread_id and closed_at is null;
  if existing.id is not null and existing.expires_at>now() and existing.selection_key=p_selection_key and existing.selection=p_selection then
    update public.kyra_studio_confirmations set prompt_message_id=p_prompt_message_id, expires_at=now()+interval '30 minutes' where id=existing.id returning * into existing;
    return next existing; return;
  end if;
  update public.kyra_studio_confirmations set closed_at=now() where user_id=p_user_id and thread_id=p_thread_id and closed_at is null;
  insert into public.kyra_studio_confirmations(user_id,thread_id,prompt_message_id,selection,selection_key)
    values(p_user_id,p_thread_id,p_prompt_message_id,p_selection,p_selection_key) returning * into existing;
  return next existing;
end;
$$;
revoke all on function public.prepare_kyra_studio_confirmation(uuid,uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.prepare_kyra_studio_confirmation(uuid,uuid,uuid,jsonb,text) to service_role;

-- Private saved-look collections, distinct from public worn outfits (ADR 0023).
create table public.studio_lookbooks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80 and name !~ '^[[:space:]]*$'),
  created_at timestamptz not null default now(),
  unique(id,user_id)
);
create index studio_lookbooks_user_created_idx on public.studio_lookbooks(user_id,created_at desc,id);
alter table public.studio_generations add constraint studio_generation_owner_unique unique(id,user_id);
alter table public.studio_generations add column retention_expires_at timestamptz default (now()+interval '30 days');
update public.studio_generations set retention_expires_at=created_at+interval '30 days';
create table public.studio_lookbook_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  lookbook_id uuid not null,
  generation_id uuid not null,
  created_at timestamptz not null default now(),
  constraint studio_lookbook_entries_collection_owner_fk foreign key(lookbook_id,user_id)
    references public.studio_lookbooks(id,user_id) on delete cascade,
  constraint studio_lookbook_entries_generation_owner_fk foreign key(generation_id,user_id)
    references public.studio_generations(id,user_id) on delete cascade,
  unique(lookbook_id,generation_id)
);
create index studio_lookbook_entries_user_collection_idx on public.studio_lookbook_entries(user_id,lookbook_id,created_at desc,id);
create index studio_lookbook_entries_generation_idx on public.studio_lookbook_entries(generation_id,user_id);
alter table public.studio_lookbooks enable row level security;
alter table public.studio_lookbook_entries enable row level security;
revoke all on public.studio_lookbooks,public.studio_lookbook_entries from public,anon;
grant select,insert,update,delete on public.studio_lookbooks to authenticated;
grant select,insert,delete on public.studio_lookbook_entries to authenticated;
grant all on public.studio_lookbooks,public.studio_lookbook_entries to service_role;
create policy studio_lookbooks_owned on public.studio_lookbooks for all to authenticated
  using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy studio_lookbook_entries_read on public.studio_lookbook_entries for select to authenticated
  using(user_id=(select auth.uid()) and exists(select 1 from public.studio_generations g
    where g.id=generation_id and g.user_id=(select auth.uid()) and g.status='complete' and g.deleted_at is null and g.result_image_path is not null));
create policy studio_lookbook_entries_add on public.studio_lookbook_entries for insert to authenticated
  with check(user_id=(select auth.uid()) and exists(select 1 from public.studio_generations g
    where g.id=generation_id and g.user_id=(select auth.uid()) and g.status='complete' and g.deleted_at is null and g.result_image_path is not null));
create policy studio_lookbook_entries_remove on public.studio_lookbook_entries for delete to authenticated
  using(user_id=(select auth.uid()));

-- Users cannot modify server-owned job columns directly. This trigger only
-- changes retention for the same owned generation referenced by the entry.
create function public.reconcile_saved_studio_retention() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_generation uuid; v_user uuid;
begin
  if tg_op='DELETE' then v_generation:=old.generation_id; v_user:=old.user_id;
  else v_generation:=new.generation_id; v_user:=new.user_id; end if;
  update public.studio_generations g set retention_expires_at=case
    when exists(select 1 from public.studio_lookbook_entries e where e.generation_id=v_generation and e.user_id=v_user)
      then null
    else now()+interval '30 days' end
    where g.id=v_generation and g.user_id=v_user;
  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.reconcile_saved_studio_retention() from public,anon,authenticated;
create trigger studio_saved_retention after insert or delete on public.studio_lookbook_entries
  for each row execute function public.reconcile_saved_studio_retention();

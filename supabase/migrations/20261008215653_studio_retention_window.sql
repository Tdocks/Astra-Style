-- Admin-configurable window, measured from completed output, not enqueue time.
alter table public.studio_retention_config add column output_retention_days integer not null default 30
  check(output_retention_days between 1 and 365);
alter table public.studio_generations alter column retention_expires_at set default null;
create function public.set_studio_retention_window() returns trigger
language plpgsql security definer set search_path='' as $$
declare days integer;
begin
  select output_retention_days into days from public.studio_retention_config where singleton;
  days:=coalesce(days,30);
  if tg_op='INSERT' then
    new.retention_expires_at:=coalesce(new.retention_expires_at,now()+make_interval(days=>days));
  elsif new.status='complete' and old.status<>'complete' then
    new.retention_expires_at:=case when exists(select 1 from public.studio_lookbook_entries where generation_id=new.id)
      then null else now()+make_interval(days=>days) end;
  end if;
  return new;
end;
$$;
revoke all on function public.set_studio_retention_window() from public,anon,authenticated;
create trigger studio_retention_window before insert or update of status on public.studio_generations
  for each row execute function public.set_studio_retention_window();

create or replace function public.reconcile_saved_studio_retention() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_generation uuid; v_user uuid; days integer;
begin
  if tg_op='DELETE' then v_generation:=old.generation_id; v_user:=old.user_id;
  else v_generation:=new.generation_id; v_user:=new.user_id; end if;
  select output_retention_days into days from public.studio_retention_config where singleton;
  update public.studio_generations g set retention_expires_at=case
    when exists(select 1 from public.studio_lookbook_entries e where e.generation_id=v_generation and e.user_id=v_user)
      then null
    else now()+make_interval(days=>coalesce(days,30)) end
    where g.id=v_generation and g.user_id=v_user;
  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.reconcile_saved_studio_retention() from public,anon,authenticated;

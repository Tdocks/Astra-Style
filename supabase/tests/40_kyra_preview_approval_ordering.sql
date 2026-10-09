begin;
do $$
declare u uuid:=gen_random_uuid(); t uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
  a uuid; j uuid; replay uuid; blocked boolean;
begin
  insert into auth.users(id,email) values(u,u||'@approval-order.invalid');
  insert into public.kyra_threads(id,user_id,title) values(t,u,'Fixture');
  insert into public.kyra_messages(id,thread_id,user_id,role,content)
    values(m,t,u,'assistant','Generate this preview? It uses one preview.');
  perform set_config('role','service_role',true);
  select id into a from public.prepare_kyra_studio_confirmation(u,t,m,'{"selection":"one"}','one');
  update public.kyra_studio_confirmations set closed_at=now() where id=a;
  blocked:=false;
  begin perform public.enqueue_studio_generation_idempotent(u,a,repeat('a',64),'',null,'{"mode":"inspiration"}','fixture');
  exception when others then if sqlerrm='studio_confirmation_unavailable' then blocked:=true; else raise; end if; end;
  if not blocked then raise exception 'Cancelled approval queued a job'; end if;
  if exists(select 1 from public.studio_allowances where user_id=u) then raise exception 'Cancelled approval spent allowance'; end if;
  select id into a from public.prepare_kyra_studio_confirmation(u,t,m,'{"selection":"one"}','one');
  update public.kyra_studio_confirmations set created_at=now()-interval '1 hour',expires_at=now()-interval '1 second' where id=a;
  blocked:=false;
  begin perform public.enqueue_studio_generation_idempotent(u,a,repeat('a',64),'',null,'{"mode":"inspiration"}','fixture');
  exception when others then if sqlerrm='studio_confirmation_unavailable' then blocked:=true; else raise; end if; end;
  if not blocked then raise exception 'Expired approval queued a job'; end if;
  select id into a from public.prepare_kyra_studio_confirmation(u,t,m,'{"selection":"one"}','one');
  select id into j from public.enqueue_studio_generation_idempotent(u,a,repeat('a',64),'',null,'{"mode":"inspiration"}','fixture');
  update public.kyra_studio_confirmations set closed_at=now() where id=a;
  select id into replay from public.enqueue_studio_generation_idempotent(u,a,repeat('a',64),'',null,'{"mode":"inspiration"}','fixture');
  if j is null or replay<>j then raise exception 'Closed accepted approval did not replay its job'; end if;
end;
$$;
rollback;

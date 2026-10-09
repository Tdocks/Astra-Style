begin;
do $$
declare owner_id uuid:=gen_random_uuid(); request_id uuid:=gen_random_uuid();
  first_id uuid; replay_id uuid; blocked boolean; n integer;
begin
  insert into auth.users(id,email) values(owner_id,owner_id||'@submission.invalid');
  perform set_config('role','service_role',true);
  select id into first_id from public.enqueue_studio_generation_idempotent(
    owner_id,request_id,repeat('a',64),'',null,'{"mode":"inspiration"}', 'fixture');
  select id into replay_id from public.enqueue_studio_generation_idempotent(
    owner_id,request_id,repeat('a',64),'',null,'{"mode":"inspiration"}', 'fixture');
  if first_id is null or replay_id<>first_id then raise exception 'Replay created another job'; end if;
  select count(*) into n from public.studio_allowances where user_id=owner_id;
  if n<>1 then raise exception 'Replay spent another allowance'; end if;
  blocked:=false;
  begin perform public.enqueue_studio_generation_idempotent(
    owner_id,request_id,repeat('b',64),'',null,'{"mode":"inspiration"}', 'fixture');
  exception when others then if sqlerrm='studio_request_conflict' then blocked:=true; else raise; end if; end;
  if not blocked then raise exception 'Key reused for another request'; end if;
  update public.studio_generations set deleted_at=now() where id=first_id;
  blocked:=false;
  begin perform public.enqueue_studio_generation_idempotent(
    owner_id,request_id,repeat('a',64),'',null,'{"mode":"inspiration"}', 'fixture');
  exception when others then if sqlerrm='studio_request_removed' then blocked:=true; else raise; end if; end;
  if not blocked then raise exception 'Removed request resurrected a job'; end if;
  perform set_config('role','authenticated',true);
  blocked:=false;
  begin perform public.enqueue_studio_generation_idempotent(
    owner_id,request_id,repeat('a',64),'',null,'{"mode":"inspiration"}', 'fixture');
  exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'Authenticated caller reached privileged enqueue'; end if;
end;
$$;
rollback;

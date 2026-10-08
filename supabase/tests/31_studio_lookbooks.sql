-- Scratch fixtures only. Assert actual RLS, composite ownership and retention.
begin;
do $$
declare
  u uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid();
  own_book uuid:=gen_random_uuid(); second_book uuid:=gen_random_uuid(); peer_book uuid:=gen_random_uuid();
  own_gen uuid:=gen_random_uuid(); queued_gen uuid:=gen_random_uuid(); peer_gen uuid:=gen_random_uuid();
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
  n integer; blocked boolean;
begin
  if has_function_privilege('authenticated','public.reconcile_saved_studio_retention()','EXECUTE')
     or has_table_privilege('authenticated','public.studio_lookbook_entries','UPDATE')
     or has_table_privilege('anon','public.studio_lookbooks','SELECT')
     or has_table_privilege('anon','public.studio_lookbook_entries','SELECT') then
    raise exception 'Collection trigger or immutable entry grants are open';
  end if;
  insert into auth.users(id,email) values(u,u::text||'@collections.invalid'),(peer,peer::text||'@collections.invalid');
  insert into public.studio_allowances(id,user_id,consumed_at) values(a,u,now()),(b,u,null),(c,peer,now());
  insert into public.studio_generations(id,user_id,reference_image_path,status,result_image_path,allowance_id)
    values(own_gen,u,'','complete','users/'||u||'/studio/'||own_gen||'/result.png',a),
          (queued_gen,u,'','queued',null,b),(peer_gen,peer,'','complete','peer/result.png',c);
  insert into public.studio_lookbooks(id,user_id,name) values(peer_book,peer,'Peer private');
  insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(peer,peer_book,peer_gen);
  perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
  perform set_config('role','authenticated',true);
  select count(*) into n from public.studio_lookbooks where id=peer_book;
  if n<>0 then raise exception 'Peer collection visible'; end if;
  select count(*) into n from public.studio_lookbook_entries where generation_id=peer_gen;
  if n<>0 then raise exception 'Peer entry visible'; end if;
  delete from public.studio_lookbook_entries where generation_id=peer_gen;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'Peer entry deleted'; end if;
  update public.studio_lookbooks set name='Changed' where id=peer_book;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'Peer collection renamed'; end if;
  delete from public.studio_lookbooks where id=peer_book;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'Peer collection deleted'; end if;
  blocked:=false;
  begin insert into public.studio_lookbooks(user_id,name) values(peer,'Cross owner');
  exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'Cross-owner collection insert admitted'; end if;
  blocked:=false;
  begin insert into public.studio_lookbooks(user_id,name) values(u,E'\n');
  exception when check_violation then blocked:=true; end;
  if not blocked then raise exception 'Blank collection admitted'; end if;
  blocked:=false;
  begin insert into public.studio_lookbooks(user_id,name) values(u,repeat('x',81));
  exception when check_violation then blocked:=true; end;
  if not blocked then raise exception 'Overlong collection admitted'; end if;
  insert into public.studio_lookbooks(id,user_id,name) values(own_book,u,'Everyday'),(second_book,u,'Work');
  update public.studio_lookbooks set name='Daily' where id=own_book;
  blocked:=false;
  begin insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(u,own_book,peer_gen);
  exception when insufficient_privilege then blocked:=true;
    when raise_exception then if sqlerrm<>'studio_save_unavailable' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Peer generation linked'; end if;
  blocked:=false;
  begin insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(u,peer_book,own_gen);
  exception when foreign_key_violation then blocked:=true; end;
  if not blocked then raise exception 'Peer collection linked'; end if;
  blocked:=false;
  begin insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(u,own_book,queued_gen);
  exception when insufficient_privilege then blocked:=true;
    when raise_exception then if sqlerrm<>'studio_save_unavailable' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Unfinished generation saved'; end if;
  insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(u,own_book,own_gen);
  insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(u,own_book,own_gen)
    on conflict(lookbook_id,generation_id) do nothing;
  select count(*) into n from public.studio_lookbook_entries where lookbook_id=own_book;
  if n<>1 then raise exception 'Duplicate save was not idempotent'; end if;
  if not exists(select 1 from public.studio_generations where id=own_gen and retention_expires_at is null) then
    raise exception 'Saving failed to retain generation'; end if;
  blocked:=false;
  begin update public.studio_generations set retention_expires_at=null where id=queued_gen;
  exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'Client could change retention directly'; end if;
  insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(u,second_book,own_gen);
  delete from public.studio_lookbook_entries where lookbook_id=own_book and generation_id=own_gen;
  if not exists(select 1 from public.studio_generations where id=own_gen and retention_expires_at is null) then
    raise exception 'Removing one of multiple saves expired generation'; end if;
  delete from public.studio_lookbooks where id=second_book;
  if not exists(select 1 from public.studio_generations where id=own_gen and retention_expires_at between now()+interval '29 days' and now()+interval '31 days') then
    raise exception 'Removing final collection did not reset the window'; end if;
  insert into public.studio_lookbook_entries(user_id,lookbook_id,generation_id) values(u,own_book,own_gen);
  perform set_config('role','service_role',true);
  delete from public.studio_generations where id=own_gen;
  if exists(select 1 from public.studio_lookbook_entries where generation_id=own_gen) then
    raise exception 'Deleted estimate left entries'; end if;
  if not exists(select 1 from public.studio_allowances where id=a and consumed_at is not null) then
    raise exception 'Deleting saved estimate refunded success'; end if;
  -- Auth identity deletion belongs to GoTrue/admin; use the scratch owner to
  -- prove its FK cascade rather than giving service_role direct auth DML.
  perform set_config('role','none',true);
  delete from auth.users where id in (u,peer);
  if exists(select 1 from public.studio_lookbooks where user_id in(u,peer))
     or exists(select 1 from public.studio_lookbook_entries where user_id in(u,peer)) then
    raise exception 'Account erasure left collections'; end if;
  raise notice 'Studio collection ownership, save/remove retention, idempotency and erasure checks passed';
end;
$$;
rollback;

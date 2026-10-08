begin;
do $$
declare
  u uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid(); key uuid:=gen_random_uuid();
  root uuid:=gen_random_uuid(); child uuid:=gen_random_uuid(); leaf uuid:=gen_random_uuid(); used_id uuid:=gen_random_uuid();
  p text; saved text; abandoned text; recent text; used text;
  j public.studio_retention_jobs; again public.studio_retention_jobs; token uuid:=gen_random_uuid(); blocked boolean;
begin
  if has_function_privilege('authenticated','public.prepare_reference_deletion(uuid,text)','EXECUTE')
    or has_function_privilege('anon','public.prepare_reference_retention(integer)','EXECUTE')
    or has_function_privilege('authenticated','public.guard_body_reference_photos()','EXECUTE') then
    raise exception 'Reference cleanup privilege boundary is open'; end if;
  insert into auth.users(id,email) values(u,u||'@references.invalid'),(peer,peer||'@references.invalid');
  p:='users/'||u||'/references/'||key||'.jpg';
  insert into public.body_profiles(user_id,appearance) values(u,jsonb_build_object('reference_selfie_paths',jsonb_build_array(p),'hair_color','brown'));
  insert into storage.objects(bucket_id,name) values('user-content',p);
  insert into public.studio_allowances(id,user_id) values(root,u),(child,u),(leaf,u),(used_id,u);
  insert into public.studio_generations(id,user_id,reference_image_path,status,result_image_path,allowance_id)
    values(root,u,p,'complete','users/'||u||'/studio/'||root||'/result.png',root),
      (child,u,'users/'||u||'/studio/'||root||'/result.png','complete','users/'||u||'/studio/'||child||'/result.png',child),
      (leaf,u,'users/'||u||'/studio/'||child||'/result.png','generating',null,leaf);
  blocked:=false;
  begin perform public.prepare_reference_deletion(u,p);
  exception when raise_exception then if sqlerrm<>'reference_photo_in_progress' then raise; end if; blocked:=true; end;
  if not blocked or exists(select 1 from public.studio_generations where user_id=u and deleted_at is not null)
    or exists(select 1 from public.studio_retention_jobs where user_id=u) then raise exception 'Active descendant caused partial erasure'; end if;
  update public.studio_generations set status='failed' where id=leaf;
  perform set_config('role','service_role',true);
  blocked:=false;
  begin perform public.prepare_reference_deletion(peer,p);
  exception when raise_exception then if sqlerrm<>'reference_photo_unavailable' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Peer erased a reference'; end if;
  select * into j from public.prepare_reference_deletion(u,p);
  select * into again from public.prepare_reference_deletion(u,p);
  if j.id<>again.id or j.kind<>'reference' or j.generation_id is not null then raise exception 'Reference queue is not idempotent'; end if;
  if (select count(*) from public.studio_generations where user_id=u and deleted_at is not null)<>3
    or (select count(*) from public.studio_retention_jobs where user_id=u)<>4 then raise exception 'Transitive cascade incomplete'; end if;
  if (select appearance->>'hair_color' from public.body_profiles where user_id=u)<>'brown'
    or (select appearance->'reference_selfie_paths' from public.body_profiles where user_id=u)<>'[]'::jsonb then raise exception 'Reference erasure changed unrelated profile data'; end if;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
  delete from storage.objects where bucket_id='user-content' and name=p;
  if not exists(select 1 from storage.objects where bucket_id='user-content' and name=p) then raise exception 'Client bypassed reference Storage fence'; end if;
  blocked:=false;
  begin update public.body_profiles set appearance=jsonb_set(appearance,'{reference_selfie_paths}',jsonb_build_array(p)) where user_id=u;
  exception when raise_exception then if sqlerrm<>'reference_photo_unavailable' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Stale profile resurrected erased reference'; end if;
  perform set_config('role','none',true);
  blocked:=false;
  begin insert into public.studio_generations(user_id,reference_image_path,status,allowance_id) values(u,p,'queued',leaf);
  exception when raise_exception then if sqlerrm<>'studio_source_unavailable' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Deleting reference accepted a new generation'; end if;
  perform public.claim_studio_deletion(u,j.id,token);
  blocked:=false;
  begin perform public.finish_studio_retention(j.id,token,true);
  exception when raise_exception then if sqlerrm<>'studio_retention_object_not_removed' then raise; end if; blocked:=true; end;
  if not blocked then raise exception 'Reference completed with its file still present'; end if;
  -- SQL removal below is solely a scratch-test stand-in for the Storage API.
  delete from storage.objects where bucket_id='user-content' and name=p;
  if not public.finish_studio_retention(j.id,token,true) then raise exception 'Reference completion failed'; end if;
  select * into again from public.prepare_reference_deletion(u,p);
  if again.id<>j.id or again.status<>'complete' then raise exception 'Completed reference retry lost identity'; end if;
  saved:='users/'||u||'/references/'||gen_random_uuid()||'.jpg';
  abandoned:='users/'||u||'/references/'||gen_random_uuid()||'.jpg';
  recent:='users/'||u||'/references/'||gen_random_uuid()||'.jpg';
  used:='users/'||u||'/references/'||gen_random_uuid()||'.jpg';
  update public.body_profiles set appearance=jsonb_set(appearance,'{reference_selfie_paths}',jsonb_build_array(saved)) where user_id=u;
  insert into storage.objects(bucket_id,name,created_at,updated_at)
    values('user-content',saved,now()-interval '3 days',now()-interval '3 days'),
      ('user-content',used,now()-interval '3 days',now()-interval '3 days'),
      ('user-content',abandoned,now()-interval '2 days',now()-interval '2 days'),
      ('user-content',recent,now()-interval '3 days',now());
  insert into public.studio_generations(user_id,reference_image_path,status,allowance_id) values(u,used,'failed',used_id);
  update public.studio_retention_config set enabled=true,reference_cleanup_enabled=false;
  if public.prepare_reference_retention(25)<>0 then raise exception 'Disabled reference cleanup performed work'; end if;
  update public.studio_retention_config set reference_cleanup_enabled=true;
  if public.prepare_reference_retention(1)<>1 then raise exception 'Old abandoned reference was not selected past protected older files'; end if;
  if not exists(select 1 from public.studio_retention_jobs where user_id=u and kind='reference' and result_image_path=abandoned)
    or exists(select 1 from public.studio_retention_jobs where user_id=u and kind='reference' and result_image_path in(saved,used,recent)) then
    raise exception 'Abandoned cleanup failed saved/used/recent protection'; end if;
  if public.prepare_reference_retention(25)<>0 then raise exception 'Pending reference queued twice'; end if;
  delete from auth.users where id=u;
  if exists(select 1 from public.studio_retention_jobs where user_id=u) then raise exception 'Reference queue survived account erasure'; end if;
  raise notice 'Reference ownership, recursive cascade, active protection, profile preservation, tombstones, Storage fence, idempotency and abandoned retention passed';
end;
$$;
rollback;

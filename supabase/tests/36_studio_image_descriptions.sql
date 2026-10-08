begin;
do $$
declare owner_id uuid:=gen_random_uuid(); peer_id uuid:=gen_random_uuid(); image_id uuid:=gen_random_uuid(); blocked boolean; n integer;
begin
  insert into auth.users(id,email) values(owner_id,owner_id||'@description.invalid'),(peer_id,peer_id||'@description.invalid');
  insert into public.studio_allowances(id,user_id,consumed_at) values(image_id,owner_id,now());
  insert into public.studio_generations(id,user_id,reference_image_path,status,prompt_payload,result_image_path,allowance_id)
    values(image_id,owner_id,'','complete','{"mode":"inspiration"}','fixture/result.png',image_id);
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  update public.studio_generations set alt_description='Navy trousers and white shirt' where id=image_id;
  get diagnostics n=row_count;
  if n<>1 then raise exception 'Owner cannot edit completed description'; end if;
  blocked:=false;
  begin update public.studio_generations set status='failed' where id=image_id;
  exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'Description grant reopened job status writes'; end if;
  blocked:=false;
  begin update public.studio_generations set alt_description=repeat('a',1001) where id=image_id;
  exception when check_violation then blocked:=true; end;
  if not blocked then raise exception 'Description length unbounded'; end if;
  update public.studio_generations set alt_description=null where id=image_id;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',peer_id,'role','authenticated')::text,true);
  update public.studio_generations set alt_description='Peer overwrite' where id=image_id;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'Peer edited description'; end if;
  perform set_config('role','service_role',true);
  update public.studio_generations set status='generating' where id=image_id;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  update public.studio_generations set alt_description='Active overwrite' where id=image_id;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'Active generation description edited'; end if;
  raise notice 'Description ownership, reset, length bounds, server status privilege and active-image fence passed';
end;
$$;
rollback;

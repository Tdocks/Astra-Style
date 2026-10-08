begin;
-- Test-only Storage privilege equivalent to the server Storage API boundary.
grant insert on storage.objects to service_role;
do $$
declare u uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid(); p text; old_path text; category text; blocked boolean; n integer;
begin
  insert into auth.users(id,email) values(u,u||'@guest-storage.invalid'),(peer,peer||'@guest-storage.invalid');
  old_path:='users/'||u||'/avatars/'||gen_random_uuid()||'.jpg';
  insert into storage.objects(bucket_id,name) values('user-content',old_path);
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','is_anonymous',true,
    'user_metadata',jsonb_build_object('is_anonymous',false))::text,true);
  for category in select unnest(array['closet','references','avatars']) loop
    p:='users/'||u||'/'||category||'/'||gen_random_uuid()||'.jpg'; blocked:=false;
    begin insert into storage.objects(bucket_id,name) values('user-content',p);
    exception when insufficient_privilege then blocked:=true; end;
    if not blocked then raise exception 'Guest uploaded a % image',category; end if;
  end loop;
  update storage.objects set metadata='{"probe":true}'::jsonb where bucket_id='user-content' and name=old_path;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'Guest replaced an existing image'; end if;
  if not exists(select 1 from storage.objects where bucket_id='user-content' and name=old_path) then
    raise exception 'Guest cannot read its owned server image'; end if;
  -- A signed permanent claim governs access, never editable user_metadata.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','is_anonymous',false,
    'user_metadata',jsonb_build_object('is_anonymous',true))::text,true);
  insert into storage.objects(bucket_id,name) values('user-content',p);
  update storage.objects set metadata='{"probe":true}'::jsonb where bucket_id='user-content' and name=old_path;
  get diagnostics n=row_count;
  if n<>1 then raise exception 'Permanent owner cannot replace its image'; end if;
  blocked:=false;
  begin insert into storage.objects(bucket_id,name) values('user-content','users/'||peer||'/closet/'||gen_random_uuid()||'.jpg');
  exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'Permanent caller crossed the owner fence'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  blocked:=false;
  begin insert into storage.objects(bucket_id,name) values('user-content','users/'||u||'/references/'||gen_random_uuid()||'.jpg');
  exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'Missing permanence claim did not fail closed'; end if;
  perform set_config('role','service_role',true);
  insert into storage.objects(bucket_id,name) values('user-content','users/'||u||'/studio/'||gen_random_uuid()||'/result.png');
  raise notice 'Guest Storage insert/update denial, metadata independence, owned reads, permanent writes, peer isolation and server output writes passed';
end;
$$;
rollback;

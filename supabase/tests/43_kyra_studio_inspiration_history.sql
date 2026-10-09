begin;
do $$
declare
  u uuid := gen_random_uuid();
  peer uuid := gen_random_uuid();
  thread_id uuid := gen_random_uuid();
  generation_id uuid := gen_random_uuid();
  message_id uuid := gen_random_uuid();
  n integer;
begin
  insert into auth.users(id, email)
  values (u, u || '@kyra-history.invalid'), (peer, peer || '@kyra-history.invalid');
  insert into public.kyra_threads(id, user_id, title)
  values (thread_id, u, 'Studio history fixture');
  insert into public.studio_allowances(id, user_id, consumed_at, latest_generation_id)
  values (generation_id, peer, now(), generation_id);
  insert into public.studio_generations(id, user_id, prompt_payload, status, result_image_path, allowance_id)
  values (
    generation_id,
    peer,
    '{"mode":"inspiration"}',
    'complete',
    'users/' || peer || '/studio/' || generation_id || '/result.png',
    generation_id
  );

  -- A caller may persist an opaque peer UUID in their own row, but that row
  -- does not grant access to the referenced generation or its private image.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u, 'role', 'authenticated')::text, true);
  insert into public.kyra_messages(id, thread_id, user_id, role, content, studio_generation_id)
  values (message_id, thread_id, u, 'user', 'Look at this image', generation_id);
  select count(*) into n from public.studio_generations where id = generation_id;
  if n <> 0 then raise exception 'Peer Studio generation became readable through its UUID'; end if;
  select count(*) into n from public.kyra_messages where id = message_id;
  if n <> 1 then raise exception 'Caller could not read their own opaque reference'; end if;

  perform set_config('role', 'service_role', true);
  delete from public.studio_generations where id = generation_id;
  select studio_generation_id into generation_id from public.kyra_messages where id = message_id;
  if generation_id is not null then raise exception 'Hard deletion did not clear Kyra image reference'; end if;
end;
$$;
rollback;

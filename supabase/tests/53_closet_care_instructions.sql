-- Scratch database only. Verifies the nullable care field follows the
-- existing closet row's owner RLS without new grants or policy changes.
begin;
do $$
declare
  owner_id uuid := gen_random_uuid();
  peer_id uuid := gen_random_uuid();
  item_id uuid := gen_random_uuid();
  affected integer;
begin
  insert into auth.users(id, email) values
    (owner_id, owner_id::text || '@care-test.invalid'),
    (peer_id, peer_id::text || '@care-test.invalid');
  insert into public.closet_items(id, user_id, name, category)
    values(item_id, owner_id, 'Care test shirt', 'top');

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
  update public.closet_items
    set care_instructions = 'Cold hand wash; lay flat to dry.'
    where id = item_id;
  if not exists (
    select 1 from public.closet_items
    where id = item_id and care_instructions = 'Cold hand wash; lay flat to dry.'
  ) then
    raise exception 'Owner could not persist or read its care instructions';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', peer_id, 'role', 'authenticated')::text, true);
  if exists (select 1 from public.closet_items where id = item_id) then
    raise exception 'Peer could read another owner care instructions';
  end if;
  update public.closet_items set care_instructions = 'Peer edit' where id = item_id;
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Peer changed another owner care instructions';
  end if;

  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  if exists (select 1 from public.closet_items where id = item_id) then
    raise exception 'Anonymous caller could read closet care instructions';
  end if;

  perform set_config('role', 'postgres', true);
  raise notice 'Closet care instructions nullable column and inherited owner RLS passed';
end;
$$;
rollback;

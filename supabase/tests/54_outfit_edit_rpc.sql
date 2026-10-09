-- Draft test for replace_outfit_items. Run after 20261009100000 migration
-- against the same scratch database used by scripts/run-rls-tests.sh.
\set ON_ERROR_STOP on
begin;

insert into auth.users(id, email) values
  ('d3400000-0000-4000-8000-000000000001', 'edit-owner@example.test'),
  ('d3400000-0000-4000-8000-000000000002', 'edit-peer@example.test');
insert into public.closet_items(id,user_id,name,category) values
  ('d3400000-0000-4000-8000-000000000011','d3400000-0000-4000-8000-000000000001','Owner top','top'),
  ('d3400000-0000-4000-8000-000000000012','d3400000-0000-4000-8000-000000000001','Owner bottom','bottom'),
  ('d3400000-0000-4000-8000-000000000013','d3400000-0000-4000-8000-000000000001','Owner jacket','outerwear'),
  ('d3400000-0000-4000-8000-000000000021','d3400000-0000-4000-8000-000000000002','Peer top','top'),
  ('d3400000-0000-4000-8000-000000000014','d3400000-0000-4000-8000-000000000001','Archived shoes','shoes');
update public.closet_items set archived_at='2026-10-08T12:00:00Z'::timestamptz where id='d3400000-0000-4000-8000-000000000014';
insert into public.outfits(id,user_id,name,source) values
  ('d3400000-0000-4000-8000-000000000031','d3400000-0000-4000-8000-000000000001','Original','user_created'),
  ('d3400000-0000-4000-8000-000000000032','d3400000-0000-4000-8000-000000000002','Peer outfit','user_created');
insert into public.outfit_items(outfit_id,user_id,closet_item_id,role,sort_order)
values ('d3400000-0000-4000-8000-000000000031','d3400000-0000-4000-8000-000000000001','d3400000-0000-4000-8000-000000000011','top',0);
insert into public.outfit_wears(id,user_id,outfit_id,worn_at)
values ('d3400000-0000-4000-8000-000000000041','d3400000-0000-4000-8000-000000000001','d3400000-0000-4000-8000-000000000031','2026-10-01T12:00:00Z');

-- Store the concurrency token in a transaction-local setting before
-- impersonating the API user; the test then needs no owner-only temp-table read.
select set_config('test.outfit_expected_updated_at', updated_at::text, true)
from public.outfits where id='d3400000-0000-4000-8000-000000000031';

set local role authenticated;
set local request.jwt.claims = '{"sub":"d3400000-0000-4000-8000-000000000001","role":"authenticated"}';

-- A successful edit preserves identity, replaces child rows atomically, and
-- updates only editable outfit fields.
do $$
declare v public.outfits%rowtype;
begin
  select * from public.replace_outfit_items(
    'd3400000-0000-4000-8000-000000000031',
    current_setting('test.outfit_expected_updated_at')::timestamptz,
    'Updated look', 'Kyra reason', 82::smallint,
    '[{"closet_item_id":"d3400000-0000-4000-8000-000000000012","role":"bottom","sort_order":0},{"closet_item_id":"d3400000-0000-4000-8000-000000000013","role":"outerwear","sort_order":1}]'
  ) into v;
  if v.id <> 'd3400000-0000-4000-8000-000000000031' or v.name <> 'Updated look' then
    raise exception 'edit changed outfit identity or failed to update metadata';
  end if;
  if (select count(*) from public.outfit_wears where outfit_id=v.id and id='d3400000-0000-4000-8000-000000000041' and worn_at='2026-10-01T12:00:00Z'::timestamptz) <> 1 then
    raise exception 'edit discarded or changed historical wear data';
  end if;
  if (select count(*) from public.outfit_items where outfit_id=v.id) <> 2
     or exists (select 1 from public.outfit_items where outfit_id=v.id and closet_item_id='d3400000-0000-4000-8000-000000000011') then
    raise exception 'edit did not replace the item set';
  end if;
end
$$;

-- A stale editor cannot overwrite the successful edit.
do $$
begin
  begin
    perform public.replace_outfit_items(
      'd3400000-0000-4000-8000-000000000031',
      (current_setting('test.outfit_expected_updated_at')::timestamptz - interval '1 day'),
      'Stale overwrite', null, 10::smallint,
      '[{"closet_item_id":"d3400000-0000-4000-8000-000000000011","role":"top","sort_order":0}]'
    );
    raise exception 'stale edit unexpectedly succeeded';
  exception when serialization_failure then
    null;
  end;
  if (select name from public.outfits where id='d3400000-0000-4000-8000-000000000031') <> 'Updated look' then
    raise exception 'stale edit changed outfit';
  end if;
end
$$;

-- Empty/oversized names fail before any child-row replacement.
do $$
begin
  begin
    perform public.replace_outfit_items(
      'd3400000-0000-4000-8000-000000000031',
      (select updated_at from public.outfits where id='d3400000-0000-4000-8000-000000000031'),
      '   ', null, 10::smallint,
      '[{"closet_item_id":"d3400000-0000-4000-8000-000000000011","role":"top","sort_order":0}]'
    );
    raise exception 'blank outfit name unexpectedly accepted';
  exception when invalid_parameter_value then
    null;
  end;
  if (select count(*) from public.outfit_items where outfit_id='d3400000-0000-4000-8000-000000000031') <> 2 then
    raise exception 'invalid name partially replaced child rows';
  end if;
end
$$;

-- Cross-owner, nonexistent, archived, and role-mismatched garments are
-- rejected before destructive replacement; the prior item rows survive.
do $$
begin
  begin
    perform public.replace_outfit_items(
      'd3400000-0000-4000-8000-000000000031',
      (select updated_at from public.outfits where id='d3400000-0000-4000-8000-000000000031'),
      'Peer reference', null, 10::smallint,
      '[{"closet_item_id":"d3400000-0000-4000-8000-000000000021","role":"top","sort_order":0}]'
    );
    raise exception 'peer item unexpectedly accepted';
  exception when insufficient_privilege then
    null;
  end;
  if (select count(*) from public.outfit_items where outfit_id='d3400000-0000-4000-8000-000000000031') <> 2 then
    raise exception 'rejected cross-owner edit partially changed child rows';
  end if;
end
$$;

-- Archived garments and role mismatches are rejected without a partial edit.
do $$
begin
  begin
    perform public.replace_outfit_items(
      'd3400000-0000-4000-8000-000000000031',
      (select updated_at from public.outfits where id='d3400000-0000-4000-8000-000000000031'),
      'Archived reference', null, 10::smallint,
      '[{"closet_item_id":"d3400000-0000-4000-8000-000000000014","role":"shoes","sort_order":0}]'
    );
    raise exception 'archived garment unexpectedly accepted';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.replace_outfit_items(
      'd3400000-0000-4000-8000-000000000031',
      (select updated_at from public.outfits where id='d3400000-0000-4000-8000-000000000031'),
      'Role mismatch', null, 10::smallint,
      '[{"closet_item_id":"d3400000-0000-4000-8000-000000000012","role":"top","sort_order":0}]'
    );
    raise exception 'role-mismatched garment unexpectedly accepted';
  exception when insufficient_privilege then
    null;
  end;
  if (select count(*) from public.outfit_items where outfit_id='d3400000-0000-4000-8000-000000000031') <> 2 then
    raise exception 'rejected archived/role-mismatched edit partially replaced items';
  end if;
end
$$;

-- Editing another user's outfit is indistinguishable from a missing outfit.
do $$
begin
  begin
    perform public.replace_outfit_items(
      'd3400000-0000-4000-8000-000000000032', now(), 'Peer outfit', null, 1::smallint,
      '[{"closet_item_id":"d3400000-0000-4000-8000-000000000011","role":"top","sort_order":0}]'
    );
    raise exception 'foreign outfit unexpectedly accepted';
  exception when no_data_found then
    null;
  end;
end
$$;

rollback;

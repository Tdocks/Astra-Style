-- Reference removal goes through the coordinated service-role deletion API.
-- Ordinary profile edits must not discard photos appended after their snapshot.
create function public.preserve_body_reference_associations() returns trigger
language plpgsql security invoker set search_path='' as $$
declare paths jsonb; p jsonb;
begin
  if current_setting('role',true)<>'authenticated' then return new; end if;
  if new.appearance ? 'reference_selfie_paths'
    and jsonb_typeof(new.appearance->'reference_selfie_paths')<>'array' then
    return new; -- Existing validation trigger rejects malformed arrays.
  end if;
  paths:=coalesce(new.appearance->'reference_selfie_paths','[]'::jsonb);
  for p in select value from jsonb_array_elements(coalesce(old.appearance->'reference_selfie_paths','[]'::jsonb)) loop
    if not paths @> jsonb_build_array(p) then paths:=paths||jsonb_build_array(p); end if;
  end loop;
  if jsonb_array_length(paths)>0 then
    new.appearance:=jsonb_set(new.appearance,'{reference_selfie_paths}',paths);
  end if;
  return new;
end;
$$;
revoke all on function public.preserve_body_reference_associations() from public,anon,authenticated;
-- Alphabetical ordering runs preservation before the existing tombstone guard.
create trigger body_reference_photo_append_guard before update of appearance on public.body_profiles
  for each row execute function public.preserve_body_reference_associations();
